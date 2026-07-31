cat > package.json <<'INNER'
{
  "name": "olympia",
  "private": true,
  "type": "module",
  "engines": { "node": ">=22" }
}
INNER
mkdir -p packages/bad-build/src
cat > packages/bad-build/tsconfig.json <<'INNER'
{
  "compilerOptions": {
    "target": "ES5",
    "lib": ["ES2023", "DOM"],
    "declaration": true,
    "declarationMap": false,
    "inlineSources": true,
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src/**/*.ts"],
  "exclude": ["src/**/*.test.ts"]
}
INNER
cat > turbo.json <<'INNER'
{ "tasks": { "build": { "cache": false } } }
INNER
