cat > apps/bad-app/src/mqtt-publish.ts <<'INNER'
import type { MqttClient } from "mqtt"

export function emit(client: MqttClient, frame: Uint8Array) {
  client.publish(identityTopic(id), frame)
  client.publish(dataTopic(id, "temp"), frame, { qos: 0, retain: true })
}
INNER
