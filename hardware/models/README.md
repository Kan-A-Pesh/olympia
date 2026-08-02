# Modèles CAO des composants

Les fichiers de ce dossier ne sont pas versionnés : ils sont lourds, leurs licences
varient, et ils se retéléchargent depuis les sources ci-dessous.

**Règle** : un modèle importé sert à vérifier l'encombrement et les collisions. **Aucune
cote de perçage ne se prend dessus.** Les perçages viennent des plans officiels, reportés
en paramètres dans `../iris-hub-case/fusion/iris_hub_case.py`.

## Ce qui existe officiellement

| Composant | Modèle 3D | Plan coté |
|---|---|---|
| Mean Well LRS-50-12 | **STEP officiel** | spec officielle, boîtier 239A |
| Raspberry Pi 4 Model B | aucun | PDF officiel RP-008343-DS-1 |
| Encodeur EC11 | aucun pour le générique | datasheets Alps et Bourns |
| Carte driver eDP | aucun, et n'existera pas | aucun — à mesurer |
| Bouton tactile 6 mm × 6 mm | via distributeurs | datasheet Omron B3F |
| Buck XL4016 | aucun | plan revendeur |

## Téléchargements

```sh
# Mean Well LRS-50-12 — le seul STEP officiel du projet
curl -L -o lrs-50-3d.zip https://www.meanwell.com/upload/pdf/LRS-50/LRS-50-3D.zip
unzip lrs-50-3d.zip          # → LRS-50.stp

# Raspberry Pi 4 — plan mécanique officiel, à lire pour coter les découpes
curl -L -o rpi4-mechanical.pdf \
  https://pip-assets.raspberrypi.com/categories/545-raspberry-pi-4-model-b/documents/RP-008343-DS-1-raspberry-pi-4-mechanical-drawing.pdf
```

Modèle 3D du Pi : aucun n'est publié par Raspberry Pi Ltd. Les modèles GrabCAD sont
utilisables comme volume d'encombrement, mais leur propre communauté signale des erreurs
d'échelle — à contrôler contre le plan officiel avant tout usage.

## Cotes officielles reportées dans le modèle

### Raspberry Pi 4 Model B

PCB 85 × 56 mm, coins R3,0. Quatre trous à **3,5 mm de chaque bord**, entraxes
**58 × 49 mm**. Le diamètre de 2,7 mm communément cité n'est **pas** lisible sur le plan
officiel — à recouper sur la spécification HAT avant de percer.

Hauteurs au-dessus du PCB, qui commandent les découpes de façade :

| Connecteur | Hauteur |
|---|---|
| USB-A | 16,0 mm |
| Ethernet RJ45 | 13,5 mm |
| Header GPIO 40 points | 8,5 mm |
| micro-HDMI, USB-C, jack | 6,0 mm |

### Mean Well LRS-50-12

99 × 82 × 30 mm, **tolérance ±1 mm sur tout le boîtier** — ne pas concevoir de logement
ajusté sur le STEP nominal.

Fixation **M3**, deux groupes distincts, avec des limites de pénétration différentes :

| Groupe | Entraxe | Pénétration maximale |
|---|---|---|
| Base | 55 mm | **3,0 mm** |
| Flanc | 74 mm | **5,0 mm** |

Dépasser la pénétration fait toucher l'électronique interne. C'est le piège de ce
composant.

### Encodeur EC11

Filetage de fixation **M7 × 0,75** — et non M9. Axe ⌀6,0 mm, perçage de façade
**⌀7,2–7,5 mm**.

Deux pièges :

- **Il n'y a pas d'ergot anti-rotation côté façade.** Les deux ergots à entraxe 12,5 mm
  visibles sur les plans sont des pattes de fixation *PCB*. Sans PCB support, l'encodeur
  tournera dans son trou malgré l'écrou.
- **L'axe cannelé chinois a 20 dents, le Bourns PEC11R en a 18.** Les boutons ne sont pas
  interchangeables entre les deux.

### Boutons du pavé — tactiles 6 mm × 6 mm

Retenus contre les poussoirs 12 mm, pour trois raisons mesurables : un poussoir 12 mm a
une **tête de ⌀17,5 mm** qui impose un entraxe d'au moins 18 mm, soit un pavé de 55 mm
hors de portée d'un pouce immobile ; sa durée de vie électrique n'est que de **10 000
cycles** contre 300 000 à 1 000 000 pour un tactile ; et il occupe **24 mm** derrière la
façade contre 5 mm.

Force d'actionnement : **1,47 N (150 gf)** plutôt que 100 gf. Sur une façade inclinée le
pouce repose naturellement sur le pavé, et 100 gf déclencherait des appuis parasites.

La course de 0,25 mm est faible : compenser par un capuchon haut (plongeur 7,0 ou 9,5 mm)
qui donne du levier et du ressenti. Les tactiles doivent être soudés sur un petit PCB
aligné derrière la façade, jamais câblés en l'air.

### Buck XL4016

PCB 61,0 × 40,5 mm, hors tout **61 × 41 × 27 mm** dissipateurs compris. Quatre trous M3,
entraxes **54,6 × 34,1 mm**, soit 3,2 mm de retrait sur les quatre bords. Le potentiomètre
de réglage dépasse de 15,2 mm au-delà du bord.

**Point thermique** : le module est donné pour 8 A mais nécessite une ventilation au-delà
de 5 A continus. Le Pi 4 en pointe demande précisément 5 A — on est donc exactement à la
limite du refroidissement passif, dans un boîtier fermé partagé avec une alimentation.
À surveiller, voire à surdimensionner.

### Carte driver eDP

Aucun modèle n'existe : les cartes eDP génériques sont des designs OEM anonymes, et deux
exemplaires achetés à six mois d'écart peuvent différer. À mesurer au pied à coulisse :
contour réel, position et diamètre des quatre trous, hauteur des composants en face
inférieure, et pour chaque mini-HDMI la distance du bord à l'axe ainsi que la hauteur du
corps.

## Format d'import

**STEP** pour tout ce qui existe. C'est un format exact : Fusion l'importe en corps solide
avec surfaces et arêtes analytiques.

**Jamais de STL pour coter.** Un maillage n'a pas de cercle — un trou y est un polygone à
N facettes, dont on ne peut pas accrocher le centre. Un STL sert à voir un encombrement,
pas à placer un perçage.

## Isolation secteur

Le Mean Well LRS-50-12 est le seul composant raccordé au 230 V. Son bornier d entrée est
cloisonné dans une zone isolée du boîtier, décrite dans
[la notice de montage](../iris-hub-case/assembly.md#sécurité-électrique).
