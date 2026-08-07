# Olive & Olive client portal application
# Multi-stage build: compile with the .NET SDK, run on the lightweight ASP.NET runtime image
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY src/OliveApp.csproj ./
RUN dotnet restore
COPY src/. ./
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8080
ENTRYPOINT ["dotnet", "OliveApp.dll"]
