cat > apps/bad-app/src/control-flow.ts <<'INNER'
export function label(kind: string): string {
  switch (kind) {
    case "scalar":
      const first = "one"
    case "series":
      return "many"
  }
}

export function pick(flag: boolean): number {
  if (flag) {
    return 1
  } else {
    return 2
  }
}
INNER
