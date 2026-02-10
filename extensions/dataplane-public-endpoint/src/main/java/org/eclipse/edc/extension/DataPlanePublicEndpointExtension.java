package org.eclipse.edc.extension;

import org.eclipse.edc.connector.dataplane.spi.Endpoint;
import org.eclipse.edc.connector.dataplane.spi.iam.DataPlaneAuthorizationService;
import org.eclipse.edc.connector.dataplane.spi.iam.PublicEndpointGeneratorService;
import org.eclipse.edc.runtime.metamodel.annotation.Extension;
import org.eclipse.edc.runtime.metamodel.annotation.Inject;
import org.eclipse.edc.spi.security.Vault;
import org.eclipse.edc.spi.system.ServiceExtension;
import org.eclipse.edc.spi.system.ServiceExtensionContext;
import org.eclipse.edc.web.spi.WebService;
import org.eclipse.edc.web.spi.configuration.PortMapping;
import org.eclipse.edc.web.spi.configuration.PortMappingRegistry;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.eclipse.edc.extension.DataPlanePublicEndpointExtension.NAME;

@Extension(NAME)
public class DataPlanePublicEndpointExtension implements ServiceExtension {

    public static final String NAME = "Data Plane Public Endpoint Registration";
    private static final String PUBLIC_API_URL_KEY = "edc.dataplane.api.public.baseurl";
    private static final String PRIVATE_KEY_PATH_KEY = "edc.transfer.proxy.token.signer.privatekey.path";
    private static final String PUBLIC_KEY_PATH_KEY = "edc.transfer.proxy.token.verifier.publickey.path";

    private static final String PUBLIC_CONTEXT = "public";
    private static final int DEFAULT_PUBLIC_PORT = 38185;
    private static final String DEFAULT_PUBLIC_PATH = "/public";

    @Inject
    private PublicEndpointGeneratorService generatorService;

    @Inject
    private Vault vault;

    @Inject
    private PortMappingRegistry portMappingRegistry;

    @Inject
    private WebService webService;

    @Inject
    private DataPlaneAuthorizationService authorizationService;

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public void initialize(ServiceExtensionContext context) {
        // Register the "public" web context with Jetty
        var publicPort = context.getSetting("web.http.public.port", DEFAULT_PUBLIC_PORT);
        var publicPath = context.getSetting("web.http.public.path", DEFAULT_PUBLIC_PATH);
        portMappingRegistry.register(new PortMapping(PUBLIC_CONTEXT, publicPort, publicPath));

        // Register public endpoint generator for HttpData
        var publicApiUrl = context.getSetting(PUBLIC_API_URL_KEY, null);
        if (publicApiUrl != null) {
            generatorService.addGeneratorFunction("HttpData", dataAddress -> Endpoint.url(publicApiUrl));
            generatorService.addResponseGeneratorFunction("HttpData", () -> Endpoint.url(publicApiUrl + "/responseChannel"));
            context.getMonitor().info("Registered public endpoint generator for HttpData at: " + publicApiUrl);
        } else {
            context.getMonitor().warning("No '%s' configured — HttpData PULL transfers will not work".formatted(PUBLIC_API_URL_KEY));
        }

        // Register the public API controller on the "public" web context
        webService.registerResource(PUBLIC_CONTEXT, new DataPlanePublicApiController(authorizationService, context.getMonitor()));

        // Load token signing keys from PEM files into the vault
        loadKeyIntoVault(context, PRIVATE_KEY_PATH_KEY,
                context.getSetting("edc.transfer.proxy.token.signer.privatekey.alias", "private-key"));
        loadKeyIntoVault(context, PUBLIC_KEY_PATH_KEY,
                context.getSetting("edc.transfer.proxy.token.verifier.publickey.alias", "public-key"));
    }

    private void loadKeyIntoVault(ServiceExtensionContext context, String pathSettingKey, String alias) {
        var keyPath = context.getSetting(pathSettingKey, null);
        if (keyPath == null) {
            return;
        }
        try {
            var pem = Files.readString(Path.of(keyPath));
            vault.storeSecret(alias, pem);
            context.getMonitor().info("Loaded key '%s' from %s".formatted(alias, keyPath));
        } catch (IOException e) {
            context.getMonitor().warning("Failed to load key from %s: %s".formatted(keyPath, e.getMessage()));
        }
    }
}
