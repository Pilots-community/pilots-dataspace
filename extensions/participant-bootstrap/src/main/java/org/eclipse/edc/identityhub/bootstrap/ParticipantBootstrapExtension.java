package org.eclipse.edc.identityhub.bootstrap;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.eclipse.edc.iam.did.spi.document.Service;
import org.eclipse.edc.iam.verifiablecredentials.spi.model.CredentialFormat;
import org.eclipse.edc.iam.verifiablecredentials.spi.model.CredentialSubject;
import org.eclipse.edc.iam.verifiablecredentials.spi.model.Issuer;
import org.eclipse.edc.iam.verifiablecredentials.spi.model.VerifiableCredential;
import org.eclipse.edc.iam.verifiablecredentials.spi.model.VerifiableCredentialContainer;
import org.eclipse.edc.identityhub.spi.did.DidDocumentService;
import org.eclipse.edc.identityhub.spi.participantcontext.ParticipantContextService;
import org.eclipse.edc.identityhub.spi.participantcontext.model.KeyDescriptor;
import org.eclipse.edc.identityhub.spi.participantcontext.model.ParticipantContext;
import org.eclipse.edc.identityhub.spi.participantcontext.model.ParticipantManifest;
import org.eclipse.edc.identityhub.spi.verifiablecredentials.model.VcStatus;
import org.eclipse.edc.identityhub.spi.verifiablecredentials.model.VerifiableCredentialResource;
import org.eclipse.edc.identityhub.spi.verifiablecredentials.store.CredentialStore;
import org.eclipse.edc.runtime.metamodel.annotation.Inject;
import org.eclipse.edc.runtime.metamodel.annotation.Setting;
import org.eclipse.edc.spi.monitor.Monitor;
import org.eclipse.edc.spi.security.Vault;
import org.eclipse.edc.spi.system.ServiceExtension;
import org.eclipse.edc.spi.system.ServiceExtensionContext;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Map;

public class ParticipantBootstrapExtension implements ServiceExtension {

    public static final String NAME = "Participant Bootstrap Extension";

    @Setting(value = "DSP protocol URL of the participant's ControlPlane")
    public static final String DSP_URL_PROPERTY = "edc.ih.participant.dsp.url";

    @Setting(value = "Path to pre-signed MembershipCredential JWT file")
    public static final String CREDENTIAL_PATH_PROPERTY = "edc.ih.participant.credential.path";

    @Inject
    private ParticipantContextService participantContextService;

    @Inject
    private DidDocumentService didDocumentService;

    @Inject
    private CredentialStore credentialStore;

    @Inject
    private Vault vault;

    private Monitor monitor;
    private String hostname;
    private int didPort;
    private int credentialsPort;
    private String credentialsPath;
    private boolean useHttps;
    private String dspUrl;
    private String credentialFilePath;

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public void initialize(ServiceExtensionContext context) {
        monitor = context.getMonitor();
        hostname = context.getSetting("edc.hostname", "localhost");
        didPort = Integer.parseInt(context.getSetting("web.http.did.port", "7093"));
        credentialsPort = Integer.parseInt(context.getSetting("web.http.credentials.port", "7091"));
        credentialsPath = context.getSetting("web.http.credentials.path", "/api/credentials");
        useHttps = Boolean.parseBoolean(context.getSetting("edc.iam.did.web.use.https", "false"));
        dspUrl = context.getSetting(DSP_URL_PROPERTY, null);
        credentialFilePath = context.getSetting(CREDENTIAL_PATH_PROPERTY, null);
    }

    @Override
    public void start() {
        if (dspUrl == null) {
            monitor.debug("Participant bootstrap: no DSP URL configured (%s), skipping".formatted(DSP_URL_PROPERTY));
            return;
        }

        // 1. Derive participant DID from hostname + port
        var encodedHostPort = hostname + "%3A" + didPort;
        var did = "did:web:" + encodedHostPort;

        // 2. Check idempotency — skip if context already exists
        if (participantContextService.getParticipantContext(did).succeeded()) {
            monitor.debug("Participant bootstrap: context already exists for '%s', skipping".formatted(did));
            return;
        }

        // 3. Build credential service URL
        var scheme = useHttps ? "https" : "http";
        var didBase64 = Base64.getEncoder().encodeToString(did.getBytes());
        var credentialServiceUrl = "%s://%s:%d%s/v1/participants/%s"
                .formatted(scheme, hostname, credentialsPort, credentialsPath, didBase64);

        // 4. Create participant context
        monitor.info("Participant bootstrap: creating context for '%s'".formatted(did));

        var manifest = ParticipantManifest.Builder.newInstance()
                .participantContextId(did)
                .did(did)
                .active(false)
                .key(KeyDescriptor.Builder.newInstance()
                        .keyId(did + "#key-1")
                        .privateKeyAlias(did + "-alias")
                        .keyGeneratorParams(Map.of("algorithm", "EdDSA", "curve", "Ed25519"))
                        .build())
                .serviceEndpoint(new Service("credentialservice-1", "CredentialService", credentialServiceUrl))
                .serviceEndpoint(new Service("dsp", "ProtocolEndpoint", dspUrl))
                .build();

        participantContextService.createParticipantContext(manifest)
                .onSuccess(response -> {
                    monitor.debug("Participant bootstrap: context created for '%s'".formatted(did));

                    // 5. Activate participant context
                    participantContextService.updateParticipant(did, ParticipantContext::activate)
                            .onSuccess(v -> monitor.debug("Participant bootstrap: context activated"))
                            .onFailure(f -> monitor.warning("Participant bootstrap: failed to activate: %s".formatted(f.getFailureDetail())));

                    // 6. Publish DID document
                    didDocumentService.publish(did)
                            .onSuccess(v -> monitor.info("Participant bootstrap: DID published for '%s'".formatted(did)))
                            .onFailure(f -> monitor.warning("Participant bootstrap: failed to publish DID: %s".formatted(f.getFailureDetail())));

                    // 7. Store STS client secret in vault
                    var clientSecret = response.clientSecret();
                    if (clientSecret != null) {
                        vault.storeSecret(did + "-sts-client-secret", clientSecret)
                                .onSuccess(v -> monitor.debug("Participant bootstrap: STS client secret stored in vault"))
                                .onFailure(f -> monitor.warning("Participant bootstrap: failed to store STS secret: %s".formatted(f.getFailureDetail())));
                    }

                    // 8. Store MembershipCredential if configured
                    storeCredential(did);
                })
                .onFailure(f -> monitor.severe("Participant bootstrap: failed to create context for '%s': %s".formatted(did, f.getFailureDetail())));
    }

    private void storeCredential(String did) {
        if (credentialFilePath == null) {
            monitor.debug("Participant bootstrap: no credential file configured, skipping VC storage");
            return;
        }

        var path = Path.of(credentialFilePath);
        if (!Files.exists(path)) {
            monitor.warning("Participant bootstrap: credential file not found: %s".formatted(credentialFilePath));
            return;
        }

        try {
            // Read JWT from file: { "credential": "eyJ..." }
            var content = Files.readString(path);
            var mapper = new ObjectMapper();
            var tree = mapper.readTree(content);
            var jwt = tree.get("credential").asText();

            // Decode JWT payload to extract VC fields
            var parts = jwt.split("\\.");
            var payloadJson = new String(Base64.getUrlDecoder().decode(padBase64(parts[1])));
            var payload = mapper.readTree(payloadJson);
            var vc = payload.get("vc");

            // Extract issuer
            var issuerNode = vc.get("issuer");
            var issuerDid = issuerNode.isTextual() ? issuerNode.asText() : issuerNode.get("id").asText();

            // Extract types
            var types = new ArrayList<String>();
            if (vc.has("type")) {
                for (var type : vc.get("type")) {
                    types.add(type.asText());
                }
            }

            // Extract dates
            var issuanceDate = Instant.parse(vc.get("issuanceDate").asText());
            var expirationDate = vc.has("expirationDate") ? Instant.parse(vc.get("expirationDate").asText()) : null;

            // Extract credential subject
            var subjectNode = vc.get("credentialSubject");
            var credentialSubject = CredentialSubject.Builder.newInstance()
                    .id(subjectNode.get("id").asText())
                    .claim("memberOf", subjectNode.get("memberOf").asText())
                    .claim("name", subjectNode.get("name").asText())
                    .claim("status", subjectNode.get("status").asText())
                    .build();

            // Build VerifiableCredential
            var vcBuilder = VerifiableCredential.Builder.newInstance()
                    .id(vc.get("id").asText())
                    .types(types)
                    .issuer(new Issuer(issuerDid))
                    .issuanceDate(issuanceDate)
                    .credentialSubject(credentialSubject);
            if (expirationDate != null) {
                vcBuilder.expirationDate(expirationDate);
            }
            var verifiableCredential = vcBuilder.build();

            // Build container and resource
            var container = new VerifiableCredentialContainer(jwt, CredentialFormat.VC1_0_JWT, verifiableCredential);
            var resource = VerifiableCredentialResource.Builder.newInstance()
                    .id("membership-credential")
                    .participantContextId(did)
                    .issuerId(issuerDid)
                    .holderId(did)
                    .state(VcStatus.ISSUED)
                    .credential(container)
                    .build();

            credentialStore.create(resource)
                    .onSuccess(v -> monitor.info("Participant bootstrap: MembershipCredential stored"))
                    .onFailure(f -> monitor.warning("Participant bootstrap: failed to store credential: %s".formatted(f.getFailureDetail())));

        } catch (Exception e) {
            monitor.warning("Participant bootstrap: failed to process credential file: %s".formatted(e.getMessage()));
        }
    }

    private String padBase64(String b64) {
        return switch (b64.length() % 4) {
            case 2 -> b64 + "==";
            case 3 -> b64 + "=";
            default -> b64;
        };
    }
}
