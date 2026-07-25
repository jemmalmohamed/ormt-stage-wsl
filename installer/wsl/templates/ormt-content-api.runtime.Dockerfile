FROM eclipse-temurin:25-jre
WORKDIR /app
COPY ormt-content-api/target/ormt-content-api-*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
