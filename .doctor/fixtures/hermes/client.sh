cat > apps/bad-app/src/hermes-client.ts <<'INNER'
import mqtt from "mqtt"

export const client = mqtt.connect("mqtts://broker.local:8883", {
  clientId: "gaia",
  protocolVersion: 4,
})

export function announce(payload: Uint8Array) {
  client.subscribe(ALL_IDENTITIES, { qos: 1 })
  client.publish(identityTopic(id), payload, { qos: 0, retain: true })
}
INNER
