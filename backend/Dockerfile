# ---------- Etapa 1: compilación con el SDK ----------
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Primero solo el .csproj: la restauración de paquetes queda en caché mientras no cambien las dependencias.
COPY global.json ./
COPY src/Pedidos.Api/Pedidos.Api.csproj src/Pedidos.Api/
RUN dotnet restore src/Pedidos.Api/Pedidos.Api.csproj

COPY src/Pedidos.Api/ src/Pedidos.Api/
RUN dotnet publish src/Pedidos.Api/Pedidos.Api.csproj -c Release -o /app/publish --no-restore /p:UseAppHost=false

# ---------- Etapa 2: ejecución con la imagen aspnet (sin SDK ni código fuente) ----------
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

# Usuario no root que ya trae la imagen oficial (UID 1654).
USER $APP_UID

ENTRYPOINT ["dotnet", "Pedidos.Api.dll"]
