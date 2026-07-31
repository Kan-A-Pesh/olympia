printf 'export const A = 1   \n' > packages/bad-pkg/src/spaces.ts
printf 'export const B = 1\r\n' > packages/bad-pkg/src/crlf.ts
printf 'export const C = 1' > packages/bad-pkg/src/no-newline.ts
