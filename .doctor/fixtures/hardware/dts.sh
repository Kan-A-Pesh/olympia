mkdir -p hardware/broken-case
cat > hardware/broken-case/broken.dts <<'EOF'
/dts-v1/;
/plugin/;

/ {
	compatible = "brcm,bcm2711"

	fragment@0 {
		target-path = "/"
		__overlay__ {
			thing { missing-semicolon = <1> }
		}
	}
}
EOF
