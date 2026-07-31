mkdir -p apps/bad-app/src
cat > apps/bad-app/src/serial-open.ts <<'INNER'
import { SerialPort } from "serialport"

export function openLink(path: string, rate: number): SerialPort {
  const port = new SerialPort({ path, baudRate: rate })
  port.on("close", () => report(path))
  return port
}
INNER
