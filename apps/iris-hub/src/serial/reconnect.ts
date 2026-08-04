export const RECONNECT_BASE_MS = 250
export const RECONNECT_MAX_MS = 8000

/**
 * Délai avant une nouvelle tentative de connexion.
 *
 * Croissant pour ne pas marteler un appareil absent, plafonné pour rester
 * réactif au rebranchement, et bruité pour que plusieurs appareils débranchés
 * ensemble ne reviennent pas tous à la même milliseconde.
 */
export function reconnectDelayMs(attempt: number, random: () => number = Math.random): number {
  const growth = Math.min(RECONNECT_BASE_MS * 2 ** attempt, RECONNECT_MAX_MS)
  return Math.round(growth * (0.5 + random() * 0.5))
}
