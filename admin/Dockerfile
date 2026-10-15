# ═══════════════════════════════════════════════════════════════════
# Stage 1: Build the React admin panel
# ═══════════════════════════════════════════════════════════════════
FROM node:26-slim AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --legacy-peer-deps && npm cache clean --force

COPY . .
RUN npm run build

# ═══════════════════════════════════════════════════════════════════
# Stage 2: Serve with DISTROLESS nginx (minimal, no shell)
# ═══════════════════════════════════════════════════════════════════
FROM nginxinc/nginx-unprivileged:1.27-alpine

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built assets from builder
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 8080

USER 101

CMD ["nginx", "-g", "daemon off;"]
