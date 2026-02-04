package org.eclipse.edc.iam.identitytrust.core;

import org.eclipse.edc.runtime.metamodel.annotation.Inject;
import org.eclipse.edc.spi.security.Vault;
import org.eclipse.edc.spi.system.ServiceExtension;
import org.eclipse.edc.spi.system.ServiceExtensionContext;

/**
 * Seeds a hardcoded EC key pair into the in-memory vault so that DCP modules
 * can sign and verify tokens without requiring an external vault.
 * <p>
 * This is a development/demo convenience only.
 */
public class SecretsExtension implements ServiceExtension {
    private static final String STS_PRIVATE_KEY_ALIAS = "edc.iam.sts.privatekey.alias";
    private static final String STS_PUBLIC_KEY_ID = "edc.iam.sts.publickey.id";

    @Inject
    private Vault vault;

    @Override
    public void initialize(ServiceExtensionContext context) {
        seedKeys(context);
    }

    private void seedKeys(ServiceExtensionContext context) {
        if (vault.getClass().getSimpleName().equals("InMemoryVault")) {
            var publicKey = """
                    -----BEGIN PUBLIC KEY-----
                    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEut/JSiIADcUNUvrrC3neZpjS8icF
                    wm87ZqhG/DUoJq8tqfF4R/GUGnSU5F3XZt7opxyrEsglegN82zah5CEncQ==
                    -----END PUBLIC KEY-----
                    """;

            var privateKey = """
                    -----BEGIN EC PRIVATE KEY-----
                    MHcCAQEEIJXj4zPaXQNZGaoR35WbBKfsnXnJekyAWwPRocSuxjeloAoGCCqGSM49
                    AwEHoUQDQgAEut/JSiIADcUNUvrrC3neZpjS8icFwm87ZqhG/DUoJq8tqfF4R/GU
                    GnSU5F3XZt7opxyrEsglegN82zah5CEncQ==
                    -----END EC PRIVATE KEY-----
                    """;

            vault.storeSecret(context.getConfig().getString(STS_PRIVATE_KEY_ALIAS), privateKey);
            vault.storeSecret(context.getConfig().getString(STS_PUBLIC_KEY_ID), publicKey);

            context.getMonitor().withPrefix("DEMO").warning(">>>>>> This extension hard-codes a keypair into the vault! <<<<<<");
        }
    }
}
