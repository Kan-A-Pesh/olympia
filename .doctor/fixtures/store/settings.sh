mkdir -p apps/bad-app/src/store
cat > apps/bad-app/src/store/settings-schema.ts <<'INNER'
import { z } from "zod"

export const settingsSchema = z.object({
  brightness: z.number(),
  theme: z.string().default("dark"),
}).strict()

export const loadSettings = (raw: unknown) => settingsSchema.parse(raw)
INNER
cat > apps/bad-app/src/store/settings-read.ts <<'INNER'
export const readAll = (db: Db) => db.prepare("SELECT key, value FROM settings").all()
INNER
