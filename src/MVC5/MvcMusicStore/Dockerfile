# escape=`

# Build stage
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8 AS build
WORKDIR /src

# Copy everything and restore
COPY . ./MvcMusicStore/
WORKDIR /src/MvcMusicStore
RUN nuget restore packages.config -PackagesDirectory C:\src\packages

# Build the project (first compile, then publish)
RUN msbuild MvcMusicStore.csproj /p:Configuration=Release /t:Build
RUN msbuild MvcMusicStore.csproj /p:Configuration=Release /p:DeployOnBuild=true /p:WebPublishMethod=FileSystem /p:publishUrl=C:\publish /t:WebPublish

# Runtime stage
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8 AS runtime
WORKDIR /inetpub/wwwroot

# Copy published application from build stage
COPY --from=build C:/publish/ .

# Expose port 80 for the application
EXPOSE 80

# The base image already configures IIS to serve the application
# No additional CMD or ENTRYPOINT needed as the aspnet base image handles this
