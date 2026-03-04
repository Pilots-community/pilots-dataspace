package org.eclipse.edc.demo.dcp.issuer;

import org.eclipse.edc.iam.verifiablecredentials.spi.validation.TrustedIssuerRegistry;
import org.eclipse.edc.runtime.metamodel.annotation.Extension;
import org.eclipse.edc.runtime.metamodel.annotation.Inject;
import org.eclipse.edc.runtime.metamodel.annotation.Provider;
import org.eclipse.edc.runtime.metamodel.annotation.Setting;
import org.eclipse.edc.spi.system.ServiceExtension;
import org.eclipse.edc.spi.system.ServiceExtensionContext;
import org.eclipse.edc.web.spi.WebService;

import java.nio.file.Path;

@Extension("Trusted Issuer API Extension")
public class TrustedIssuerApiExtension implements ServiceExtension {

    @Setting(value = "Path to persist trusted issuers as JSON", defaultValue = "/app/data/trusted-issuers.json")
    private static final String PERSISTENCE_PATH_SETTING = "edc.demo.trusted.issuer.persistence.path";

    private final DynamicTrustedIssuerRegistry registry = new DynamicTrustedIssuerRegistry();

    @Inject
    private WebService webService;

    @Override
    public void initialize(ServiceExtensionContext context) {
        var monitor = context.getMonitor().withPrefix("TrustedIssuerApi");

        var persistencePath = context.getSetting(PERSISTENCE_PATH_SETTING, "/app/data/trusted-issuers.json");
        registry.configurePersistence(Path.of(persistencePath), monitor);
        registry.load();

        var mgmtPort = context.getSetting("web.http.management.port", "19193");
        var mgmtPath = context.getSetting("web.http.management.path", "/management");
        var apiKey = context.getSetting("edc.api.auth.key", "password");
        var managementBaseUrl = "http://localhost:" + mgmtPort + mgmtPath;

        webService.registerResource("management", new TrustedIssuerApiController(registry, monitor, managementBaseUrl, apiKey));
        monitor.info("Trusted Issuer API registered on management context at /v1/trusted-issuers");
    }

    @Provider
    public TrustedIssuerRegistry trustedIssuerRegistry() {
        return registry;
    }
}
