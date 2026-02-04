package org.eclipse.edc.demo.dcp.core;

import org.eclipse.edc.iam.decentralizedclaims.spi.scope.ScopeExtractorRegistry;
import org.eclipse.edc.iam.decentralizedclaims.spi.verification.SignatureSuiteRegistry;
import org.eclipse.edc.iam.verifiablecredentials.spi.VcConstants;
import org.eclipse.edc.iam.verifiablecredentials.spi.model.Issuer;
import org.eclipse.edc.iam.verifiablecredentials.spi.validation.TrustedIssuerRegistry;
import org.eclipse.edc.policy.context.request.spi.RequestCatalogPolicyContext;
import org.eclipse.edc.policy.context.request.spi.RequestContractNegotiationPolicyContext;
import org.eclipse.edc.policy.context.request.spi.RequestTransferProcessPolicyContext;
import org.eclipse.edc.policy.engine.spi.PolicyEngine;
import org.eclipse.edc.runtime.metamodel.annotation.Inject;
import org.eclipse.edc.security.signature.jws2020.Jws2020SignatureSuite;
import org.eclipse.edc.spi.system.ServiceExtension;
import org.eclipse.edc.spi.system.ServiceExtensionContext;
import org.eclipse.edc.spi.types.TypeManager;
import org.eclipse.edc.transform.spi.TypeTransformerRegistry;
import org.eclipse.edc.transform.transformer.edc.to.JsonValueToGenericTypeTransformer;

import java.util.Map;
import java.util.Set;

import static org.eclipse.edc.iam.verifiablecredentials.spi.validation.TrustedIssuerRegistry.WILDCARD;
import static org.eclipse.edc.spi.constants.CoreConstants.JSON_LD;

public class DcpPatchExtension implements ServiceExtension {

    public static final String NAME = "DCP Patch Extension";
    private static final String DEFAULT_ISSUER_DID = "did:web:did-server%3A9876";
    private static final String ISSUER_DID_SETTING = "edc.demo.dcp.issuer.did";

    @Inject
    private TypeManager typeManager;

    @Inject
    private PolicyEngine policyEngine;

    @Inject
    private SignatureSuiteRegistry signatureSuiteRegistry;

    @Inject
    private TrustedIssuerRegistry trustedIssuerRegistry;

    @Inject
    private ScopeExtractorRegistry scopeExtractorRegistry;

    @Inject
    private TypeTransformerRegistry typeTransformerRegistry;

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public void initialize(ServiceExtensionContext context) {
        var monitor = context.getMonitor().withPrefix("DcpPatch");

        // register JWS 2020 signature suite
        var suite = new Jws2020SignatureSuite(typeManager.getMapper(JSON_LD));
        signatureSuiteRegistry.register(VcConstants.JWS_2020_SIGNATURE_SUITE, suite);
        monitor.info("Registered JWS 2020 signature suite");

        // register the dataspace issuer as a trusted issuer
        var issuerDid = context.getSetting(ISSUER_DID_SETTING, DEFAULT_ISSUER_DID);
        trustedIssuerRegistry.register(new Issuer(issuerDid, Map.of()), WILDCARD);
        monitor.info("Registered trusted issuer: %s".formatted(issuerDid));

        // register a default scope provider that requests MembershipCredential for all DSP interactions
        var contextMappingFunction = new DefaultScopeMappingFunction(Set.of("org.eclipse.edc.vc.type:MembershipCredential:read"));

        policyEngine.registerPostValidator(RequestCatalogPolicyContext.class, contextMappingFunction::apply);
        policyEngine.registerPostValidator(RequestContractNegotiationPolicyContext.class, contextMappingFunction::apply);
        policyEngine.registerPostValidator(RequestTransferProcessPolicyContext.class, contextMappingFunction::apply);
        monitor.info("Registered scope mapping for MembershipCredential");

        // register scope extractor for DataAccess constraints
        scopeExtractorRegistry.registerScopeExtractor(new DataAccessCredentialScopeExtractor());

        // register JSON-LD transformer for credential processing
        typeTransformerRegistry.register(new JsonValueToGenericTypeTransformer(typeManager, JSON_LD));
        monitor.info("DCP Patch Extension initialized successfully");
    }
}
