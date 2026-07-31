cat > packages/bad-pkg/src/inference.ts <<'INNER'
export type Reading = {
  probeId: string
  celsius: number
  takenAt: number
}

export type ReadingSummary = {
  probeId: string
  celsius: number
}

export type ReadingCopy = {
  probeId: string
  celsius: number
  takenAt: number
}

export const label: string = "probe"

export const preset = { probeId: "a", celsius: 1 } as Reading
INNER
