FROM eclipse-temurin:17-jre-alpine

# Patch Alpine OS packages (e.g. openssl) between base-image rebuilds
RUN apk update && apk upgrade --no-cache

WORKDIR /app

COPY target/demo-app-*.jar app.jar

EXPOSE 8080

USER nobody

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
