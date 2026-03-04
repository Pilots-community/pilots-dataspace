package org.eclipse.edc.demo.dcp.issuer;

import org.eclipse.edc.iam.verifiablecredentials.spi.model.Issuer;
import org.eclipse.edc.iam.verifiablecredentials.spi.validation.TrustedIssuerRegistry;

import java.util.Collections;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public class DynamicTrustedIssuerRegistry implements TrustedIssuerRegistry {

    private final ConcurrentHashMap<String, TrustedIssuerRecord> issuers = new ConcurrentHashMap<>();

    @Override
    public void register(Issuer issuer, String credentialType) {
        issuers.computeIfAbsent(issuer.id(), k -> new TrustedIssuerRecord(issuer.id(), null, null, null, null, null))
                .getCredentialTypes().add(credentialType);
    }

    @Override
    public Set<String> getSupportedTypes(Issuer issuer) {
        var record = issuers.get(issuer.id());
        return record != null ? record.getCredentialTypes() : Set.of();
    }

    public void registerWithMetadata(String did, String name, String organization, String email, String dspEndpoint, String participantDid) {
        issuers.compute(did, (k, existing) -> {
            if (existing != null) {
                // Preserve existing credential types, update metadata by replacing record
                var updated = new TrustedIssuerRecord(did, name, organization, email, dspEndpoint, participantDid);
                updated.getCredentialTypes().addAll(existing.getCredentialTypes());
                return updated;
            }
            return new TrustedIssuerRecord(did, name, organization, email, dspEndpoint, participantDid);
        });
    }

    public Map<String, TrustedIssuerRecord> getAll() {
        return Collections.unmodifiableMap(issuers);
    }

    public boolean unregister(String issuerId) {
        return issuers.remove(issuerId) != null;
    }
}
