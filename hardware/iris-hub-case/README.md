# iris-hub-case

Boîtier base du hub : berceau d'écran, carte driver eDP, Raspberry Pi 4, alimentation,
bandeau de commandes.

**Bloqué en amont d'une mesure.** La longueur exacte de la nappe eDP et sa position de
sortie sur le capot ThinkPad fixent la position de la carte driver, donc toute la géométrie
interne. Rien ne doit être dessiné avant.

Cotes connues et contraintes : [`docs/03-hardware.md`](../../docs/03-hardware.md).

## À produire

- `iris-hub-case.f3d` — modèle Fusion 360 paramétrique
- `stl/` — pièces prêtes à imprimer, découpées pour un plateau de 256 mm
- `assembly.md` — ordre de montage et visserie

## Paramètres à exposer dans le modèle

| Paramètre | Source |
|---|---|
| `edp_flex_length` | **à mesurer** |
| `edp_exit_offset_x` | **à mesurer** |
| `panel_lid_thickness` | **à mesurer** sur le capot |
| `cradle_angle` | choix ergonomique, ~20° |
| `driver_board` | 82 × 60 × 5 mm |
| `pi4_board` | 85 × 56 mm, M2,5 entraxe 58 × 49 |
