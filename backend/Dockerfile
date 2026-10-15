# ═══════════════════════════════════════════════════════════════════
# Stage 1: Build dependencies
# ═══════════════════════════════════════════════════════════════════
FROM node:26-slim AS builder

WORKDIR /app

# Copy package files and install dependencies
COPY package.json package-lock.json ./
RUN npm ci --only=production && npm cache clean --force

# Copy application source
COPY . .

# Remove unnecessary files
RUN rm -rf .env .git tests

# ═══════════════════════════════════════════════════════════════════
# Stage 2: Production image (DISTROLESS — no shell, no package manager)
# ═══════════════════════════════════════════════════════════════════
FROM gcr.io/distroless/nodejs22-debian12

WORKDIR /app

# Copy only production artifacts from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/server.js ./
COPY --from=builder /app/seed.js ./
COPY --from=builder /app/config ./config
COPY --from=builder /app/controllers ./controllers
COPY --from=builder /app/middleware ./middleware
COPY --from=builder /app/models ./models
COPY --from=builder /app/routes ./routes
COPY --from=builder /app/uploads ./uploads

# Expose application port
EXPOSE 4000

# Distroless runs as non-root (uid 65534) by default
USER 65534

CMD ["server.js"]
