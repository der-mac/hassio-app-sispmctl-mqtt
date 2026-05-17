# Gembird SisPM MQTT Bridge — Home Assistant Add-on

Verbindet eine Gembird SisPMCTL USB-Steckdosenleiste (EG-PMS2, 4 Outlets)
mit Home Assistant ueber MQTT. Die Steckdosen erscheinen automatisch via
MQTT Discovery als schaltbare switch-Entitaeten.

## Installation

1. Einstellungen > Add-ons > Add-on-Store > Menue > Repository hinzufuegen
2. URL dieses GitHub-Repositories eintragen
3. Add-on installieren, Konfiguration anpassen, Starten

## Konfiguration

| Option        | Standard       | Beschreibung                        |
|---------------|----------------|-------------------------------------|
| device_id     | 01:01:51:c7:30 | Hardware-ID (sispmctl -s)           |
| device_name   | Gembird SisPM  | Anzeigename in Home Assistant       |
| mqtt_host     | core-mosquitto | Broker-Hostname                     |
| mqtt_port     | 1883           | Broker-Port                         |
| mqtt_user     | (leer)         | MQTT-Benutzername (optional)        |
| mqtt_pass     | (leer)         | MQTT-Passwort (optional)            |
| poll_interval | 5              | Abfrageintervall in Sekunden (1-60) |
