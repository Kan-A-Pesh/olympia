cat > apps/bad-app/src/hermes-messages.ts <<'INNER'
import type { MqttClient } from "mqtt"

export function listen(client: MqttClient) {
  client.on("message", (topic: string, payload: Uint8Array) => {
    apply(topic, decode(payload))
  })
}
INNER
cat > apps/bad-app/src/hermes-frame.ts <<'INNER'
export function readHeader(bytes: Uint8Array) {
  const view = new DataView(bytes.buffer)
  return { magic: view.getUint32(0, false), rate: view.getUint32(8, true) }
}
INNER
