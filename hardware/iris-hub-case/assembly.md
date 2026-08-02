# Montage — iris-hub-case

## Sécurité électrique

Le boîtier contient du **230 V** : l'alimentation Mean Well est raccordée au secteur par
une embase avec porte-fusible. Trois règles non négociables.

**Isolation.** La zone secteur — embase, fusible, interrupteur, bornier d'entrée du
LRS-50 — est cloisonnée par une paroi imprimée pleine. Aucune vis traversante ne débouche
dans cette zone, et aucune partie métallique accessible de l'extérieur ne s'en approche à
moins de 8 mm.

**Longueur des vis du LRS-50.** Le fabricant limite la pénétration à **3 mm** sur les
trous de base. Une vis M3 × 6 avec une paroi de 3 mm laisse exactement 3 mm de
pénétration. Une M3 × 8 touche l'électronique interne : ne pas substituer.

**Ordre de câblage.** Le secteur se raccorde en dernier, boîtier ouvert, et on vérifie la
continuité de terre avant la première mise sous tension.

## Ordre de montage

### 1. Inserts laiton

Poser les 6 inserts Ruthex M3 × 5,7 au fer à souder, pointe à 200–250 °C, **avant** tout
autre montage : le plastique refoulé doit pouvoir s'échapper et la pièce être manipulable.

L'insert entre perpendiculairement, sans forcer, jusqu'à affleurer la surface. Un insert
qui penche fera diverger la vis et fissurera le bossage.

Perçage prévu au modèle : ⌀4,0 mm sur 6,7 mm de profondeur, dans un bossage de ⌀8,6 mm.

> **À calibrer avant de lancer les grosses pièces.** Imprimer un coupon d'essai avec trois
> trous à 3,9 / 4,0 / 4,1 mm et poser un insert dans chacun. Le bon diamètre est celui où
> l'insert entre droit sans repousser de bourrelet. Reporter la valeur dans le paramètre
> `insert_hole_dia` du script Fusion.

### 2. Organes internes, demi-coque gauche

1. Raspberry Pi 4 sur ses 4 entretoises M2,5 × 5, vis M2,5 × 6.
2. Mean Well LRS-50-12, 2 vis M3 × 6 **uniquement**.
3. Buck XL4016 sur entretoises M3 × 5, 4 vis M3 × 8.

Régler la tension de sortie du buck à **5,1 V à vide** avant de brancher le Pi, puis
vérifier en charge. Le potentiomètre dépasse de 15,2 mm du bord de la carte : prévoir
l'accès, ou le régler avant montage définitif.

### 3. Organes internes, demi-coque droite

Carte driver eDP sur entretoises M3 × 5, dans le coin arrière-droit, connecteur eDP
orienté vers la fente du berceau. Le câble ne fait que 25 mm : présenter la carte avant de
serrer, et vérifier que le connecteur atteint la fente sans tension.

### 4. Commandes

Les 4 encodeurs EC11 et les 8 tactiles sont soudés sur un **PCB de façade** aligné derrière
la face inclinée.

> L'EC11 **n'a pas d'ergot anti-rotation côté façade** : les ergots visibles sur les plans
> sont des pattes de fixation PCB. Sans ce PCB, l'écrou M7 seul finira par se desserrer et
> l'encodeur tournera dans son trou.

Filtres RC d'anti-rebond — 10 kΩ et 100 nF par voie A et B — sur le même PCB, au plus près
des encodeurs.

### 5. Assemblage des demi-coques

Rapprocher les deux demi-coques après avoir passé les faisceaux à travers le plan de
joint, puis serrer les 6 vis M3 × 12 progressivement, en croix.

### 6. Écran

Coller le joint mousse 2 mm × 10 mm au fond de la gorge du berceau. Passer le câble eDP
par la fente **avant** de poser le capot. Le capot se pose sans être vissé : il est retenu
par la gorge et son inclinaison.

## Contrôles avant première mise sous tension

- Continuité de terre entre l'embase secteur et toute partie métallique accessible.
- Aucune vis ne débouche dans la zone secteur.
- Sortie du buck mesurée à 5,1 V ± 0,1 V, alimentation en charge.
- Câble eDP non tendu, capot posé.
- Le boîtier ne bascule pas quand on appuie fermement sur les molettes.

## Point thermique à surveiller

Le buck XL4016 est donné pour 8 A mais nécessite une ventilation au-delà de **5 A
continus**. Le Raspberry Pi 4 en pointe demande précisément 5 A. On est donc à la limite
du refroidissement passif, dans un volume fermé partagé avec une alimentation.

Vérifier la température du dissipateur après une heure de fonctionnement en charge. Si
elle dépasse 70 °C, ajouter des ouïes sous les pieds arrière — la surélévation de 10 mm
ménage déjà le passage d'air.
