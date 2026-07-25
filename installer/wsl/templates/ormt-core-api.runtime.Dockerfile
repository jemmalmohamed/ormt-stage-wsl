FROM eclipse-temurin:25-jre-alpine
LABEL maintainer="jemmalmohamed@gmail.com"
WORKDIR /app
VOLUME /tmp
COPY target/ormt-core-api.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-Djava.security.egd=file:/dev/./urandom", "-jar", "/app/app.jar"]
