package org.eclipse.edc.demo.dcp.issuer;

import jakarta.json.Json;
import jakarta.json.JsonObject;
import jakarta.json.JsonString;
import org.eclipse.edc.iam.verifiablecredentials.spi.model.Issuer;
import org.eclipse.edc.iam.verifiablecredentials.spi.validation.TrustedIssuerRegistry;
import org.eclipse.edc.spi.monitor.Monitor;

import java.io.IOException;
import java.io.StringReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collections;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public class DynamicTrustedIssuerRegistry implements TrustedIssuerRegistry {

    private final ConcurrentHashMap<String, TrustedIssuerRecord> issuers = new ConcurrentHashMap<>();
    private Path persistencePath;
    private Monitor monitor;

    @Override
    public void register(Issuer issuer, String credentialType) {
        issuers.computeIfAbsent(issuer.id(), k -> new TrustedIssuerRecord(issuer.id(), null, null, null, null, null))
                .getCredentialTypes().add(credentialType);
        save();
    }

    @Override
    public Set<String> getSupportedTypes(Issuer issuer) {
        var record = issuers.get(issuer.id());
        return record != null ? record.getCredentialTypes() : Set.of();
    }

    public void registerWithMetadata(String did, String name, String organization, String email, String dspEndpoint, String participantDid) {
        issuers.compute(did, (k, existing) -> {
            if (existing != null) {
                var updated = new TrustedIssuerRecord(did, name, organization, email, dspEndpoint, participantDid);
                updated.getCredentialTypes().addAll(existing.getCredentialTypes());
                return updated;
            }
            return new TrustedIssuerRecord(did, name, organization, email, dspEndpoint, participantDid);
        });
        save();
    }

    public Map<String, TrustedIssuerRecord> getAll() {
        return Collections.unmodifiableMap(issuers);
    }

    public boolean unregister(String issuerId) {
        var removed = issuers.remove(issuerId) != null;
        if (removed) {
            save();
        }
        return removed;
    }

    public void configurePersistence(Path path, Monitor mon) {
        this.persistencePath = path;
        this.monitor = mon;
    }

    public void load() {
        if (persistencePath == null || !Files.exists(persistencePath)) {
            return;
        }
        try {
            var content = Files.readString(persistencePath);
            var reader = Json.createReader(new StringReader(content));
            var array = reader.readArray();
            for (var item : array) {
                var obj = item.asJsonObject();
                var did = obj.getString("did");
                var name = getStringOrNull(obj, "name");
                var organization = getStringOrNull(obj, "organization");
                var email = getStringOrNull(obj, "email");
                var dspEndpoint = getStringOrNull(obj, "dspEndpoint");
                var participantDid = getStringOrNull(obj, "participantDid");
                var record = new TrustedIssuerRecord(did, name, organization, email, dspEndpoint, participantDid);
                if (obj.containsKey("credentialTypes")) {
                    for (var ct : obj.getJsonArray("credentialTypes")) {
                        record.getCredentialTypes().add(((JsonString) ct).getString());
                    }
                }
                issuers.put(did, record);
            }
            if (monitor != null) {
                monitor.info("Loaded %d trusted issuers from %s".formatted(array.size(), persistencePath));
            }
        } catch (IOException e) {
            if (monitor != null) {
                monitor.warning("Failed to load trusted issuers from %s: %s".formatted(persistencePath, e.getMessage()));
            }
        }
    }

    private void save() {
        if (persistencePath == null) {
            return;
        }
        try {
            var array = Json.createArrayBuilder();
            for (var entry : issuers.entrySet()) {
                var record = entry.getValue();
                var typesArray = Json.createArrayBuilder();
                record.getCredentialTypes().forEach(typesArray::add);
                array.add(Json.createObjectBuilder()
                        .add("did", record.getDid())
                        .add("name", record.getName() != null ? record.getName() : "")
                        .add("organization", record.getOrganization() != null ? record.getOrganization() : "")
                        .add("email", record.getEmail() != null ? record.getEmail() : "")
                        .add("dspEndpoint", record.getDspEndpoint() != null ? record.getDspEndpoint() : "")
                        .add("participantDid", record.getParticipantDid() != null ? record.getParticipantDid() : "")
                        .add("credentialTypes", typesArray));
            }
            Files.createDirectories(persistencePath.getParent());
            Files.writeString(persistencePath, array.build().toString());
        } catch (IOException e) {
            if (monitor != null) {
                monitor.warning("Failed to save trusted issuers to %s: %s".formatted(persistencePath, e.getMessage()));
            }
        }
    }

    private static String getStringOrNull(JsonObject obj, String key) {
        if (!obj.containsKey(key) || obj.isNull(key)) {
            return null;
        }
        var value = obj.getString(key, "");
        return value.isEmpty() ? null : value;
    }
}
