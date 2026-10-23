#!/usr/bin/env bash
# Auto-update: pull de main y reinicio por PM2 si hay cambios. Ejecutar por cron cada 15 min.
set -euo pipefail
cd "$(dirname "$0")/.."
git fetch origin main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  git merge --ff-only origin/main
  pip install -q -r local/requirements.txt
  pm2 restart nexus
fi
