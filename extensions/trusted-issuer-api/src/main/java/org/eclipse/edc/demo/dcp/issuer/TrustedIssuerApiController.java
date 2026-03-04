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

import java.util.Map;

import static jakarta.json.JsonValue.NULL;
import static org.eclipse.edc.iam.verifiablecredentials.spi.validation.TrustedIssuerRegistry.WILDCARD;

@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
@Path("/v1/trusted-issuers")
public class TrustedIssuerApiController {

    private final DynamicTrustedIssuerRegistry registry;
    private final Monitor monitor;

    public TrustedIssuerApiController(DynamicTrustedIssuerRegistry registry, Monitor monitor) {
        this.registry = registry;
        this.monitor = monitor;
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
