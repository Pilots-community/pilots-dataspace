FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
RUN apk add --no-cache curl

ENV CP_HOST=controlplane
ENV CP_MGMT_PORT=19193
ENV CP_HEALTH_PORT=18181
ENV DP_HOST=dataplane
ENV DP_HEALTH_PORT=38181
ENV DP_PUBLIC_PORT=38185
ENV IH_HOST=identityhub
ENV IH_HEALTH_PORT=7090

EXPOSE 80
CMD ["sh", "-c", "envsubst '${CP_HOST} ${CP_MGMT_PORT} ${CP_HEALTH_PORT} ${DP_HOST} ${DP_HEALTH_PORT} ${DP_PUBLIC_PORT} ${IH_HOST} ${IH_HEALTH_PORT}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf && exec nginx -g 'daemon off;'"]
