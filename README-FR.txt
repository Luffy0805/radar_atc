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

---

## Vue d'ensemble

Radar ATC est une application qui s'exécute sur le **laptop** (`laptop` mod). Elle permet à un opérateur de :

- **Surveiller le trafic aérien** en temps réel sur un radar (avions uniquement — les voitures ne sont pas affichées)
- **Gérer des aéroports** (créer des aéroports, configurer les pistes, définir des coordonnées d'approche)
- **Traiter les demandes ATC** des pilotes (atterrissage, décollage, survol, approche)
- **Communiquer par radio** avec les pilotes
- **Contrôler à distance** un autre aéroport via mot de passe ou antenne de liaison
- **Publier des NOTAM** (avis aux pilotes) par aéroport

> ⚠️ Les avions sans pilote dont le propriétaire est hors ligne sont automatiquement filtrés du radar (avions fantômes supprimés).

---

## Onglets de l'application

### 🟢 Radar

Affiche une vue radar en temps réel centrée sur la position de l'ordinateur (ou sur l'aéroport contrôlé à distance).

**Éléments affichés :**
- Cercle radar avec anneaux de distance
- Avions sous forme de blips avec traînée (historique de position)
- Altitude en mètres et pieds au survol
- Liste des appareils en vol : propriétaire, pilote, cap, vitesse, altitude, gaz, PV, carburant, autonomie, distance
- Indicateur d'aéroport lié et portée active
- Indication `MAJ : HH:MM:SS` en bas du radar

**Portées disponibles :** 500 m, 750 m, 1 000 m, 1 500 m, 2 000 m, 3 000 m, 5 000 m

> ⚠️ Les portées supérieures à **1 000 m** nécessitent un **Transpondeur ASR** placé à moins de 75 blocs de l'aéroport actif.

---

### ✈️ Aéroports

Liste tous les aéroports enregistrés et permet de **prendre le contrôle** d'un aéroport.

**Informations affichées par aéroport :**
- Identifiant OACI, nom complet, position centrale (coordonnées)
- Pistes : désignation, longueur, largeur, coordonnées d'approche **triées par seuil** (la coordonnée la plus proche du seuil 1 est affichée en premier)

**Badges :**
- `← associé` : l'ordinateur est lié à cet aéroport
- `← contrôlé` : l'ordinateur contrôle cet aéroport à distance

**Pistes indépendantes :** liste des pistes sans aéroport ATC associé, visibles par tous les pilotes.

---

### 📡 ATC

Interface de contrôle du trafic aérien pour l'aéroport actif.

**Sous-onglet Demandes :**
- Liste des demandes en attente (atterrissage, décollage, survol, approche)
- Actions : **Autoriser** (avec sélection de piste), **En attente**, **Refuser**
- **Boutons d'approche colorés :** vert si des coordonnées d'approche sont programmées pour ce seuil, rose si absentes
- Les messages radio dans les conversations s'affichent en intégralité, sans troncature

**Sous-onglet Radio :**
- Messages radio libres via `/atc <ID> msg <texte>`
- Conversations groupées par pilote

**Sous-onglet NOTAM :**
- Avis aux pilotes publiés par l'opérateur ATC
- Maximum 10 lignes par aéroport
- Consultables via `/notam <ID>`

**Sous-onglet Log :**
- Historique des 10 dernières décisions ATC

---

### 🔒 Admin

Accès protégé par mot de passe (par défaut : `admin`).

**Labels des formulaires colorés en bleu** pour une meilleure lisibilité.

**Gestion des aéroports :**
- Créer un aéroport (identifiant OACI, nom, position)
- Ajouter/supprimer des pistes (désignation automatique, largeur, coordonnées d'approche)
- Supprimer un aéroport

**Gestion des mots de passe** *(priv `atc` requis)* :
- Modifier les mots de passe admin et distant
- Les mots de passe sont persistants (survivent aux redémarrages)

---

## Nœuds

### Transpondeur ASR (`radar_atc:transponder`)

Tour radar rotative qui étend la portée au-delà de 1 000 m.

- Doit être placé à **moins de 75 blocs** de l'aéroport
- Craft :

```
[ Parabole  ]  [ Magnétron ]  [ Parabole  ]
[ Guide d'onde ]  [ Moteur  ]  [ Guide d'onde ]
[ Bloc acier ]  [ Module com ]  [ Bloc acier ]
```

---

### Antenne de liaison ATC (`radar_atc:link_antenna`)

Permet de prendre le contrôle de n'importe quel aéroport sans mot de passe.

- Doit être placée à **moins de 75 blocs** de l'ordinateur radar
- Craft :

```
[    vide    ]  [ Parabole  ]  [    vide    ]
[ Guide d'onde ]  [ Module com ]  [ Guide d'onde ]
[ Bloc acier ]  [ Magnétron ]  [ Bloc acier ]
```

---

### Composants de craft

| Item | Craft |
|------|-------|
| **Module de communication** | 2× or + 2× mese + 2× cuivre + acier |
| **Parabole** | 4× acier + diamant |
| **Guide d'onde** ×2 | 4× cuivre + 2× or |
| **Magnétron** | 4× obsidienne + 2× acier + bloc mese |
| **Moteur de rotation** | 4× acier + 4× cuivre + mese cristal |

---

## Commandes chat

### `/atc <action> [paramètres]`

**Nécessite d'être à bord d'un avion** (sauf `airport` et `navigate`).

| Commande | Description |
|----------|-------------|
| `/atc airport` | Affiche l'aéroport le plus proche avec distance, direction et **coordonnées centrales** |
| `/atc navigate [ID]` | Informations de navigation : position, pistes, caps, coordonnées d'approche, NOTAM |
| `/atc <ID> landing` | Demande d'autorisation d'atterrissage |
| `/atc <ID> takeoff` | Demande d'autorisation de décollage |
| `/atc <ID> flyover <alt_m>` | Demande de survol à l'altitude indiquée (mètres) |
| `/atc <ID> approach` | Demande d'instructions d'approche |
| `/atc <ID> msg <texte>` | Message radio libre vers la tour |

**Exemples :**
```
/atc airport
/atc navigate LFPG
/atc LFPG landing
/atc LFPG flyover 500
/atc LFPG msg En finale piste 27
```

---

### `/notam <ID|nearest>`

Consulte les NOTAM d'un aéroport.

---

## Privilège `atc`

```
/grant <joueur> atc
```

Permet de modifier les mots de passe depuis l'interface Admin.

---

## Configuration (`minetest.conf`)

```ini
radar_atc.timer_interval = 3
radar_atc.default_radius = 1000
radar_atc.trail_len = 5
radar_atc.airport_link_r = 500
radar_atc.transponder_enabled = true
radar_atc.transponder_free_radius = 1000
radar_atc.transponder_link_r = 75
radar_atc.transponder_rotation_speed = 0.55
radar_atc.req_stale_age = 90
radar_atc.req_cmd_cooldown = 15
radar_atc.notam_max_lines = 10
radar_atc.atc_log_max = 10
```

---

## Licence

| Contenu | Licence |
|---------|---------|
| Code source (`.lua`) | MIT |
| Modèles 3D et textures | CC BY-SA 4.0 |

Auteur : **Luffy0805**
