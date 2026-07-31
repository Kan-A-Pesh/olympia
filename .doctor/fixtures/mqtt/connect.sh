cat > apps/bad-app/src/mqtt-connect.ts <<'INNER'
import mqtt from "mqtt"

export const client = mqtt.connect("mqtt://admin:hunter2@broker.local:1883", {
  clientId: `hub-${Math.random()}`,
  will: { topic: "status", payload: "", qos: 1 },
})
INNER
cat > apps/bad-app/src/mqtt-spare.ts <<'INNER'
import { connectAsync } from "mqtt"

export const spare = () =>
  connectAsync("mqtts://broker.local:8883", {
    clientId: "iris-hub",
    keepalive: 30,
    clean: false,
    sessionExpiryInterval: 300,
  })
INNER
