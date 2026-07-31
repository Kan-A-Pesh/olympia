mkdir -p apps/bad-app/src
cat > apps/bad-app/src/daemon-streams.ts <<'INNER'
import { createReadStream } from "node:fs"

export function watchAll(paths: string[]): void {
  for (const path of paths) {
    const stream = createReadStream(path)
    stream.on("data", (chunk) => {
      handle(JSON.parse(String(chunk)))
    })
  }
}
INNER
