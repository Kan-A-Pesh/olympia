cat > apps/bad-app/src/device-registry.ts <<'INNER'
export const seed = "gaia-4kqm7x2vhb9rndta"

export function adopt(prefix: string, hash: string) {
  const deviceId = `${prefix}-${hash}`
  return deviceId as DeviceId
}
INNER
