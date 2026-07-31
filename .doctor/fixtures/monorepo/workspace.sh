mkdir -p packages/bad-turbo/src
cat > packages/bad-turbo/package.json <<'INNER'
{
  "name": "@olympia/bad-turbo",
  "type": "module",
  "engines": { "node": ">=18" },
  "scripts": {
    "ci": "turbo run lint typecheck",
    "compile": "tsc -p tsconfig.json"
  },
  "dependencies": { "zod": "^3.24.0" }
}
INNER
cat > packages/bad-turbo/turbo.json <<'INNER'
{ "extends": ["//"], "tasks": { "compile": {} } }
INNER
cat > packages/bad-turbo/tsconfig.json <<'INNER'
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": { "declaration": true, "outDir": "dist", "rootDir": "src" },
  "include": ["src/**/*.ts"],
  "exclude": ["src/**/*.test.ts"]
}
INNER
cat > tsconfig.base.json <<'INNER'
{
  "compilerOptions": {
    "target": "ES2023",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "verbatimModuleSyntax": true,
    "declaration": true
  }
}
INNER
cat > pnpm-workspace.yaml <<'INNER'
packages:
  - "packages/*"
  - "packages/bad-turbo"
  - "apps/*"
INNER
cat > pnpm-lock.yaml <<'INNER'
lockfileVersion: '9.0'

importers:

  packages/bad-turbo:
    dependencies:
      zod:
        specifier: ^3.20.0
        version: 3.25.76
    devDependencies:
      vitest:
        specifier: ^2.1.0
        version: 2.1.9

packages: {}
INNER
