cat > packages/bad-pkg/src/calls.ts <<'INNER'
export function bad() {
  console.log("x")
  try { doThing() } catch (e) {}
  throw "not an error"
}
INNER
