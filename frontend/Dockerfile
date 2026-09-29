# ---------- Etapa 1: compilación de Flutter Web ----------
# Flutter se instala en una versión fija desde el repositorio oficial para que el build sea reproducible
# (las imágenes públicas de Flutter traen además el SDK de Android, que aquí no hace falta).
FROM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.47.5
RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl unzip xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home builder
USER builder
WORKDIR /home/builder

RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git flutter
ENV PATH="/home/builder/flutter/bin:${PATH}"
RUN flutter config --no-analytics --no-cli-animations \
    && flutter precache --web

WORKDIR /home/builder/app
COPY --chown=builder pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY --chown=builder . .

# URL pública de la API tal como la ve el navegador. Se inyecta en el build (--dart-define):
# no es un secreto, y ningún secreto debe pasarse por aquí porque quedaría dentro del bundle.
ARG API_URL
RUN test -n "${API_URL}" || (echo "Falta el build-arg API_URL" && exit 1)
# --no-web-resources-cdn: CanvasKit se sirve desde nginx, sin depender de un CDN externo.
RUN flutter build web --release --no-web-resources-cdn --dart-define=API_URL=${API_URL}

# ---------- Etapa 2: archivos estáticos con nginx (usuario no root, puerto 8080) ----------
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /home/builder/app/build/web /usr/share/nginx/html
EXPOSE 8080
