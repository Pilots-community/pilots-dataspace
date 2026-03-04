package org.eclipse.edc.demo.dcp.issuer;

import jakarta.json.Json;
import jakarta.json.JsonObject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.edc.spi.monitor.Monitor;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

import static jakarta.json.JsonValue.NULL;
import static org.eclipse.edc.iam.verifiablecredentials.spi.validation.TrustedIssuerRegistry.WILDCARD;

@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
@Path("/v1/trusted-issuers")
public class TrustedIssuerApiController {

    private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(3);
    private static final Duration CATALOG_TIMEOUT = Duration.ofSeconds(8);

    private final DynamicTrustedIssuerRegistry registry;
    private final Monitor monitor;
    private final HttpClient httpClient;
    private final String managementBaseUrl;
    private final String apiKey;

    public TrustedIssuerApiController(DynamicTrustedIssuerRegistry registry, Monitor monitor,
                                      String managementBaseUrl, String apiKey) {
        this.registry = registry;
        this.monitor = monitor;
        this.managementBaseUrl = managementBaseUrl;
        this.apiKey = apiKey;
        this.httpClient = HttpClient.newBuilder().connectTimeout(CONNECT_TIMEOUT).build();
    }

    @GET
    public Response listIssuers() {
        var issuers = registry.getAll();
        var array = Json.createArrayBuilder();
        for (Map.Entry<String, TrustedIssuerRecord> entry : issuers.entrySet()) {
            var record = entry.getValue();
            var typesArray = Json.createArrayBuilder();
            record.getCredentialTypes().forEach(typesArray::add);
            var obj = Json.createObjectBuilder()
                    .add("did", entry.getKey())
                    .add("credentialTypes", typesArray);
            obj.add("name", record.getName() != null ? record.getName() : "");
            obj.add("organization", record.getOrganization() != null ? record.getOrganization() : "");
            obj.add("email", record.getEmail() != null ? record.getEmail() : "");
            obj.add("dspEndpoint", record.getDspEndpoint() != null ? record.getDspEndpoint() : "");
            obj.add("participantDid", record.getParticipantDid() != null ? record.getParticipantDid() : "");
            array.add(obj);
        }
        return Response.ok(array.build().toString()).build();
    }

    @POST
    public Response addIssuer(JsonObject body) {
        var did = body.getString("did", null);
        if (did == null || did.isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity("{\"error\": \"'did' field is required\"}")
                    .build();
        }
        var name = body.containsKey("name") && body.get("name") != NULL ? body.getString("name", null) : null;
        var organization = body.containsKey("organization") && body.get("organization") != NULL ? body.getString("organization", null) : null;
        var email = body.containsKey("email") && body.get("email") != NULL ? body.getString("email", null) : null;
        var dspEndpoint = body.containsKey("dspEndpoint") && body.get("dspEndpoint") != NULL ? body.getString("dspEndpoint", null) : null;
        var participantDid = body.containsKey("participantDid") && body.get("participantDid") != NULL ? body.getString("participantDid", null) : null;

        registry.registerWithMetadata(did, name, organization, email, dspEndpoint, participantDid);
        var issuer = new org.eclipse.edc.iam.verifiablecredentials.spi.model.Issuer(did, java.util.Map.of());
        registry.register(issuer, WILDCARD);
        monitor.info("Registered trusted issuer via API: %s".formatted(did));
        return Response.ok("{\"did\": \"%s\"}".formatted(did)).build();
    }

    @PUT
    public Response updateIssuer(JsonObject body) {
        var did = body.getString("did", null);
        if (did == null || did.isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity("{\"error\": \"'did' field is required\"}")
                    .build();
        }
        var existing = registry.getAll().get(did);
        if (existing == null) {
            return Response.status(Response.Status.NOT_FOUND)
                    .entity("{\"error\": \"Issuer not found: %s\"}".formatted(did))
                    .build();
        }
        var name = body.containsKey("name") && body.get("name") != NULL ? body.getString("name", null) : null;
        var organization = body.containsKey("organization") && body.get("organization") != NULL ? body.getString("organization", null) : null;
        var email = body.containsKey("email") && body.get("email") != NULL ? body.getString("email", null) : null;
        var dspEndpoint = body.containsKey("dspEndpoint") && body.get("dspEndpoint") != NULL ? body.getString("dspEndpoint", null) : null;
        var participantDid = body.containsKey("participantDid") && body.get("participantDid") != NULL ? body.getString("participantDid", null) : null;

        registry.registerWithMetadata(did, name, organization, email, dspEndpoint, participantDid);
        monitor.info("Updated trusted issuer metadata via API: %s".formatted(did));
        return Response.ok("{\"did\": \"%s\"}".formatted(did)).build();
    }

    @GET
    @Path("/health")
    public Response checkHealth() {
        var issuers = registry.getAll();
        var futures = new ArrayList<CompletableFuture<Map.Entry<String, String>>>();

        for (var entry : issuers.entrySet()) {
            var record = entry.getValue();
            if (record.getDspEndpoint() == null || record.getDspEndpoint().isBlank() ||
                    record.getParticipantDid() == null || record.getParticipantDid().isBlank()) {
                continue;
            }
            var key = entry.getKey();
            futures.add(CompletableFuture.supplyAsync(() ->
                    Map.entry(key, checkTrustStatus(record))
            ));
        }

        var result = Json.createObjectBuilder();
        for (var future : futures) {
            try {
                var entry = future.join();
                result.add(entry.getKey(), entry.getValue());
            } catch (Exception e) {
                monitor.debug("Health check future failed: %s".formatted(e.getMessage()));
            }
        }
        return Response.ok(result.build().toString()).build();
    }

    private String checkTrustStatus(TrustedIssuerRecord record) {
        // Attempt a real catalog request via the local management API
        try {
            var context = Json.createObjectBuilder()
                    .add("@vocab", "https://w3id.org/edc/v0.0.1/ns/")
                    .build();
            var catalogBody = Json.createObjectBuilder()
                    .add("@context", context)
                    .add("@type", "CatalogRequest")
                    .add("counterPartyAddress", record.getDspEndpoint())
                    .add("counterPartyId", record.getParticipantDid())
                    .add("protocol", "dataspace-protocol-http")
                    .build().toString();
            var request = HttpRequest.newBuilder()
                    .uri(URI.create(managementBaseUrl + "/v3/catalog/request"))
                    .timeout(CATALOG_TIMEOUT)
                    .header("Content-Type", "application/json")
                    .header("x-api-key", apiKey)
                    .POST(HttpRequest.BodyPublishers.ofString(catalogBody))
                    .build();
            var response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            if (response.statusCode() == 200) {
                return "mutual_trust";
            }
        } catch (Exception e) {
            monitor.debug("Catalog probe failed for %s: %s".formatted(record.getDspEndpoint(), e.getMessage()));
        }

        // Catalog failed — check if the DSP endpoint is at least reachable
        if (isDspReachable(record.getDspEndpoint())) {
            return "untrusted";
        }
        return "unreachable";
    }

    private boolean isDspReachable(String url) {
        try {
            var request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(CONNECT_TIMEOUT)
                    .GET()
                    .build();
            var response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            return response.statusCode() >= 200 && response.statusCode() < 500;
        } catch (Exception e) {
            return false;
        }
    }

    @DELETE
    public Response removeIssuer(JsonObject body) {
        var did = body.getString("did", null);
        if (did == null || did.isBlank()) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity("{\"error\": \"'did' field is required\"}")
                    .build();
        }
        var removed = registry.unregister(did);
        if (!removed) {
            return Response.status(Response.Status.NOT_FOUND)
                    .entity("{\"error\": \"Issuer not found: %s\"}".formatted(did))
                    .build();
        }
        monitor.info("Removed trusted issuer via API: %s".formatted(did));
        return Response.noContent().build();
    }
}
