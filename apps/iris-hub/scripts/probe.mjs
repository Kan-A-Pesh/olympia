// Sonde série pour découvrir le protocole d un appareil branché.
//
//   node scripts/probe.mjs list
//   node scripts/probe.mjs /dev/cu.usbmodem1101 i
//   node scripts/probe.mjs /dev/cu.usbmodem1101 '*' 'i' --wait 500
//
// Affiche la réponse en hexadécimal ET en texte, parce qu un protocole série
// mélange presque toujours les deux.

import { SerialPort } from "serialport"

const BAUD_RATE = 115200
const DEFAULT_WAIT_MS = 400

const args = process.argv.slice(2)

function parseWait() {
  const index = args.indexOf("--wait")
  if (index === -1) return DEFAULT_WAIT_MS
  const value = Number(args[index + 1])
  args.splice(index, 2)
  return Number.isFinite(value) ? value : DEFAULT_WAIT_MS
}

const waitMs = parseWait()

function describe(bytes) {
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join(" ")
  const text = [...bytes].map((b) => (b >= 0x20 && b < 0x7f ? String.fromCharCode(b) : ".")).join("")
  return { hex, text }
}

async function list() {
  const ports = await SerialPort.list()
  if (ports.length === 0) {
    console.log("aucun port série")
    return
  }
  for (const port of ports) {
    const vid = port.vendorId ?? "----"
    const pid = port.productId ?? "----"
    const maker = port.manufacturer ?? ""
    console.log(`${port.path}\tVID ${vid} PID ${pid}\t${maker}`)
  }
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function probe(path, commands) {
  const port = new SerialPort({ path, baudRate: BAUD_RATE, lock: true })

  const chunks = []
  port.on("data", (chunk) => chunks.push(chunk))
  port.on("error", (error) => {
    console.error("erreur port :", error.message)
    process.exitCode = 1
  })

  await new Promise((resolve, reject) => {
    port.once("open", resolve)
    port.once("error", reject)
  })
  console.log(`ouvert ${path} à ${BAUD_RATE} bauds\n`)

  for (const command of commands) {
    chunks.length = 0
    console.log(`→ ${JSON.stringify(command)}`)
    port.write(command)
    await new Promise((resolve) => port.drain(resolve))
    await wait(waitMs)

    const received = Buffer.concat(chunks)
    if (received.length === 0) {
      console.log("← (rien)\n")
      continue
    }
    const { hex, text } = describe(received)
    console.log(`← ${received.length} octets`)
    console.log(`  hex  ${hex.slice(0, 240)}${hex.length > 240 ? " …" : ""}`)
    console.log(`  txt  ${text.slice(0, 120)}${text.length > 120 ? " …" : ""}\n`)
  }

  await new Promise((resolve) => port.close(resolve))
}

if (args.length === 0 || args[0] === "list") {
  await list()
} else {
  const [path, ...commands] = args
  if (commands.length === 0) {
    console.error("donne au moins une commande à envoyer")
    process.exitCode = 1
  } else {
    await probe(path, commands)
  }
}
