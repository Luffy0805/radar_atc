# Radar ATC

**Mod Minetest** — Surveillance aérienne, contrôle du trafic aérien et gestion d'aéroports pour le mod [laptop](https://content.minetest.net/packages/mt-mods/laptop/).

---

## Dépendances

| Mod | Rôle |
|-----|------|
| `laptop` | Fournit l'interface d'application et l'ordinateur portable |
| `airutils` | Fournit les avions détectables par le radar |

---

## Installation

1. Placer le dossier `radar_atc/` dans `<minetest>/mods/`
2. Activer le mod dans les paramètres de la partie
3. Crafting de l'application depuis le laptop

---

## Vue d'ensemble

Radar ATC est une application qui s'exécute sur le **laptop** (`laptop` mod). Elle permet à un opérateur de :

- **Surveiller le trafic aérien** en temps réel sur un radar
- **Gérer des aéroports** (créer des aéropotrs, configurer les pistes, définir des coordonnées approches)
- **Traiter les demandes ATC** des pilotes (atterrissage, décollage, survol, approche)
- **Communiquer par radio** avec les pilotes
- **Contrôler à distance** un autre aéroport via mot de passe ou antenne de liaison
- **Publier des NOTAM** (avis aux pilotes) par aéroport

---

## Onglets de l'application

### 🟢 Radar

Affiche une vue radar en temps réel centrée sur la position de l'ordinateur (ou sur l'aéroport contrôlé à distance).

**Éléments affichés :**
- Cercle radar avec anneaux de distance
- Avions sous forme de blips avec traînée (historique de position)
- Altitude en mètres et pieds au survol
- Indicateur d'aéroport lié et portée active

**Portées disponibles :** 500 m, 750 m, 1 000 m, 1 500 m, 2 000 m, 3 000 m, 5 000 m

> ⚠️ Les portées supérieures à **1 000 m** nécessitent un **Transpondeur ASR** placé à moins de 75 blocs de l'aéroport actif. Sans transpondeur, seules les portées ≤ 1 000 m sont disponibles dans le menu.

---

### ✈️ Aéroports

Liste tous les aéroports enregistrés et permet de **prendre le contrôle** d'un aéroport distant.

**Informations affichées par aéroport :**
- Identifiant OACI, nom complet, position
- Pistes : désignation, longueur, largeur, coordonnées d'approche

**Prise de contrôle d'un aéroport distant :**

Un ordinateur peut contrôler un aéroport autre que son aéroport lié. Deux méthodes :
1. **Mot de passe distant** — saisir le mot de passe défini pour changer d'aéroport (pr défaut "airport")
2. **Antenne de liaison** — si une `Antenne de liaison ATC` est présente à moins de 75 blocs de l'ordinateur, la connexion est autorisée sans mot de passe

Une fois en contrôle distant, le radar se centre sur l'aéroport cible et le transpondeur recherché est celui de cet aéroport.

**Pistes indépendantes :** liste des pistes sans aéroport ATC associé, visibles par tous les pilotes.

---

### 📡 ATC

Interface de contrôle du trafic aérien pour l'aéroport actif.

**Sous-onglet Demandes :**
- Liste des demandes en attente des pilotes (atterrissage, décollage, survol, approche)
- Chaque demande affiche : pilote, modèle d'avion, type, altitude (survol), heure
- Actions : **Autoriser** (avec piste et instructions optionnelles), **En attente**, **Refuser**
- Les demandes deviennent « anciennes » après 90 secondes (grisées) — le pilote peut en renvoyer une nouvelle
- Pagination : 3 demandes par page

**Sous-onglet Radio :**
- Messages radio libres envoyés par les pilotes via `/atc <ID> msg <texte>`
- Conversations groupées par pilote

**Sous-onglet NOTAM :**
- Avis aux pilotes publiés par l'opérateur ATC
- Maximum 10 lignes par aéroport
- Consultables par les pilotes via la commande `/notam ID`

**Sous-onglet Log :**
- Historique des 10 dernières décisions ATC (autorisation/refus)

---

### 🔒 Admin

Accès protégé par mot de passe (par défaut : `admin`).

**Gestion des aéroports :**
- Créer un aéroport (identifiant OACI, nom, position)
- Ajouter/supprimer des pistes (désignation automatique depuis les coordonnées, largeur, coordonnées d'approche par sens)
- Supprimer un aéroport
- Pagination : 10 aéroports par page

**Gestion des mots de passe** *(priv `atc` requis)* :
- Bouton `🔑 Mots de passe` visible uniquement aux joueurs ayant le privilège `atc`
- Affiche les mots de passe courants en clair (admin et distant)
- Permet de les modifier — les nouveaux mots de passe sont **persistants** (survivent aux redémarrages), et ne seront pas affichés en dur dans le code ! 

---

## Nœuds

### Transpondeur ASR (`radar_atc:transponder`)

Tour radar rotative réaliste (mesh 3D) qui étend la portée du radar au-delà de 1 000 m.

- Doit être placé à **moins de 75 blocs** de l'aéroport qu'il dessert (dans le rayon `airport_link_r`)
- Sa présence est **mémorisée** dans les données de l'aéroport — il n'est pas nécessaire que le chunk soit chargé pour que le radar reconnaisse son existence
- L'antenne tourne automatiquement quand un joueur est à moins de 48 blocs (veille sinon)

**Craft :**

```
[ Parabole  ]  [ Magnétron ]  [ Parabole  ]
[ Guide d'onde ]  [ Moteur  ]  [ Guide d'onde ]
[ Bloc acier ]  [ Module com ]  [ Bloc acier ]
```

---

### Antenne de liaison ATC (`radar_atc:link_antenna`)

Tour de télécommunication (~6 blocs de haut) qui permet à un ordinateur radar de prendre le contrôle de **n'importe quel aéroport sans mot de passe**.

- Doit être placée à **moins de 75 blocs** de l'ordinateur radar
- Aucune configuration nécessaire — la simple présence suffit
- Peut être orientée selon la direction de pose (`facedir`)

**Craft :**

```
[    vide    ]  [ Parabole  ]  [    vide    ]
[ Guide d'onde ]  [ Module com ]  [ Guide d'onde ]
[ Bloc acier ]  [ Magnétron ]  [ Bloc acier ]
```

---

### Composants de craft (non posables)

| Item | Craft | Usage |
|------|-------|-------|
| **Module de communication** | 2× or + 2× mese + 2× cuivre + acier | Transpondeur + Antenne |
| **Parabole** | 4× acier + diamant | Transpondeur + Antenne |
| **Guide d'onde** ×2 | 4× cuivre + 2× or | Transpondeur + Antenne |
| **Magnétron** | 4× obsidienne + 2× acier + mese (bloc) | Transpondeur + Antenne |
| **Moteur de rotation** | 4× acier + 4× cuivre + mese | Transpondeur uniquement |

---

## Commandes chat

### `/atc <ID|airport> <action> [param]`

Communication pilot → tour de contrôle. **Nécessite d'être à bord d'un avion** (sauf `airport`).

| Sous-commande | Description |
|---------------|-------------|
| `airport` | Affiche l'aéroport le plus proche avec distance et orientation (N, NNE, NE…) |
| `<ID> landing` | Demande d'autorisation d'atterrissage |
| `<ID> takeoff` | Demande d'autorisation de décollage |
| `<ID> flyover <alt_m>` | Demande de survol à l'altitude indiquée (en mètres) |
| `<ID> approach` | Demande d'instructions d'approche |
| `<ID> msg <texte>` | Message radio libre vers la tour |

**Anti-doublon :** un pilote ne peut pas renvoyer la même demande avant 15 secondes.

**Exemples :**
```
/atc airport
/atc LFPG landing
/atc LFPG flyover 500
/atc LFPG msg En courte finale piste 27
```

---

### `/notam <ID|nearest>`

Consulte les avis aux pilotes d'un aéroport.

```
/notam LFPG
/notam nearest
```

---

## Privilège `atc`

Le privilège `atc` est destiné aux administrateurs et contrôleurs en chef.

**Accès :**
```
/grant <joueur> atc
```

**Ce que ce privilège permet :**
- Voir et modifier les mots de passe admin et distant depuis l'interface (bouton `🔑 Mots de passe` dans Admin)
- Les modifications sont persistantes (stockées dans le mod storage)

**Ce que ce privilège ne permet PAS :**
- Passer outre le mot de passe admin pour déverrouiller l'onglet Admin
- Prendre le contrôle d'un aéroport sans mot de passe ou antenne

---

## Configuration (`config.lua`)

Tous les paramètres utilisent le préfixe `radar_atc.` :

```ini
# Intervalle de rafraîchissement du radar (secondes, défaut : 3)
radar_atc.timer_interval = 3

# Portée radar par défaut au démarrage (mètres, défaut : 1000)
radar_atc.default_radius = 1000

# Longueur des traînées radar (positions mémorisées, défaut : 5)
radar_atc.trail_len = 5

# Distance de liaison automatique ordinateur → aéroport (mètres, défaut : 500)
radar_atc.airport_link_r = 500

# Activer le système de transpondeur (true/false, défaut : true)
radar_atc.transponder_enabled = true

# Portée maximale sans transpondeur (mètres, défaut : 1000)
radar_atc.transponder_free_radius = 1000

# Distance de détection du transpondeur / antenne autour de l'aéroport (blocs, défaut : 75)
radar_atc.transponder_link_r = 75

# Vitesse de rotation de l'antenne ASR (rad/s, défaut : 0.55)
radar_atc.transponder_rotation_speed = 0.55

# Durée avant qu'une demande ATC devienne « ancienne » (secondes, défaut : 90)
radar_atc.req_stale_age = 90

# Anti-doublon commande /atc (secondes, défaut : 15)
radar_atc.req_cmd_cooldown = 15

# Nombre maximum de lignes NOTAM par aéroport (défaut : 10)
radar_atc.notam_max_lines = 10

# Nombre de décisions conservées dans le log ATC (défaut : 10)
radar_atc.atc_log_max = 10
```

---

## Flux de travail typique

### Mise en place d'un aéroport

1. Placer un **laptop** près de l'aéroport (dans un rayon de 500 m du centre)
2. Ouvrir l'application Radar ATC → onglet **Admin** → mot de passe `admin`
3. Créer un aéroport : identifiant OACI (ex. `LFPG`), nom, position du centre
4. Ajouter les pistes avec leurs coordonnées et désignations
5. Placer un **Transpondeur ASR** à moins de 75 blocs du centre pour débloquer les portées > 1 000 m

### Contrôle d'un aéroport distant

**Option A — Mot de passe :**
1. Onglet Aéroports → sélectionner l'aéroport cible
2. Cliquer `⊕ Prendre le contrôle`
3. Saisir le mot de passe distant (défaut : `airport`)

**Option B — Antenne de liaison :**
1. Placer une **Antenne de liaison ATC** à moins de 75 blocs de l'ordinateur
2. L'interface affiche directement `📡 Antenne de liaison [ID] Nom` et un bouton de connexion directe

### Workflow pilote

1. `/atc airport` — trouver l'identifiant et la direction de l'aéroport le plus proche
2. `/atc LFPG landing` — envoyer une demande d'atterrissage
3. Attendre la réponse de l'ATC (dans le jeu, par chat ou radio)
4. `/atc LFPG msg <texte>` — communiquer librement avec la tour

---

## Architecture technique

```
radar_atc/
├── init.lua          — Point d'entrée, enregistrement de l'app laptop, privilège atc
├── config.lua        — Paramètres globaux (CFG), lecture depuis minetest.conf
├── storage.lua       — Persistance : aéroports, état ATC, mots de passe, NOTAM, logs
├── utils.lua         — Fonctions utilitaires (distances, noms de pistes, helpers UI)
├── scan.lua          — Détection des avions dans le rayon radar
├── transponder.lua   — Nœuds ASR + antenne liaison, flag has_transponder par aéroport
├── ui_tabs.lua       — Construction des formspecs (4 onglets)
├── fields.lua        — Gestion des interactions utilisateur (tous les champs)
├── commands.lua      — Commandes chat /atc et /notam
├── models/           — Meshes 3D OBJ (antenne ASR, socle, tour liaison)
└── textures/         — Textures PNG (icônes, palettes, items de craft)
```

**Stockage (mod_storage) :**
- `airports_v5` — liste des aéroports (id, nom, pos, pistes, has_transponder)
- `atc_<ID>` — état ATC par aéroport (demandes, conversations radio)
- `atclog_<ID>` — log des décisions par aéroport
- `notam_<ID>` — NOTAM par aéroport
- `indep_strips_v1` — pistes indépendantes
- `passwords_v1` — mots de passe persistants

---

## Licence

Code source : **MIT**
Modèles 3D et textures : **CC BY-SA 4.0**

*Auteur : [Luffy0805]*
