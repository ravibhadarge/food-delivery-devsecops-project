# ═══════════════════════════════════════════════════════════════════
# Stage 1: Build the React app
# ═══════════════════════════════════════════════════════════════════
FROM node:26-slim AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --legacy-peer-deps && npm cache clean --force

COPY . .
RUN npm run build

# ═══════════════════════════════════════════════════════════════════
# Stage 2: Serve with nginx (minimal, no shell)
# ═══════════════════════════════════════════════════════════════════
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 8080

USER 101

CMD ["nginx", "-g", "daemon off;"]
