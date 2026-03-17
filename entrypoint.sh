#!/usr/bin/env bash
set -euo pipefail

# ─── Parse args: extract --self-destroy-in-secs, pass the rest to TEI ─────────

SELF_DESTROY_SECS=""
TEI_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-destroy-in-secs)
            SELF_DESTROY_SECS="$2"
            shift 2
            ;;
        *)
            TEI_ARGS+=("$1")
            shift
            ;;
    esac
done

# ─── Start TEI ────────────────────────────────────────────────────────────────

text-embeddings-router "${TEI_ARGS[@]}" &
TEI_PID=$!

# ─── Watchdog (only if --self-destroy-in-secs was provided) ───────────────────

if [[ -n "$SELF_DESTROY_SECS" ]]; then
    (
        IDLE_TIMEOUT="$SELF_DESTROY_SECS"
        LAST_COUNT=-1

        # Resolve TEI port from args (default 80)
        TEI_PORT=80
        for i in "${!TEI_ARGS[@]}"; do
            if [[ "${TEI_ARGS[$i]}" == "--port" ]]; then
                TEI_PORT="${TEI_ARGS[$((i + 1))]}"
                break
            fi
        done

        MAX_MIN=$((IDLE_TIMEOUT / 60))

        echo "[watchdog] Enabled — idle timeout: ${IDLE_TIMEOUT}s (${MAX_MIN}m), TEI port: ${TEI_PORT}"
        echo "[watchdog] Waiting for TEI to be ready..."

        # Wait for TEI to be healthy before starting idle countdown
        while kill -0 "$TEI_PID" 2>/dev/null; do
            if curl -sf "http://localhost:${TEI_PORT}/health" >/dev/null 2>&1; then
                echo "[watchdog] TEI is ready — starting idle countdown"
                break
            fi
            sleep 10
        done

        IDLE_SINCE=$(date +%s)

        while kill -0 "$TEI_PID" 2>/dev/null; do
            sleep 60

            COUNT=$(curl -sf "http://localhost:${TEI_PORT}/metrics" 2>/dev/null \
                | grep -m1 "^te_request_count" \
                | awk '{print $NF}' \
                || echo "$LAST_COUNT")

            NOW=$(date +%s)

            if [[ "$COUNT" != "$LAST_COUNT" ]]; then
                LAST_COUNT="$COUNT"
                IDLE_SINCE="$NOW"
                echo "[watchdog] Activity detected (request_count=$COUNT), idle timer reset"
            else
                IDLE_SECS=$((NOW - IDLE_SINCE))
                IDLE_MIN=$((IDLE_SECS / 60))
                echo "[watchdog] Pod idle for ${IDLE_MIN}m (max ${MAX_MIN}m)"

                if [[ "$IDLE_SECS" -ge "$IDLE_TIMEOUT" ]]; then
                    echo "[watchdog] Idle limit reached — self-terminating pod $RUNPOD_POD_ID"

                    DELETED=false
                    for ATTEMPT in $(seq 1 5); do
                        RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
                            "https://rest.runpod.io/v1/pods/$RUNPOD_POD_ID" \
                            -H "Authorization: Bearer $SELF_DESTROY_API_KEY")
                        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
                        BODY=$(echo "$RESPONSE" | sed '$d')
                        echo "[watchdog] DELETE attempt ${ATTEMPT}/5 — HTTP ${HTTP_CODE}${BODY:+ — $BODY}"

                        if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
                            echo "[watchdog] Pod delete confirmed"
                            DELETED=true
                            break
                        fi

                        echo "[watchdog] Retrying in 30s..."
                        sleep 30
                    done

                    if [[ "$DELETED" != "true" ]]; then
                        echo "[watchdog] All delete attempts failed — killing TEI to force container exit"
                        kill "$TEI_PID" 2>/dev/null
                    fi

                    break
                fi
            fi
        done
    ) &
fi

# ─── Wait for TEI to exit ─────────────────────────────────────────────────────

wait "$TEI_PID"
