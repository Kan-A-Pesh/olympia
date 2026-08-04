const MAGIC = 0x48574631
const HEADER_BYTES = 20
const MAX_CHANNELS = 8
const MAX_SAMPLES_PER_CHANNEL = 0xffff
const MAX_BYTES_PER_SAMPLE = 2

/** Plafond absolu d une trame, pour qu un en-tête falsifié ne fasse pas allouer sans borne. */
export const MAX_FRAME_BYTES =
  HEADER_BYTES + MAX_CHANNELS * 8 + MAX_CHANNELS * MAX_SAMPLES_PER_CHANNEL * MAX_BYTES_PER_SAMPLE

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

type FrameHeader = {
  channelCount: number
  bitsPerSample: 8 | 16
  samplesPerChannel: number
  sampleRateHz: number
  capturedAt: number
}

function readHeader(view: DataView, byteLength: number): FrameHeader {
  if (byteLength < HEADER_BYTES) throw new RangeError("waveform frame truncated")
  if (byteLength > MAX_FRAME_BYTES) throw new RangeError(`waveform frame exceeds ${MAX_FRAME_BYTES} bytes`)
  if (view.getUint32(0, false) !== MAGIC) throw new TypeError("not a waveform frame")

  const bitsPerSample = view.getUint8(5)
  if (bitsPerSample !== 8 && bitsPerSample !== 16) {
    throw new TypeError(`unsupported sample width: ${bitsPerSample}`)
  }

  const channelCount = view.getUint8(4)
  if (channelCount < 1 || channelCount > MAX_CHANNELS) {
    throw new RangeError(`channel count out of range: ${channelCount}`)
  }

  return {
    channelCount,
    bitsPerSample,
    samplesPerChannel: view.getUint16(6, true),
    sampleRateHz: view.getUint32(8, true),
    capturedAt: view.getFloat64(12, true),
  }
}

export function decodeWaveform(bytes: Uint8Array): WaveformFrame {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  const header = readHeader(view, bytes.byteLength)
  const bytesPerSample = header.bitsPerSample / 8

  const expected =
    HEADER_BYTES + header.channelCount * 8 + header.channelCount * header.samplesPerChannel * bytesPerSample
  if (bytes.byteLength !== expected) {
    throw new RangeError(`waveform frame size mismatch: got ${bytes.byteLength}, expected ${expected}`)
  }

  const channels: WaveformChannel[] = []
  let offset = HEADER_BYTES + header.channelCount * 8

  for (let c = 0; c < header.channelCount; c++) {
    const scaleAt = HEADER_BYTES + c * 8
    const samples =
      header.bitsPerSample === 8
        ? new Uint8Array(header.samplesPerChannel)
        : new Uint16Array(header.samplesPerChannel)

    for (let i = 0; i < header.samplesPerChannel; i++) {
      samples[i] = header.bitsPerSample === 8 ? view.getUint8(offset) : view.getUint16(offset, true)
      offset += bytesPerSample
    }

    channels.push({
      voltsPerSample: view.getFloat32(scaleAt, true),
      offsetVolts: view.getFloat32(scaleAt + 4, true),
      samples,
    })
  }

  return {
    sampleRateHz: header.sampleRateHz,
    capturedAt: header.capturedAt,
    bitsPerSample: header.bitsPerSample,
    channels,
  }
}

export function toVolts(channel: WaveformChannel, index: number): number {
  return (channel.samples[index] ?? 0) * channel.voltsPerSample + channel.offsetVolts
}
