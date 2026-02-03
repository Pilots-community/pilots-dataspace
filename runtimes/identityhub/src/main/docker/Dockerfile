FROM eclipse-temurin:24_36-jre-alpine

ARG JVM_ARGS=""
ARG JAR

RUN apk --no-cache add curl

WORKDIR /app

COPY ${JAR} identityhub.jar

EXPOSE 7080

HEALTHCHECK --interval=5s --timeout=5s --retries=10 CMD curl --fail http://localhost:7080/api/check/health

ENV ENV_JVM_ARGS=$JVM_ARGS
CMD ["sh", "-c", "exec java -Djava.security.egd=file:/dev/urandom -jar identityhub.jar"]
