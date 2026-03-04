package org.eclipse.edc.demo.dcp.issuer;

import org.eclipse.edc.iam.verifiablecredentials.spi.validation.TrustedIssuerRegistry;
import org.eclipse.edc.runtime.metamodel.annotation.Extension;
import org.eclipse.edc.runtime.metamodel.annotation.Inject;
import org.eclipse.edc.runtime.metamodel.annotation.Provider;
import org.eclipse.edc.spi.system.ServiceExtension;
import org.eclipse.edc.spi.system.ServiceExtensionContext;
import org.eclipse.edc.web.spi.WebService;

@Extension("Trusted Issuer API Extension")
public class TrustedIssuerApiExtension implements ServiceExtension {

    private final DynamicTrustedIssuerRegistry registry = new DynamicTrustedIssuerRegistry();

    @Inject
    private WebService webService;

    @Override
    public void initialize(ServiceExtensionContext context) {
        var monitor = context.getMonitor().withPrefix("TrustedIssuerApi");
        webService.registerResource("management", new TrustedIssuerApiController(registry, monitor));
        monitor.info("Trusted Issuer API registered on management context at /v1/trusted-issuers");
    }

    @Provider
    public TrustedIssuerRegistry trustedIssuerRegistry() {
        return registry;
    }
}
