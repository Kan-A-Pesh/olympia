cat > apps/bad-app/src/mqtt-handler.ts <<'INNER'
import type { MqttClient } from "mqtt"

export function onMqttMessage(client: MqttClient, topic: string, payload: Uint8Array) {
  const parsed = decode(payload)
  switch (parsed.kind) {
    case "identity":
      client.publish(topic, payload, { qos: 1 })
      break
  }
}
INNER
