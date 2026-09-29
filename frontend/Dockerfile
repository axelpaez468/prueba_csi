# ---------- Etapa 1: compilación de Flutter Web ----------
# Flutter se instala en una versión fija desde el repositorio oficial para que el build sea reproducible
# (las imágenes públicas de Flutter traen además el SDK de Android, que aquí no hace falta).
FROM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.47.5
RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl unzip xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Reintenta un comando de red: el DNS de Docker Desktop falla de forma intermitente durante builds
# en paralelo ("Could not resolve host"), y sin esto un fallo momentáneo tumbaría todo el build.
RUN printf '#!/bin/sh\nfor i in 1 2 3 4 5; do "$@" && exit 0; echo "[reintento] fallo $i/5: $*" >&2; sleep $((i * 5)); done; exit 1\n' \
      > /usr/local/bin/reintentar && chmod +x /usr/local/bin/reintentar

RUN useradd --create-home builder
USER builder
WORKDIR /home/builder

RUN reintentar sh -c 'rm -rf flutter && git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git flutter'
ENV PATH="/home/builder/flutter/bin:${PATH}"
RUN flutter config --no-analytics --no-cli-animations \
    && reintentar flutter precache --web

WORKDIR /home/builder/app
COPY --chown=builder pubspec.yaml pubspec.lock ./
RUN reintentar flutter pub get

COPY --chown=builder . .

# URL pública de la API tal como la ve el navegador. Se inyecta en el build (--dart-define):
# no es un secreto, y ningún secreto debe pasarse por aquí porque quedaría dentro del bundle.
ARG API_URL
RUN test -n "${API_URL}" || (echo "Falta el build-arg API_URL" && exit 1)
# --no-web-resources-cdn: CanvasKit se sirve desde nginx, sin depender de un CDN externo.
RUN flutter build web --release --no-web-resources-cdn --dart-define=API_URL=${API_URL}

# ---------- Etapa 2: archivos estáticos con nginx (usuario no root, puerto 8080) ----------
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
ARG API_URL
COPY nginx.conf /etc/nginx/conf.d/default.conf
# La CSP debe permitir conexiones a la API: se inyecta su URL en tiempo de build (no en runtime,
# para que el contenedor pueda correr con el sistema de archivos en solo lectura).
USER root
RUN sed -i "s|__API_URL__|${API_URL}|g" /etc/nginx/conf.d/default.conf && nginx -t
USER nginx
COPY --from=build /home/builder/app/build/web /usr/share/nginx/html
EXPOSE 8080
