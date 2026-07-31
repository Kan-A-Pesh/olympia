mkdir -p apps/bad-app/src
cat > apps/bad-app/src/uart-frames.ts <<'INNER'
let held = Buffer.alloc(0)

export function feed(link: { on(event: string, handler: (chunk: Buffer) => void): void }): void {
  link.on("data", (chunk) => {
    held = Buffer.concat([held, chunk])
    const signature = "frame:" + chunk.toString()
    report(signature)
  })
}
INNER
