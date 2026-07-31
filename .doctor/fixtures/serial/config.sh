mkdir -p apps/bad-app/src
cat > apps/bad-app/src/link-config.ts <<'INNER'
export function connect(port: { write(data: string): void }): void {
  const options = { path: "/dev/ttyACM0", baudRate: 115200 }
  port.write("i")
  const expected = "SRPICO,A031D21,02"
  use(options, expected)
}
INNER
