# Nomenclature — iris-hub-case

## Électronique

| Qté | Élément | Cotes | Fixation |
|---|---|---|---|
| 1 | Capot ThinkPad T470 complet, dalle B140HAK01.0 | 335 mm × 230 mm × 7 mm | posé dans le berceau |
| 1 | Carte driver eDP générique | 75 mm × 56,5 mm × 16 mm | 4 × M3, cotes **à mesurer** |
| 1 | Raspberry Pi 4 Model B 2 Go | 85 mm × 56 mm × 18 mm | 4 × M2,5, entraxes 58 mm × 49 mm |
| 1 | Mean Well LRS-50-12 | 99 mm × 82 mm × 30 mm | 2 × M3, entraxe 55 mm, pénétration ≤ 3 mm |
| 1 | Buck XL4016 12 V → 5 V | 61 mm × 41 mm × 27 mm | 4 × M3, entraxes 54,6 mm × 34,1 mm |
| 4 | Encodeur rotatif EC11, axe cannelé 20 dents | canon M7 × 0,75, axe ⌀6 mm | écrou M7 + PCB support |
| 8 | Bouton tactile 6 mm × 6 mm, 150 gf | plongeur 7 mm ou 9,5 mm | soudé sur PCB dédié |
| 4 | Capuchon d'encodeur, cannelure 20 dents | ⌀18 mm | emmanché |
| 8 | Capuchon de tactile | ⌀9 mm | emmanché |
| 4 | Prise USB-A panneau, câblée vers le Pi | découpe 15 mm × 8 mm | 2 × M2 chacune |
| 1 | Interrupteur secteur bipolaire, zone isolée et cloisonnée | à définir | encliquetage |
| 1 | Embase secteur avec porte-fusible | à définir | 2 × M3 |

## Visserie et inserts

| Qté | Élément | Référence | Usage |
|---|---|---|---|
| 6 | Insert laiton M3, pose à chaud | Ruthex RX-M3×5,7 | assemblage des deux demi-coques |
| 6 | Vis M3 × 12 mm, tête cylindrique six pans creux | ISO 4762 | assemblage des demi-coques |
| 4 | Vis M2,5 × 6 mm | ISO 4762 | Raspberry Pi 4 |
| 4 | Entretoise M2,5 × 5 mm | — | Raspberry Pi 4 |
| 2 | Vis M3 × 6 mm | ISO 4762 | Mean Well, pénétration ≤ 3 mm |
| 4 | Vis M3 × 8 mm | ISO 4762 | buck XL4016 |
| 4 | Vis M3 × 8 mm | ISO 4762 | carte driver eDP |
| 8 | Entretoise M3 × 5 mm | — | driver eDP et buck |
| 1 | Joint mousse adhésif, 2 mm × 10 mm | — | gorge du berceau |

## Anti-rebond des encodeurs

L'overlay noyau `rotary-encoder` n'expose aucun paramètre d'anti-rebond, et les EC11 sont
mécaniques. Un filtre RC est donc nécessaire sur chaque voie.

| Qté | Élément | Valeur |
|---|---|---|
| 8 | Résistance | 10 kΩ |
| 8 | Condensateur céramique | 100 nF |

## Impression

| Pièce | Cotes | Plateau |
|---|---|---|
| Demi-coque gauche | 212 mm × 150 mm × 70 mm | tient dans 256 mm |
| Demi-coque droite | 128 mm × 150 mm × 70 mm | tient dans 256 mm |
| Pied arrière gauche | 46 mm × 58 mm × 10 mm | — |
| Pied arrière droit | 46 mm × 58 mm × 10 mm | — |

Matière : PETG de préférence au PLA — le boîtier enferme une alimentation et un Raspberry
Pi, et le PLA flue au-dessus de 55 °C.

## Cotes non mesurées

Ces valeurs sont des hypothèses et doivent être relevées sur les pièces réelles avant
impression :

- hauteur du capot ThinkPad : **230 mm à mesurer**
- position et diamètre des trous de la carte driver eDP : **à mesurer**
- hauteur des connecteurs mini-HDMI de la carte driver : **à mesurer**
- distance de la sortie du câble eDP au bord droit du capot : **à mesurer**

## Zone secteur

Le LRS-50-12 est raccordé au 230 V. Cette zone — embase, fusible, interrupteur, bornier
d entrée — est cloisonnée par une paroi pleine, sans vis traversante. Détail dans
[la notice de montage](assembly.md#sécurité-électrique).
