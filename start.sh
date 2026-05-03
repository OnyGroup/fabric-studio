#!/usr/bin/env bash
set -euo pipefail

# Start daemon in background (serves /api, /artifacts, /frames on OD_PORT)
node apps/daemon/dist/cli.js --no-open &
DAEMON_PID=$!

# Give daemon a moment to bind before Next.js starts accepting traffic
sleep 2

# Start Next.js server on $PORT (injected by DigitalOcean).
# pnpm workspace resolution finds the next binary inside apps/web.
pnpm --filter @open-design/web exec -- next start -p "${PORT:-3000}" &
WEB_PID=$!

# If either process exits, kill the other and exit non-zero
wait -n
kill $DAEMON_PID $WEB_PID 2>/dev/null || true
exit 1
