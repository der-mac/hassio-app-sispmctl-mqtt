ARG BUILD_FROM
FROM $BUILD_FROM

RUN apt-get update \
    && apt-get install -y --no-install-recommends sispmctl mosquitto-clients \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs /
RUN chmod +x /app/run.sh /app/sispmctl_mqtt.sh
