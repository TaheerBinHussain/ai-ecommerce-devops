# syntax=docker/dockerfile:1
# Build context: repository root  ->  docker build -f docker/Dockerfile .

# ---------- Stage 1: test & build the storefront ----------
FROM node:22-alpine AS build
WORKDIR /app
COPY application/package.json application/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY application/ ./
ARG APP_VERSION=1.0.0
ARG GIT_COMMIT=local
ARG BUILD_NUMBER=0
ENV APP_VERSION=$APP_VERSION GIT_COMMIT=$GIT_COMMIT BUILD_NUMBER=$BUILD_NUMBER
RUN npm run lint && npm test && npm run build

# ---------- Stage 2: minimal, non-root runtime ----------
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
ARG APP_VERSION=1.0.0
ARG GIT_COMMIT=local
LABEL org.opencontainers.image.title="nexvion-store" \
      org.opencontainers.image.description="NEXVION e-commerce storefront" \
      org.opencontainers.image.version=$APP_VERSION \
      org.opencontainers.image.revision=$GIT_COMMIT

# Patch OS packages to reduce image-scan findings
USER root
RUN apk upgrade --no-cache
USER 101

COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build --chown=101:101 /app/dist/ /usr/share/nginx/html/

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1
