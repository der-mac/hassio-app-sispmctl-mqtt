#!/bin/sh
# sispmctl MQTT Bridge – Home Assistant MQTT Discovery
#
# Env vars:
#   SISPMCTL_DEVICE   Hardware-ID der Steckdose   (default: 01:01:51:c7:30)
#   MQTT_HOST         Broker-Hostname              (default: localhost)
#   MQTT_PORT         Broker-Port                  (default: 1883)
#   MQTT_USER         MQTT-Benutzername            (optional)
#   MQTT_PASS         MQTT-Passwort                (optional)
#   POLL_INTERVAL     Abfrageintervall in Sekunden (default: 5)
#   DEVICE_NAME       Anzeigename in Home Assistant (default: Gembird SisPM)

DEVICE_ID="${SISPMCTL_DEVICE:-01:01:51:c7:30}"
MQTT_HOST="${MQTT_HOST:-localhost}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USER:-}"
MQTT_PASS="${MQTT_PASS:-}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
DEVICE_NAME="${DEVICE_NAME:-Gembird SisPM}"

# Geräte-ID für Topic-Namen (Doppelpunkte entfernen)
SAFE_ID=$(echo "$DEVICE_ID" | tr -d ':')
AVAIL_TOPIC="sispmctl/${SAFE_ID}/availability"

# Mosquitto-Basisargumente – bewusst unquoted für Word-Splitting
MQTT_ARGS="-h ${MQTT_HOST} -p ${MQTT_PORT}"
[ -n "$MQTT_USER" ] && MQTT_ARGS="${MQTT_ARGS} -u ${MQTT_USER} -P ${MQTT_PASS}"

# ── Hilfsfunktionen ────────────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*"; }

outlet_base() {
    echo "homeassistant/switch/sispmctl_${SAFE_ID}_outlet_${1}"
}

# mqtt_pub <topic> <payload> [retain]
mqtt_pub() {
    topic="$1" payload="$2" retain="${3:-}"
    # shellcheck disable=SC2086
    mosquitto_pub $MQTT_ARGS ${retain:+-r} -t "$topic" -m "$payload"
}

# ── HA MQTT Discovery ──────────────────────────────────────────────────────────

send_discovery() {
    n="$1"
    base="$(outlet_base "$n")"
    # JSON-Payload als statisches Template – kein jq nötig
    payload=$(printf \
        '{"name":"Outlet %s","unique_id":"sispmctl_%s_outlet_%s","state_topic":"%s/state","command_topic":"%s/set","availability_topic":"%s","payload_on":"ON","payload_off":"OFF","state_on":"ON","state_off":"OFF","retain":true,"device":{"identifiers":["sispmctl_%s"],"name":"%s","model":"EG-PMS2","manufacturer":"Gembird"}}' \
        "$n" "$SAFE_ID" "$n" \
        "$base" "$base" \
        "$AVAIL_TOPIC" \
        "$SAFE_ID" "$DEVICE_NAME")
    mqtt_pub "${base}/config" "$payload" retain
    log "discovery: outlet $n announced"
}

send_all_discovery() {
    for n in 1 2 3 4; do
        send_discovery "$n"
    done
    mqtt_pub "$AVAIL_TOPIC" "online" retain
    log "discovery: all 4 outlets announced, availability = online"
}

# ── Status-Polling ─────────────────────────────────────────────────────────────

poll_status() {
    output=$(sispmctl -D "$DEVICE_ID" -g all 2>/dev/null) || {
        log "poll: device read error – marking offline"
        mqtt_pub "$AVAIL_TOPIC" "offline" retain
        return 1
    }
    mqtt_pub "$AVAIL_TOPIC" "online" retain
    for n in 1 2 3 4; do
        state=$(printf '%s\n' "$output" \
            | awk "/outlet ${n}:/ { print toupper(\$NF) }")
        [ -n "$state" ] && mqtt_pub "$(outlet_base "$n")/state" "$state" retain
    done
}

# ── Command-Handler (läuft im Pipe-Subshell) ──────────────────────────────────

handle_command() {
    topic="$1"
    payload="$2"

    # HA-Neustart → Discovery neu senden
    if [ "$topic" = "homeassistant/status" ] && [ "$payload" = "online" ]; then
        log "ha: Home Assistant online – re-sending discovery"
        send_all_discovery
        return
    fi

    # Outlet-Nummer aus Topic extrahieren:
    # homeassistant/switch/sispmctl_<id>_outlet_N/set  →  N
    n="${topic##*_outlet_}"   # alles bis einschließlich "_outlet_" abschneiden → "2/set"
    n="${n%%/*}"               # alles ab "/" abschneiden → "2"

    case "$payload" in
        ON)
            sispmctl -D "$DEVICE_ID" "-o${n}" \
                && mqtt_pub "$(outlet_base "$n")/state" "ON"  retain \
                && log "cmd: outlet $n → ON"
            ;;
        OFF)
            sispmctl -D "$DEVICE_ID" "-f${n}" \
                && mqtt_pub "$(outlet_base "$n")/state" "OFF" retain \
                && log "cmd: outlet $n → OFF"
            ;;
        *)
            log "cmd: unknown payload '${payload}' on ${topic}"
            ;;
    esac
}

# ── Subscriber-Loop mit automatischem Reconnect ────────────────────────────────

subscribe_loop() {
    while true; do
        log "sub: connecting to ${MQTT_HOST}:${MQTT_PORT} ..."
        # shellcheck disable=SC2086
        mosquitto_sub $MQTT_ARGS -v \
            -t "homeassistant/switch/sispmctl_${SAFE_ID}_outlet_1/set" \
            -t "homeassistant/switch/sispmctl_${SAFE_ID}_outlet_2/set" \
            -t "homeassistant/switch/sispmctl_${SAFE_ID}_outlet_3/set" \
            -t "homeassistant/switch/sispmctl_${SAFE_ID}_outlet_4/set" \
            -t "homeassistant/status" \
        | while IFS= read -r line; do
            topic="${line%% *}"
            payload="${line#* }"
            handle_command "$topic" "$payload"
        done
        log "sub: connection lost – reconnecting in 5s ..."
        sleep 5
    done
}

# ── Warten bis Broker erreichbar ───────────────────────────────────────────────

wait_for_broker() {
    log "start: waiting for broker at ${MQTT_HOST}:${MQTT_PORT} ..."
    # shellcheck disable=SC2086
    until mosquitto_pub $MQTT_ARGS -t "sispmctl/ping" -m "" -q 0 2>/dev/null; do
        sleep 3
    done
    log "start: broker ready"
}

# ── Sauberes Herunterfahren ────────────────────────────────────────────────────

cleanup() {
    log "shutdown: marking device offline"
    mqtt_pub "$AVAIL_TOPIC" "offline" retain
    kill "$SUB_PID" 2>/dev/null
    exit 0
}
trap cleanup INT TERM

# ── Main ───────────────────────────────────────────────────────────────────────

log "start: sispmctl MQTT bridge"
log "start: device=${DEVICE_ID}  broker=${MQTT_HOST}:${MQTT_PORT}  interval=${POLL_INTERVAL}s"

wait_for_broker
send_all_discovery

subscribe_loop &
SUB_PID=$!

while true; do
    poll_status
    sleep "$POLL_INTERVAL"
done
