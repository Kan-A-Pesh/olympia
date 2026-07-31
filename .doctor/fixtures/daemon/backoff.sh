mkdir -p apps/bad-app/src
cat > apps/bad-app/src/daemon-backoff.ts <<'INNER'
export async function reconnectForever(client: { connect(): Promise<void> }): Promise<void> {
  while (true) {
    await client.connect()
  }
}
INNER
