cat > packages/bad-pkg/src/names.ts <<'INNER'
export type ILegacy = { visible: boolean }
export type ThingType = { ready: boolean }
INNER
