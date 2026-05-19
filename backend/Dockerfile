# ── Stage 1: install dependencies ────────────────────────────────────────────
FROM node:22-alpine AS deps

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts \
    && npm cache clean --force

# ── Stage 2: runtime image ────────────────────────────────────────────────────
FROM node:22-alpine AS runner

# Tạo group + user riêng, không chạy root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy deps từ stage 1 (không có npm cache)
COPY --from=deps --chown=appuser:appgroup /app/node_modules ./node_modules

# Copy source
COPY --chown=appuser:appgroup src ./src

USER appuser

ENV NODE_ENV=production
EXPOSE 3000

# Dùng exec form để nhận SIGTERM đúng cách (graceful shutdown)
CMD ["node", "src/index.js"]
