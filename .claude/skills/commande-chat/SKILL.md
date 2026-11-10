---
name: commande-chat
description: Ajoute ou modifie une commande chat de radar_atc (/atc et ses sous-commandes airport, navigate, landing, takeoff, flyover, approach, msg, ou /notam) — analyse des arguments, contrôle « à bord d'un avion », envoi des demandes à la tour, aide, documentation et traductions. À utiliser dès que l'utilisateur parle d'une commande, d'un nouveau type de demande pilote, d'un message dans le chat, de l'aide de /atc ou de ce que les pilotes voient dans le chat.
---

# Commandes chat (/atc, /notam)

> **Contexte** — radar_atc est un mod pour **Luanti**, conçu pour le jeu **Minetest Game**. Il ajoute l'application « Radar ATC » à l'ordinateur du mod **laptop**, et son radar suit les avions des mods construits sur **airutils** d'apercy (Super Cub, PA-28, Ju 52, trike…). Ces mods doivent être installés et activés dans le monde : `depends = laptop, airutils, default` dans mod.conf (`default` est fourni par Minetest Game). Architecture et conventions : CLAUDE.md.

Tout se trouve dans `commands.lua`. Le pilote parle à la tour par le chat ; la tour (onglet ATC du laptop) lit l'état partagé `atc_<ID>`.

## Structure de /atc
`func(name, param)` découpe `param` en `args`, puis teste dans l'ordre :
1. `airport` — aéroport et piste indépendante les plus proches ;
2. `navigate` — `IR [n]`, `RIR` ou `[ID]` ;
3. sinon `<ID> <action>` : `find_ap(ID)`, puis **`in_aircraft(name)` obligatoire**, actions `msg`, `landing`, `takeoff`, `flyover <alt>`, `approach`.

Une nouvelle sous-commande d'information se place **avant** l'étape 3, qui interprète `args[1]` comme un identifiant d'aéroport.

Retour : `return true, texte` (succès) ou `return false, texte` (erreur), ou plusieurs `minetest.chat_send_player(name, ligne)` suivis de `return true`. Couleurs : information `#88CCFF`, piste indépendante `#FFAA44`, erreur `#FF4444`, confirmation `#FFFF44`, autorisation `#00FF88`.

## Ajouter ou modifier une sous-commande
1. Pilote ou information ? Une action qui crée une demande exige d'être à bord (`in_aircraft`) et respecte l'anti-spam `CFG.req_cmd_cooldown`.
2. Valider les arguments : `args[n]` peut être nil ; identifiants en majuscules (`:upper()`) ; nombres via `tonumber` avec test de nil.
3. Nouveau type de demande : il faut aussi l'afficher et le traiter côté tour — rendu dans `tab_atc` (ui_tabs.lua), boutons `atc_*` dans fields.lua (skill `/interface`), entrée de journal `push_atc_log`, libellé dans la table `tf` de commands.lua.
4. Textes en `S()` avec `@1`, `@2`… dans l'ordre et en nombre égal aux arguments (sinon erreur Lua à l'exécution).
5. Aide : mettre à jour `params` et la `description` (chaîne `S()` multiligne : `\n` dans le Lua, **`@n` dans les .tr**).
6. Documentation : tableau des commandes de README.md **et** de README-FR.txt.
7. Traductions dans les 6 langues (skill `/traductions`).
8. `python3 tools/check.py`, puis à tester en jeu : à bord et à pied, identifiant inconnu, argument manquant, double envoi rapide.

## Pièges
- `minetest.get_player_by_name(name)` peut renvoyer nil (commande lancée depuis la console ou un pont IRC) ; `player:get_attach()` aussi.
- Convention de cap du mod : +X = est, +Z = nord, cap = `atan2(dx, dz)` (comme `hdg_str` et `card_dir`). `utils.bearing()` est en miroir nord/sud pour les pistes en diagonale : bug connu, voir `tools/tests/run.lua`.
- `card_dir` (commands.lua) utilise des abréviations françaises codées en dur (SO, O, NO…) et non traduites, alors que `head2card` (utils.lua) est en anglais. Dans du nouveau code, réutiliser `head2card` / `cap_to_dir` plutôt que dupliquer une table.
- La condition « est un avion » (`_vehicle_name` et `_max_plane_hp` ou `_climb_rate`) existe en double, dans `in_aircraft` (commands.lua) et dans `scan()` (scan.lua) : les garder identiques.
