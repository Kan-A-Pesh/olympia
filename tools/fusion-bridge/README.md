# fusion-bridge

Pont entre Claude Code et Fusion 360. Deux moitiés :

- `addin/OlympiaBridge.py` — add-in Fusion qui écoute sur `127.0.0.1:8765`
- `server.py` — serveur MCP qui relaie vers cet add-in

## Pourquoi deux moitiés

**L'API Fusion n'est appelable que depuis son thread principal.** Un serveur HTTP tourne
forcément dans un thread séparé : il ne peut donc pas toucher l'API directement, sous peine
de faire planter Fusion de façon erratique.

Le seul mécanisme que Fusion offre pour revenir sur le thread principal depuis un thread de
travail est l'**événement personnalisé**. Chaque requête HTTP dépose donc son travail dans
une file, déclenche l'événement, et attend que le gestionnaire — qui, lui, s'exécute sur le
thread principal — ait posé le résultat.

C'est ce point qui fait échouer la plupart des tentatives de piloter Fusion à distance.

## Installation

L'add-in et le serveur MCP sont déjà installés. Pour refaire l'opération ailleurs :

```sh
# Add-in
DEST="$HOME/Library/Application Support/Autodesk/Autodesk Fusion 360/API/AddIns/OlympiaBridge"
mkdir -p "$DEST" && cp addin/OlympiaBridge.* "$DEST/"

# Serveur MCP
python3 -m venv .venv && .venv/bin/pip install "mcp[cli]"
claude mcp add fusion -s user -- "$PWD/.venv/bin/python" "$PWD/server.py"
```

## Utilisation

1. Ouvrir Fusion avec un document de conception.
2. **Utilitaires → Scripts et compléments → onglet Compléments → OlympiaBridge → Exécuter.**
   Une boîte de dialogue confirme que le pont écoute.
3. Laisser Fusion ouvert. Le pont s'arrête depuis le même panneau.

Sans cette étape, tous les outils répondent que le pont ne répond pas — c'est le message à
lire en premier quand quelque chose ne marche pas.

## Outils exposés

| Outil | Rôle |
|---|---|
| `fusion_health` | vérifie que l'add-in tourne |
| `fusion_info` | corps, composants, cotes d'encombrement, paramètres |
| `fusion_screenshot` | capture la vue en iso, face, profil, dessus… |
| `fusion_eval` | exécute du Python dans le contexte Fusion |
| `fusion_set_parameter` | change une cote et régénère le modèle |

`fusion_eval` reçoit `adsk`, `app`, `ui`, `design` et `root` déjà en portée. Ce qui est
affecté à `result` est renvoyé.

## Le piège des unités

`ValueInput.createByReal` attend des **centimètres** et des **radians**. Donc
`createByReal(5)` vaut 5 cm, et `createByReal(18)` vaut 18 radians, pas 18 degrés.

Utiliser `createByString` avec une unité explicite — `"340 mm"`, `"18 deg"` — élimine le
problème. Les cotes lues sur l'API sont également en centimètres : les multiplier par 10
pour obtenir des millimètres.

## Sécurité

Le serveur n'écoute que sur `127.0.0.1`, sans authentification : quiconque peut exécuter du
code sur cette machine peut piloter Fusion pendant que le pont tourne. C'est acceptable
pour un poste de développement personnel, et c'est la raison pour laquelle l'add-in ne
démarre **pas** automatiquement — il faut le lancer à la main à chaque session.
