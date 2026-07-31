mkdir -p apps/daemon-app/src
cat > apps/daemon-app/src/main.ts <<'INNER'
export function boot(): void {
  process.on("SIGTERM", () => shutdown())
  setInterval(() => poll(), 1000)
  const timer = setTimeout(() => tick(), 500)
  void timer
}
INNER
