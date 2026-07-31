cat > packages/bad-pkg/src/functions.ts <<'INNER'
export function plot(width: number, height: number, gain: number, offset: number, scale: number): number {
  return width + height + gain + offset + scale
}

export function render(target: string, isDense: boolean): string {
  return target
}

export async function reload(target: string): Promise<string> {
  return target
}
INNER
