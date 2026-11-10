---
name: ajouter-avion
description: Ajoute ou corrige la prise en charge d'un avion dans le radar de radar_atc (avions basés sur airutils d'apercy, ou compatibles) — détection, carburant, autonomie, affichage. À utiliser quand l'utilisateur cite un nouvel avion ou un mod d'avion (hydravion, Cessna, Ju 52, trike, Super Cub, PA-28…), quand un avion n'apparaît pas sur le radar ou n'est pas reconnu par /atc, ou quand son autonomie est absente ou fausse.
argument-hint: "<mod ou nom de l'avion>"
---

# Prendre en charge un avion

> **Contexte** — radar_atc est un mod pour **Luanti**, conçu pour le jeu **Minetest Game**. Il ajoute l'application « Radar ATC » à l'ordinateur du mod **laptop**, et son radar suit les avions des mods construits sur **airutils** d'apercy (Super Cub, PA-28, Ju 52, trike…). Ces mods doivent être installés et activés dans le monde : `depends = laptop, airutils, default` dans mod.conf (`default` est fourni par Minetest Game). Architecture et conventions : CLAUDE.md.

Avion demandé : $ARGUMENTS (si rien n'est indiqué, demander lequel et où trouver son code).

## Comment le radar voit un avion
- **Détection** (scan.lua, et la même condition dans `in_aircraft`, commands.lua) : entité avec `_vehicle_name` et (`_max_plane_hp` ou `_climb_rate ~= nil`), **avec un pilote** (`driver_name`). Les avions sans pilote sont masqués. La plupart des avions airutils sont donc détectés sans rien faire.
- **Autonomie** (`calc_autonomy`, scan.lua) : consommation par seconde = `_power_lever / diviseur * 20` ; autonomie en minutes = `_energy / consommation / 60`. Le diviseur vient de la table `AUTONOMY_DIVISORS`, indexée par `_vehicle_name`. Sans entrée dans la table, aucune autonomie n'est affichée.

## Étapes
1. **Trouver le code de l'avion** : chemin local donné par l'utilisateur, dossier `mods/` de Luanti, ou dépôt en ligne (la page ContentDB donne le lien). Pour une recherche large ou plusieurs avions, déléguer à l'agent `compat-airutils`.
2. Relever dans sa définition d'entité :
   - `_vehicle_name` : chaîne exacte, sensible à la casse, c'est la clé ;
   - `_fuel_consumption_divisor` : s'il est absent, l'avion hérite de la valeur par défaut d'airutils (700000 jusqu'ici, à revérifier dans le code d'airutils) ;
   - la présence de `_max_plane_hp` ou `_climb_rate`, de `_max_fuel`, `_energy`, `_power_lever`.
3. Ajouter l'entrée dans `AUTONOMY_DIVISORS` (scan.lua) et dans le commentaire d'en-tête qui liste les modèles.
4. Mettre à jour la **liste dupliquée** de `tab_radar` (ui_tabs.lua) : la condition `p.model == "PA-28" or …` qui affiche « Range : engine off ».
   Mieux, avec l'accord de l'utilisateur : supprimer ce doublon une fois pour toutes, en ajoutant `has_autonomy = AUTONOMY_DIVISORS[e._vehicle_name] ~= nil` au résultat de `scan()` et en testant `p.has_autonomy` dans ui_tabs.lua (aucune nouvelle globale nécessaire).
5. Avion pas du tout détecté : comparer ses champs à la condition de détection. Si elle doit évoluer, modifier **scan.lua et commands.lua ensemble**.
6. `python3 tools/check.py`.
7. À tester en jeu : voler avec l'avion, le sélectionner sur le radar, comparer carburant et autonomie avec sa jauge, gaz à 0 → « moteur coupé », `/atc <ID> landing` accepté à bord.

Modèles déjà connus : `PA-28`, `Super Cub`, `Super Duck Hydroplane` (700000), `Ju 52 3M`, `Ju52 3M Hydroplane` (500000), `trike` (1200000).
