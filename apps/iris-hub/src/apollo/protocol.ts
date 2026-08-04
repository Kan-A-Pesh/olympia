import { HubError } from "../error.js"

export const IDENTITY_COMMAND = "i\n"
export const ARM_COMMAND = "F\n"
export const STOP_COMMAND = "+"
export const RESET_COMMAND = "*"

export const IDENTITY_LENGTH = 17
export const SAMPLE_RATE_MIN_HZ = 5000
export const SAMPLE_RATE_MAX_HZ = 120000016
export const ANALOG_BUDGET_HZ = 494845
export const ANALOG_BIAS = 0x80
export const END_MARKER = 0x24
export const DATA_FLOOR = 0x30
export const FALLBACK_SCALE_V = 0.0257

export type DeviceIdentity = {
  analogChannels: number
  analogBytesPerSample: number
  digitalChannels: number
  version: string
}

export type Calibration = {
  scaleV: number
  offsetV: number
}

export const sampleRateCommand = (rateHz: number): string => `R${Math.round(rateHz)}\n`
export const sampleCountCommand = (count: number): string => `L${Math.round(count)}\n`
export const calibrationCommand = (channel: number): string => `a${channel}\n`
export const analogChannelCommand = (channel: number, isEnabled: boolean): string =>
  `A${isEnabled ? 1 : 0}${channel}\n`
export const digitalChannelCommand = (channel: number, isEnabled: boolean): string =>
  `D${isEnabled ? 1 : 0}${channel}\n`

/**
 * Décode la réponse à `i`, de la forme SRPICO,A<nn><s>D<nn>,<vv>.
 *
 * Le firmware ne termine pas ses réponses : l appelant lit jusqu à un court
 * silence, pas jusqu à un retour à la ligne.
 */
export function parseIdentity(response: string): DeviceIdentity {
  const match = /^SRPICO,A(\d{2})(\d)D(\d{2}),(\d{2})/.exec(response.trim())
  if (!match) {
    throw new HubError("PROTOCOL_UNEXPECTED", `identité illisible : ${JSON.stringify(response)}`)
  }

  const [, analog, bytes, digital, version] = match
  return {
    analogChannels: Number(analog),
    analogBytesPerSample: Number(bytes),
    digitalChannels: Number(digital),
    version: version ?? "",
  }
}

/**
 * Décode la réponse à `a<ch>`, de la forme <échelle>x<décalage> en microvolts.
 *
 * Le firmware renvoie la même valeur quel que soit le canal demandé : le
 * numéro est analysé puis ignoré.
 */
export function parseCalibration(response: string): Calibration {
  const match = /^(-?\d+)x(-?\d+)/.exec(response.trim())
  if (!match) {
    throw new HubError("PROTOCOL_UNEXPECTED", `calibration illisible : ${JSON.stringify(response)}`)
  }
  return {
    scaleV: Number(match[1]) / 1e6,
    offsetV: Number(match[2]) / 1e6,
  }
}

/** Un octet analogique porte 7 bits utiles, biaisés pour rester hors de l ASCII de contrôle. */
export const toVolts = (byte: number, calibration: Calibration): number =>
  (byte - ANALOG_BIAS) * calibration.scaleV + calibration.offsetV

/** Le RP2040 ne convertit qu une voie à la fois : le budget est partagé. */
export function maxSampleRateHz(analogChannels: number): number {
  if (analogChannels <= 0) return SAMPLE_RATE_MAX_HZ
  return Math.floor(ANALOG_BUDGET_HZ / analogChannels)
}

export function assertSampleRate(rateHz: number, analogChannels: number): void {
  if (rateHz < SAMPLE_RATE_MIN_HZ || rateHz > SAMPLE_RATE_MAX_HZ) {
    throw new HubError(
      "PROTOCOL_UNEXPECTED",
      `débit ${rateHz} Hz hors des bornes ${SAMPLE_RATE_MIN_HZ}–${SAMPLE_RATE_MAX_HZ}`,
    )
  }
  const budget = maxSampleRateHz(analogChannels)
  if (rateHz > budget) {
    throw new HubError(
      "PROTOCOL_UNEXPECTED",
      `${rateHz} Hz sur ${analogChannels} voies dépasse le budget de ${budget} Hz`,
    )
  }
}

/** Nombre d octets qu occupe un instant de mesure sur le fil. */
export const sliceBytes = (analogChannels: number, digitalChannels: number): number =>
  Math.ceil(digitalChannels / 7) + analogChannels
