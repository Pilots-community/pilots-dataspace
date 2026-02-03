package org.eclipse.edc.extension;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.edc.connector.dataplane.spi.store.AccessTokenDataStore;
import org.eclipse.edc.spi.monitor.Monitor;

@Path("/")
public class DataPlanePublicApiController {

    private final AccessTokenDataStore accessTokenDataStore;
    private final Monitor monitor;

    public DataPlanePublicApiController(AccessTokenDataStore accessTokenDataStore, Monitor monitor) {
        this.accessTokenDataStore = accessTokenDataStore;
        this.monitor = monitor;
    }

    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public Response getData(@HeaderParam("Authorization") String authorization) {
        if (authorization == null || !authorization.toLowerCase().startsWith("bearer ")) {
            return Response.status(Response.Status.UNAUTHORIZED)
                    .entity("{\"error\": \"Missing or invalid Authorization header\"}")
                    .build();
        }

        var token = authorization.substring(7);
        var jti = extractJti(token);

        var tokenData = accessTokenDataStore.getById(jti);
        if (tokenData == null) {
            monitor.warning("No access token data found for JTI: " + jti);
            return Response.status(Response.Status.FORBIDDEN)
                    .entity("{\"error\": \"Invalid or expired token\"}")
                    .build();
        }

        monitor.info("Public API: valid token for JTI " + jti);
        return Response.ok("{\"message\": \"Data transfer successful via EDC data plane\", \"jti\": \"" + jti + "\"}").build();
    }

    private String extractJti(String token) {
        try {
            var parts = token.split("\\.");
            if (parts.length >= 2) {
                var payload = new String(java.util.Base64.getUrlDecoder().decode(parts[1]));
                var idx = payload.indexOf("\"jti\"");
                if (idx >= 0) {
                    var start = payload.indexOf("\"", idx + 5) + 1;
                    var end = payload.indexOf("\"", start);
                    return payload.substring(start, end);
                }
            }
        } catch (Exception e) {
            monitor.warning("Failed to extract JTI from token: " + e.getMessage());
        }
        return "";
    }
}
