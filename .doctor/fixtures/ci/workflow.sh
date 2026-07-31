mkdir -p .github/workflows
cat > .github/workflows/bad.yml <<'INNER'
name: bad

on: push

jobs:
  lint:
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 18
      - run: pnpm install
      - run: echo "${{ secrets.NPM_TOKEN }}"
      - run: pnpm run lint || true
INNER
