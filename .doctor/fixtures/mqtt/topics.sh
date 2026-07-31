cat > apps/bad-app/src/mqtt-topics.ts <<'INNER'
import type { MqttClient } from "mqtt"

const BAD_ROOT = "olympia"

export const deepTopic = `${BAD_ROOT}/v1/devices/gaia/data/temp/raw/extra`

export function follow(client: MqttClient, query: { deviceId: string }) {
  client.subscribe(`olympia/v1/devices/${query.deviceId}/data/+`)
}
INNER
