mkdir -p apps/bad-app/src/misc
printf 'export const SEED = 2\n' > apps/bad-app/src/misc/tuning.ts
printf 'export const miscellaneous = [1, 2]\n' > packages/bad-pkg/src/leftovers.ts
