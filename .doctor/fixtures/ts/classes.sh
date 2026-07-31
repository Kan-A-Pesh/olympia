cat > packages/bad-pkg/src/classes.ts <<'INNER'
export class Base extends Thing {
  private secret = "x"
}
INNER
