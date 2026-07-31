const MAGIC = 0x48574631
const HEADER_BYTES = 20
const MAX_CHANNELS = 8

export type WaveformChannel = {
  voltsPerSample: number
  offsetVolts: number
  samples: Uint8Array | Uint16Array
}

export type WaveformFrame = {
  sampleRateHz: number
  capturedAt: number
  bitsPerSample: 8 | 16
  channels: WaveformChannel[]
}

export function encodeWaveform(frame: WaveformFrame): Uint8Array {
  const { channels, bitsPerSample } = frame
  const channelCount = channels.length
  if (channelCount < 1 || channelCount > MAX_CHANNELS) {
    throw new RangeError(`channel count out of range: ${channelCount}`)
  }

  const first = channels[0]
  if (!first) throw new RangeError("waveform frame has no channels")
  const samplesPerChannel = first.samples.length
  if (channels.some((c) => c.samples.length !== samplesPerChannel)) {
    throw new RangeError("all channels must carry the same sample count")
  }
  if (samplesPerChannel > 0xffff) {
    throw new RangeError(`sample count exceeds frame limit: ${samplesPerChannel}`)
  }

  const bytesPerSample = bitsPerSample / 8
  const scalesBytes = channelCount * 8
  const payloadBytes = channelCount * samplesPerChannel * bytesPerSample
  const buffer = new ArrayBuffer(HEADER_BYTES + scalesBytes + payloadBytes)
  const view = new DataView(buffer)

  view.setUint32(0, MAGIC, false)
  view.setUint8(4, channelCount)
  view.setUint8(5, bitsPerSample)
  view.setUint16(6, samplesPerChannel, true)
  view.setUint32(8, frame.sampleRateHz, true)
  view.setFloat64(12, frame.capturedAt, true)

  let offset = HEADER_BYTES
  for (const channel of channels) {
    view.setFloat32(offset, channel.voltsPerSample, true)
    view.setFloat32(offset + 4, channel.offsetVolts, true)
    offset += 8
  }

  for (const channel of channels) {
    for (let i = 0; i < samplesPerChannel; i++) {
      const sample = channel.samples[i] ?? 0
      if (bitsPerSample === 8) view.setUint8(offset, sample)
      else view.setUint16(offset, sample, true)
      offset += bytesPerSample
    }
  }

  return new Uint8Array(buffer)
}

export function decodeWaveform(bytes: Uint8Array): WaveformFrame {
  if (bytes.byteLength < HEADER_BYTES) throw new RangeError("waveform frame truncated")
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)

  if (view.getUint32(0, false) !== MAGIC) throw new TypeError("not a waveform frame")

  const channelCount = view.getUint8(4)
  const bitsPerSample = view.getUint8(5)
  if (bitsPerSample !== 8 && bitsPerSample !== 16) {
    throw new TypeError(`unsupported sample width: ${bitsPerSample}`)
  }
  const samplesPerChannel = view.getUint16(6, true)
  const bytesPerSample = bitsPerSample / 8

  const expected = HEADER_BYTES + channelCount * 8 + channelCount * samplesPerChannel * bytesPerSample
  if (bytes.byteLength !== expected) {
    throw new RangeError(`waveform frame size mismatch: got ${bytes.byteLength}, expected ${expected}`)
  }

  const scales: Array<{ voltsPerSample: number; offsetVolts: number }> = []
  let offset = HEADER_BYTES
  for (let c = 0; c < channelCount; c++) {
    scales.push({ voltsPerSample: view.getFloat32(offset, true), offsetVolts: view.getFloat32(offset + 4, true) })
    offset += 8
  }

  const channels: WaveformChannel[] = []
  for (let c = 0; c < channelCount; c++) {
    const samples = bitsPerSample === 8 ? new Uint8Array(samplesPerChannel) : new Uint16Array(samplesPerChannel)
    for (let i = 0; i < samplesPerChannel; i++) {
      samples[i] = bitsPerSample === 8 ? view.getUint8(offset) : view.getUint16(offset, true)
      offset += bytesPerSample
    }
    const scale = scales[c]
    if (!scale) throw new RangeError("missing channel scale")
    channels.push({ ...scale, samples })
  }

  return {
    sampleRateHz: view.getUint32(8, true),
    capturedAt: view.getFloat64(12, true),
    bitsPerSample,
    channels,
  }
}

export function toVolts(channel: WaveformChannel, index: number): number {
  return (channel.samples[index] ?? 0) * channel.voltsPerSample + channel.offsetVolts
}
