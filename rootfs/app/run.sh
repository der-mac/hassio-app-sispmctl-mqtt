#!/bin/sh
set -e
CONFIG_PATH=/data/options.json
export SISPMCTL_DEVICE=$(jq -r '.device_id'    "$CONFIG_PATH")
export DEVICE_NAME=$(jq -r '.device_name'       "$CONFIG_PATH")
export MQTT_HOST=$(jq -r '.mqtt_host'           "$CONFIG_PATH")
export MQTT_PORT=$(jq -r '.mqtt_port'           "$CONFIG_PATH")
export MQTT_USER=$(jq -r '.mqtt_user'           "$CONFIG_PATH")
export MQTT_PASS=$(jq -r '.mqtt_pass'           "$CONFIG_PATH")
export POLL_INTERVAL=$(jq -r '.poll_interval'   "$CONFIG_PATH")
exec /app/sispmctl_mqtt.sh
