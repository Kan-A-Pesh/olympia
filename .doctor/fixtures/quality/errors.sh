cat > apps/bad-app/src/errors.ts <<'INNER'
export function load(path: string): string {
  try {
    return path
  } catch (problem) {
    throw new Error(`unreadable: ${path}`)
  }
}

export function blank(): Error {
  return new Error("failed")
}

export function later(): Promise<void> {
  return new Promise(async (resolve) => {
    await load("x")
    resolve()
  })
}

load("/etc/passwd")
INNER
