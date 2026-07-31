cat > hardware/bad-case/bad.dts <<'INNER'
/ {
	keys {
		key-a { linux,code = <30>; gpios = <&gpio 4 1>; };
		key-b { linux,code = <30>; gpios = <&gpio 4 1>; };
	};
	pins { brcm,pins = <4 5>; };
};
INNER
printf 'dtoverlay=rotary-encoder,pin_b=17,relative_axis=1\n' > hardware/bad-case/bad.snippet
