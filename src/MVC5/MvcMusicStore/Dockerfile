# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0-preview AS build
WORKDIR /src

# Copy csproj and restore dependencies
COPY ["MvcMusicStore/MvcMusicStore.csproj", "MvcMusicStore/"]
RUN dotnet restore "MvcMusicStore/MvcMusicStore.csproj"

# Copy everything else and build
COPY . .
WORKDIR "/src/MvcMusicStore"
RUN dotnet build "MvcMusicStore.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "MvcMusicStore.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0-preview AS final
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

# Copy published application
COPY --from=publish /app/publish .

# Set environment variables
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production

# Create a non-root user
RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

ENTRYPOINT ["dotnet", "MvcMusicStore.dll"]
