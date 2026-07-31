mkdir -p apps/bad-app/src
cat > apps/bad-app/src/usb-device.ts <<'INNER'
export function attach(reported: { sampleRate: number }) {
  return {
    transport: "usb",
    isAuthenticated: true,
    sampleRate: reported.sampleRate,
  }
}
INNER
