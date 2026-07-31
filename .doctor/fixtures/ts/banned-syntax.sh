cat > packages/bad-pkg/src/syntax.ts <<'INNER'
export interface Legacy { value: any }
export let mutable = 1
INNER
