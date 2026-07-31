mkdir -p hardware/bad-plan apps/bad-app/src/input
cat > hardware/bad-plan/bad-plan.dts <<'INNER'
/dts-v1/;
/plugin/;

/ {
	olympia-keys {
		compatible = "gpio-keys";
		key-n {
			label = "olympia:pad-n";
			linux,code = <72>;
			gpios = <&gpio 12 1>;
			debounce-interval = <20>;
		};
		key-e {
			label = "olympia:pad-e";
			linux,code = <99>;
			gpios = <&gpio 8 1>;
			debounce-interval = <20>;
		};
		key-w {
			label = "olympia:pad-w";
			linux,code = <75>;
			gpios = <&gpio 14 1>;
			debounce-interval = <20>;
		};
		key-enc1 {
			label = "olympia:enc1-push";
			linux,code = <183>;
			gpios = <&gpio 27 1>;
			debounce-interval = <20>;
		};
	};
};
INNER
cat > hardware/bad-plan/bad-plan.snippet <<'INNER'
dtoverlay=rotary-encoder,pin_a=4,pin_b=17,relative_axis=1
dtparam=spi=on

# Encodeurs                         A     B     poussoir
#   encodeur 1                      4     18    26
#
# Pavé directionnel                       N 13   E  8
#                                         O 14
#
# 9 GPIO au total, sur 26 disponibles.
INNER
cat > apps/bad-app/src/input/panel.ts <<'INNER'
export const DIRECTIONS = ["n", "e", "s"] as const

export const DEFAULT_LAYOUT = {
  encoders: ["/dev/input/by-path/platform-rotary@5-event"],
  keys: "/dev/input/by-path/platform-olympia-keys-event",
  directions: { 72: "e", 99: "e" },
  pushes: { 183: 2 },
}
INNER
