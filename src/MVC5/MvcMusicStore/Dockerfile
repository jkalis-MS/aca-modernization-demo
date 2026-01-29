# escape=`

# Build stage
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8 AS build
WORKDIR /app

# Copy project file and restore dependencies
COPY *.csproj ./
COPY packages.config ./
RUN nuget restore

# Copy everything else and build
COPY . ./
RUN msbuild MvcMusicStore.csproj /p:Configuration=Release /p:DeployOnBuild=true /p:WebPublishMethod=FileSystem /p:publishUrl=C:\app\out /t:WebPublish

# Runtime stage
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8 AS runtime
WORKDIR /inetpub/wwwroot

# Copy published application from build stage
COPY --from=build C:/app/out/_PublishedWebsites/MvcMusicStore .

# Expose port 80 for the application
EXPOSE 80

# The base image already configures IIS to serve the application
# No additional CMD or ENTRYPOINT needed as the aspnet base image handles this
