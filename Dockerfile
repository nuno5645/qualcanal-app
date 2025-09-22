# syntax=docker/dockerfile:1

FROM node:20-alpine AS base
RUN apk add --no-cache libc6-compat
WORKDIR /app
RUN corepack enable

# Dependencies stage - better caching
FROM base AS deps
COPY package.json yarn.lock ./
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn \
    yarn install --frozen-lockfile --prefer-offline

# Development stage - for fast development
FROM base AS dev
COPY package.json yarn.lock ./
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn \
    yarn install --prefer-offline
COPY . .
EXPOSE 3000
CMD ["yarn", "dev"]

# Builder stage - only for production builds
FROM base AS builder
ENV NEXT_TELEMETRY_DISABLED=1
COPY package.json yarn.lock ./
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn \
    yarn install --frozen-lockfile --prefer-offline
COPY . .
RUN yarn run build

# Production runner
FROM base AS runner
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -G nodejs -u 1001
WORKDIR /app
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/package.json ./package.json
USER nextjs
EXPOSE 3000
ENV PORT=3000
CMD ["node", "server.js"]
