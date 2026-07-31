mkdir -p packages/bad-deps packages/hermes-protocol
cat > packages/bad-deps/package.json <<'INNER'
{
  "name": "@olympia/bad-deps",
  "type": "module",
  "scripts": { "postinstall": "node ./setup.js" },
  "dependencies": {
    "lodash": "*",
    "moment": "^2.30.0",
    "core-js": ">=3",
    "typescript": "^5.7.0",
    "left-pad": "git+https://github.com/stevemao/left-pad.git",
    "local-thing": "file:../local-thing",
    "early-thing": "1.0.0-beta.3"
  }
}
INNER
cat > packages/hermes-protocol/package.json <<'INNER'
{
  "name": "@olympia/hermes-protocol",
  "type": "module",
  "dependencies": { "express": "^4.21.0" }
}
INNER
