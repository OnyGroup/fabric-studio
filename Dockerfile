FROM node:24-slim AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate

# Install native build deps for better-sqlite3
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pnpm-workspace.yaml pnpm-lock.yaml package.json ./
COPY apps/daemon/package.json ./apps/daemon/
COPY apps/web/package.json ./apps/web/
COPY packages/ ./packages/
COPY tools/ ./tools/
COPY scripts/ ./scripts/

# Install deps — skip Electron (not needed on server)
RUN ELECTRON_SKIP_BINARY_DOWNLOAD=1 pnpm install --frozen-lockfile

# Copy source
COPY . .

# Build daemon
RUN pnpm --filter @open-design/daemon build

# Build web in server output mode (SSR, not static export)
RUN OD_WEB_OUTPUT_MODE=server pnpm --filter @open-design/web build

# ---- runtime ----
FROM node:24-slim AS runtime
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=base /app ./

# Install design agent CLIs.
# claude  — primary agent; authenticated via ANTHROPIC_API_KEY at runtime.
# codex   — secondary agent; authenticated via OPENAI_API_KEY at runtime.
# Both CLIs are invoked as subprocesses by the daemon; ANTHROPIC_API_KEY /
# OPENAI_API_KEY are forwarded automatically from the container environment.
RUN npm install -g @anthropic-ai/claude-code @openai/codex \
    && claude --version \
    && codex --version

ENV NODE_ENV=production
ENV OD_WEB_OUTPUT_MODE=server
# Daemon binds on this port internally; Next.js proxies to it in dev,
# and in server mode the sidecar is imported directly — keep for reference.
ENV OD_PORT=7456

EXPOSE 3000

# Start script runs the daemon in background then Next.js in foreground
COPY start.sh ./start.sh
RUN chmod +x ./start.sh
CMD ["./start.sh"]
