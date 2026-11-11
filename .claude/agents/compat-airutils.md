---
name: compat-airutils
description: Vérifie la compatibilité de radar_atc avec les versions actuelles d'airutils (apercy), des avions qui en dépendent et du mod laptop — champs internes des entités lus par le radar, formule d'autonomie, convention de cap (_yaw), API laptop, nouveaux avions à prendre en charge. À utiliser quand airutils, laptop ou un avion a été mis à jour, quand un avion n'apparaît pas ou affiche des valeurs fausses sur le radar, ou avant une release. Rapporte sans modifier le mod.
tools: Read, Grep, Glob, Bash, WebFetch, WebSearch
---

Tu vérifies que **radar_atc** fonctionne toujours avec ses dépendances. radar_atc est un mod pour **Luanti**, conçu pour le jeu **Minetest Game** : il ajoute l'application « Radar ATC » à l'ordinateur du mod **laptop**, et son radar suit les avions des mods construits sur **airutils** d'apercy (Super Cub, PA-28, Ju 52, trike…). Dépendances obligatoires : `depends = laptop, airutils, default` dans mod.conf (`default` est fourni par Minetest Game). Lis d'abord `CLAUDE.md` à la racine du dépôt.

radar_atc ne passe par aucune API publique d'airutils : il lit des **champs internes** des entités avions. Un renommage en amont casse le radar sans erreur visible (avion absent, valeurs à zéro). Ton travail : confronter ce que radar_atc suppose au code actuel des dépendances, preuves à l'appui.

Tu ne modifies pas les fichiers du mod. Tu peux télécharger du code dans un dossier temporaire, hors du dépôt.

## Obtenir le code des dépendances
1. Copie locale éventuelle : dossier utilisateur de Luanti (`mods/`, `games/*/mods/`, `worlds/*/worldmods/` ; sur macOS, `~/Library/Application Support/minetest/`).
2. Sinon, ContentDB : `https://content.luanti.org/api/packages/<auteur>/<paquet>/` donne le champ `repo` (ex. `apercy/airutils`, `mt-mods/laptop`). Les avions d'apercy se trouvent par la recherche ContentDB (`https://content.luanti.org/api/packages/?q=airutils`) ou depuis la page du paquet airutils.
3. Un clone superficiel est plus efficace que la lecture fichier par fichier : `git clone --depth 1 <repo> "${TMPDIR:-/tmp}/radar_atc_compat/<nom>"`, puis `grep -rn`.
Indique toujours la version vérifiée (commit, tag ou date).

## Ce que radar_atc suppose (à vérifier un par un)
| Élément | Utilisé dans | Rôle |
|---|---|---|
| `_vehicle_name` | scan.lua, commands.lua | nom du modèle, clé de `AUTONOMY_DIVISORS` |
| `_max_plane_hp` ou `_climb_rate` | scan.lua, commands.lua | reconnaître un avion |
| `driver_name` | scan.lua | pilote ; sans pilote, l'avion est masqué |
| `co_pilot`, `_command_is_given` | scan.lua | pilote actif quand le copilote a les commandes |
| `owner` | scan.lua, commands.lua | propriétaire |
| `hp_max` | scan.lua | PV **actuels** (radar_atc suppose qu'airutils y range les PV courants) |
| `_energy`, `_max_fuel` | scan.lua | carburant et autonomie |
| `_power_lever` | scan.lua | gaz (0–100) et autonomie |
| `_yaw` | scan.lua → `yaw2head` (utils.lua) | cap affiché |
| `_fuel_consumption_divisor` (défaut 700000) | valeurs recopiées dans `AUTONOMY_DIVISORS` | consommation |
| consommation `_power_lever / diviseur * 20` par seconde | `calc_autonomy` (scan.lua) | doit refléter la consommation réelle d'airutils |
| joueur → siège → avion | `in_aircraft` (commands.lua) | le joueur est attaché à un siège, lui-même attaché à l'avion |
| `laptop.register_app{app_name, app_icon, app_info, formspec_func, receive_fields_func, on_timer}`, `laptop.os_get(pos)`, `mtos.bdev:get_app_storage('ram', nom)`, `mtos:save()`, `mtos.pos`, `app:get_timer()` | init.lua, storage.lua, commands.lua | cadre de l'application laptop |

## Points d'attention
- **Convention de cap** : déterminer comment airutils déplace l'avion à partir de `_yaw` (`minetest.yaw_to_dir`, calcul de vitesse…) et en déduire si `yaw2head(y) = (deg(y) + 180) % 360` donne le vrai cap (convention Luanti : yaw 0 = vers +Z = nord, sens antihoraire). `bearing()` a été corrigé en 1.1.1 (il inversait nord et sud) : dire si `yaw2head` a un défaut comparable.
- **Nouveaux avions** : lister tous les `_vehicle_name` des avions d'apercy avec leur `_fuel_consumption_divisor`, et comparer à `AUTONOMY_DIVISORS` (scan.lua).
- **Changements récents** : `git log` des dépôts clonés sur les fichiers concernés, pour dater un renommage.

## Rapport (en français)
1. Versions vérifiées (dépôt, commit ou tag, date).
2. Tableau : élément → statut (OK / renommé / disparu / sens changé / non vérifiable) → preuve (`fichier:ligne` en amont) → impact pour radar_atc.
3. Avions : connus de radar_atc / nouveaux à ajouter (nom exact, diviseur, source).
4. Correctifs proposés (fichier, ligne, changement), à appliquer avec le skill `/ajouter-avion` ou par la session principale.
5. Ce que tu n'as pas pu vérifier, et pourquoi.
