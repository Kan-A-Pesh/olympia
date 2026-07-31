mkdir -p apps/bad-app/src/ui
cat > apps/bad-app/src/ui/device-list.tsx <<'INNER'
export function DeviceList({ devices }) {
  const [count, setCount] = useState(0)
  setCount(devices.length)
  useEffect(() => {
    window.addEventListener("resize", onResize)
    bus.subscribe("devices", onDevices)
  }, [])
  return (
    <ul style={{ padding: 0 }}>
      {devices.map((device, i) => (
        <li key={i}>{device.label}</li>
      ))}
      {devices.map((device) => (
        <li>{device.label}</li>
      ))}
    </ul>
  )
}
INNER
