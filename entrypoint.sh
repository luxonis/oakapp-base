#!/usr/bin/env bash
set -Eeuo pipefail

RUNSVDIR_PID=""
APP_PID=""
APP_RC=0
TERMINATING=0
MISSING_APP_COMMAND_RC=64

stop_helpers() {
  for svc in /etc/service/*; do
    [ -d "$svc" ] || continue
    sv exit "$svc" >/dev/null 2>&1 || true
  done
}

stop_runsvdir() {
  if [[ -n "${RUNSVDIR_PID:-}" ]] && kill -0 "$RUNSVDIR_PID" 2>/dev/null; then
    kill -TERM "$RUNSVDIR_PID" 2>/dev/null || true
    wait "$RUNSVDIR_PID" 2>/dev/null || true
  fi
}

graceful_shutdown() {
  # Prevent re-entry if multiple TERM/INT arrive
  if [[ "$TERMINATING" -eq 1 ]]; then
    return
  fi
  TERMINATING=1

  echo "[entrypoint] Received termination signal, shutting down gracefully..."

  echo "[entrypoint] Stopping helpers..."
  stop_runsvdir
  stop_helpers

  # Forward SIGTERM to the app
  echo "[entrypoint] Sending stop signal to the application (SIGTERM)..."
  if [[ -n "${APP_PID:-}" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    echo "[entrypoint] Forwarding SIGTERM to app PID $APP_PID"
    kill -TERM "$APP_PID" 2>/dev/null || true

    # Wait for app to exit
    wait "$APP_PID" || APP_RC=$?
  else
    APP_RC=143
  fi

  echo "[entrypoint] Graceful shutdown complete, exiting with code ${APP_RC}"
  exit "${APP_RC}"
}

trap graceful_shutdown TERM INT

# Start main app outside runit
if [[ "$#" -lt 1 ]]; then
  echo "[entrypoint] No application command was provided."
  echo "[entrypoint] Configure oakapp.toml with an entrypoint command, for example:"
  echo "[entrypoint] entrypoint = [\"/entrypoint.sh\", \"python3\", \"-u\", \"/app/backend/src/main.py\", \"arg1\", ..., \"argn\"]"
  exit "$MISSING_APP_COMMAND_RC"
fi

# Start helper services under runit
echo "[entrypoint] Starting helper scripts at /etc/service/"
/usr/bin/runsvdir -P /etc/service &
RUNSVDIR_PID=$!

echo "[entrypoint] Starting application command: $*"
bash -lc 'exec "$@"' bash "$@" &
APP_PID=$!

# Normal app exit path
wait "$APP_PID" || APP_RC=$?

stop_helpers
stop_runsvdir

exit "${APP_RC}"
