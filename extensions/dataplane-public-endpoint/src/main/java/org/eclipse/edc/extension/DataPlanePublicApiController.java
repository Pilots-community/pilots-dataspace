package org.eclipse.edc.extension;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;
import org.eclipse.edc.connector.dataplane.spi.iam.DataPlaneAuthorizationService;
import org.eclipse.edc.spi.monitor.Monitor;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;

@Path("/")
public class DataPlanePublicApiController {

    private final DataPlaneAuthorizationService authorizationService;
    private final Monitor monitor;
    private final HttpClient httpClient;

    public DataPlanePublicApiController(DataPlaneAuthorizationService authorizationService, Monitor monitor) {
        this.authorizationService = authorizationService;
        this.monitor = monitor;
        this.httpClient = HttpClient.newHttpClient();
    }

    @GET
    public Response getData(@HeaderParam("Authorization") String authorization) {
        if (authorization == null || !authorization.toLowerCase().startsWith("bearer ")) {
            return Response.status(Response.Status.UNAUTHORIZED)
                    .entity("{\"error\": \"Missing or invalid Authorization header\"}")
                    .build();
        }

        var token = authorization.substring(7);

        // Authorize the token and get the source DataAddress
        var requestData = Map.<String, Object>of("method", "GET");
        var result = authorizationService.authorize(token, requestData);

        if (result.failed()) {
            monitor.warning("Public API: authorization failed: " + result.getFailureDetail());
            return Response.status(Response.Status.FORBIDDEN)
                    .entity("{\"error\": \"" + result.getFailureDetail() + "\"}")
                    .build();
        }

        var dataAddress = result.getContent();
        var baseUrl = dataAddress.getStringProperty("baseUrl");

        if (baseUrl == null || baseUrl.isBlank()) {
            monitor.warning("Public API: no baseUrl in DataAddress");
            return Response.status(Response.Status.BAD_GATEWAY)
                    .entity("{\"error\": \"No source URL configured for this data address\"}")
                    .build();
        }

        monitor.info("Public API: proxying request to " + baseUrl);

        // Fetch from the actual data source
        try {
            var request = HttpRequest.newBuilder()
                    .uri(URI.create(baseUrl))
                    .GET()
                    .build();

            var response = httpClient.send(request, HttpResponse.BodyHandlers.ofByteArray());
            var contentType = response.headers().firstValue("Content-Type").orElse("application/octet-stream");

            return Response.status(response.statusCode())
                    .entity(response.body())
                    .header("Content-Type", contentType)
                    .build();
        } catch (Exception e) {
            monitor.warning("Public API: failed to fetch from source: " + e.getMessage());
            return Response.status(Response.Status.BAD_GATEWAY)
                    .entity("{\"error\": \"Failed to fetch from data source: " + e.getMessage() + "\"}")
                    .build();
        }
    }
}
