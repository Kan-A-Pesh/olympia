cat > apps/bad-app/src/mqtt-subscribe.ts <<'INNER'
import type { MqttClient } from "mqtt"

export function listen(client: MqttClient) {
  client.subscribe("#")
  client.subscribe("olympia/v1/devices/+/identity")
  client.subscribe(ALL_DATA)
  client.subscribe(ALL_DATA)
}
INNER
