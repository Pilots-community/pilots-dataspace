package org.eclipse.edc.extension;

import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.PATCH;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;
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
    public Response getRoot(@HeaderParam("Authorization") String auth,
                            @Context UriInfo uriInfo) {
        return proxy(auth, "GET", "", null, null, null, uriInfo);
    }

    @GET
    @Path("{subPath: .+}")
    public Response getSubPath(@HeaderParam("Authorization") String auth,
                               @PathParam("subPath") String subPath,
                               @Context UriInfo uriInfo) {
        return proxy(auth, "GET", subPath, null, null, null, uriInfo);
    }

    @POST
    public Response postRoot(@HeaderParam("Authorization") String auth,
                             @HeaderParam("Content-Type") String contentType,
                             byte[] body,
                             @Context UriInfo uriInfo) {
        return proxy(auth, "POST", "", body, contentType, null, uriInfo);
    }

    @POST
    @Path("{subPath: .+}")
    public Response postSubPath(@HeaderParam("Authorization") String auth,
                                @PathParam("subPath") String subPath,
                                @HeaderParam("Content-Type") String contentType,
                                byte[] body,
                                @Context UriInfo uriInfo) {
        return proxy(auth, "POST", subPath, body, contentType, null, uriInfo);
    }

    @PUT
    public Response putRoot(@HeaderParam("Authorization") String auth,
                            @HeaderParam("Content-Type") String contentType,
                            byte[] body,
                            @Context UriInfo uriInfo) {
        return proxy(auth, "PUT", "", body, contentType, null, uriInfo);
    }

    @PUT
    @Path("{subPath: .+}")
    public Response putSubPath(@HeaderParam("Authorization") String auth,
                               @PathParam("subPath") String subPath,
                               @HeaderParam("Content-Type") String contentType,
                               byte[] body,
                               @Context UriInfo uriInfo) {
        return proxy(auth, "PUT", subPath, body, contentType, null, uriInfo);
    }

    @PATCH
    public Response patchRoot(@HeaderParam("Authorization") String auth,
                              @HeaderParam("Content-Type") String contentType,
                              @HeaderParam("If-Match") String ifMatch,
                              byte[] body,
                              @Context UriInfo uriInfo) {
        return proxy(auth, "PATCH", "", body, contentType, ifMatch, uriInfo);
    }

    @PATCH
    @Path("{subPath: .+}")
    public Response patchSubPath(@HeaderParam("Authorization") String auth,
                                 @PathParam("subPath") String subPath,
                                 @HeaderParam("Content-Type") String contentType,
                                 @HeaderParam("If-Match") String ifMatch,
                                 byte[] body,
                                 @Context UriInfo uriInfo) {
        return proxy(auth, "PATCH", subPath, body, contentType, ifMatch, uriInfo);
    }

    @DELETE
    @Path("{subPath: .+}")
    public Response deleteSubPath(@HeaderParam("Authorization") String auth,
                                  @PathParam("subPath") String subPath,
                                  @Context UriInfo uriInfo) {
        return proxy(auth, "DELETE", subPath, null, null, null, uriInfo);
    }

    private Response proxy(String authorization, String method, String subPath,
                           byte[] body, String contentType, String ifMatch,
                           UriInfo uriInfo) {
        if (authorization == null || !authorization.toLowerCase().startsWith("bearer ")) {
            return Response.status(Response.Status.UNAUTHORIZED)
                    .entity("{\"error\": \"Missing or invalid Authorization header\"}")
                    .build();
        }

        var token = authorization.substring(7);

        var requestData = Map.<String, Object>of("method", method);
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

        // Build target URL: baseUrl + sub-path from request + query string
        var targetUrl = baseUrl.endsWith("/") ? baseUrl.stripTrailing() : baseUrl;
        if (!subPath.isEmpty()) {
            targetUrl = targetUrl + "/" + subPath;
        }
        var rawQuery = uriInfo.getRequestUri().getRawQuery();
        if (rawQuery != null && !rawQuery.isEmpty()) {
            targetUrl = targetUrl + "?" + rawQuery;
        }

        monitor.info("Public API: proxying " + method + " " + targetUrl);

        try {
            var bodyPublisher = (body != null && body.length > 0)
                    ? HttpRequest.BodyPublishers.ofByteArray(body)
                    : HttpRequest.BodyPublishers.noBody();

            var builder = HttpRequest.newBuilder()
                    .uri(URI.create(targetUrl))
                    .method(method, bodyPublisher);

            if (contentType != null) {
                builder.header("Content-Type", contentType);
            }
            if (ifMatch != null) {
                builder.header("If-Match", ifMatch);
            }

            var response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofByteArray());
            var respContentType = response.headers().firstValue("Content-Type").orElse("application/octet-stream");

            return Response.status(response.statusCode())
                    .entity(response.body())
                    .header("Content-Type", respContentType)
                    .build();
        } catch (Exception e) {
            monitor.warning("Public API: failed to proxy " + method + " " + targetUrl + ": " + e.getMessage());
            return Response.status(Response.Status.BAD_GATEWAY)
                    .entity("{\"error\": \"Failed to proxy request: " + e.getMessage() + "\"}")
                    .build();
        }
    }
}
