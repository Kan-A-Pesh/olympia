cat > hardware/bad-case/links.md <<'INNER'
# Liaisons

| Liaison | Câble | Longueur |
|---|---|---|
| dalle vers driver | nappe eDP 40 broches | 45 cm |
| Pi vers driver | micro-HDMI vers mini-HDMI | 20 cm |
INNER
printf 'dtoverlay=rotary-encoder,pin_a=9,pin_b=10,relative_axis=1\n' > hardware/bad-case/encoders.snippet
