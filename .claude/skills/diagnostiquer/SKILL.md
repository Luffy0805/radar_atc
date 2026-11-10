---
name: diagnostiquer
description: Enquête sur un bug ou un crash du mod radar_atc à partir d'un message d'erreur Luanti (debug.txt, console, « Runtime error from mod 'radar_atc' »), d'un comportement anormal décrit par un joueur ou d'une capture d'écran — localise la cause, l'explique, corrige au plus juste et ajoute un test de non-régression quand c'est possible. À utiliser dès que l'utilisateur colle une erreur, parle de crash, de serveur qui plante, de bouton qui ne fait rien, d'avion invisible sur le radar, de texte cassé ou de « ça ne marche plus ».
argument-hint: "<message d'erreur ou description du problème>"
---

# Diagnostiquer un bug

> **Contexte** — radar_atc est un mod pour **Luanti**, conçu pour le jeu **Minetest Game**. Il ajoute l'application « Radar ATC » à l'ordinateur du mod **laptop**, et son radar suit les avions des mods construits sur **airutils** d'apercy (Super Cub, PA-28, Ju 52, trike…). Ces mods doivent être installés et activés dans le monde : `depends = laptop, airutils, default` dans mod.conf (`default` est fourni par Minetest Game). Architecture et conventions : CLAUDE.md.

Problème signalé : $ARGUMENTS

## 1. Lire l'erreur
Forme typique :
`Runtime error from mod 'radar_atc' in callback on_receive_fields(): …/radar_atc/fields.lua:123: attempt to index a nil value (field '?')`, suivi d'un `stack traceback`.
- Le couple fichier:ligne est le point de départ ; remonter la pile jusqu'au premier fichier du mod.
- Le callback indique le chemin : formspec du laptop → `do_fields` / `build_fs` ; `nodetimer`, `LBM`, `on_step` → transpondeur et antennes (transponder.lua) ; `chatcommand` → commands.lua ; timer de l'application → `on_timer` (init.lua) → `scan()`.
- Journaux : `debug.txt` dans le dossier utilisateur de Luanti, ou la console du serveur. Pour plus de détails : `debug_log_level = verbose` dans minetest.conf.

## 2. Causes fréquentes dans ce mod
| Symptôme | Piste |
|---|---|
| `attempt to index a nil value` après un redémarrage | `data` (RAM du laptop) vidé : valeur par défaut manquante |
| idem autour de `find_ap(...)` | aéroport supprimé alors qu'un laptop le contrôle encore (`data.active_airport`) |
| erreur dans `scan()` ou `in_aircraft` | champ airutils absent ou renommé (agent `compat-airutils`) ; `get_luaentity()` ou `get_pos()` nil |
| `Not enough arguments`, `Too many arguments` ou `not in the correct order` (core.translate) | marqueurs `@N` de `S()` incohérents, détectés par `check.py i18n` |
| `attempt to concatenate a nil value` dans un `S()` | argument nil passé à `S()` (ex. `p.throttle`) |
| `area volume exceeds allowed value` | `find_nodes_in_area` avec `radar_atc.transponder_link_r` ≥ 80 |
| avertissement `Undeclared global variable` | faute de frappe ou `local` manquant, détecté par `check.py globals` |
| bouton sans effet | traitement absent de fields.lua, ou placé dans le mauvais bloc `data.tab`, détecté par `check.py fields` |
| formulaire tronqué, éléments étranges | texte non échappé (`fe()` manquant) |
| nom de piste incohérent avec son dessin | bug connu de `bearing()` (voir `tools/tests/run.lua`) |

## 3. Méthode
1. **Reproduire** : étapes minimales (onglet, action, données, un ou plusieurs joueurs). Si la reproduction est impossible, classer les hypothèses et dire ce qui permettrait de trancher.
2. **Localiser** : lire le code autour de la ligne et remonter l'origine de la donnée fautive (`data.*`, mod_storage, champ d'entité).
3. **Expliquer** la cause à l'utilisateur avant de corriger si le correctif n'est pas évident.
4. **Corriger au plus juste** : garde-fou au plus près de la source ; pas de `pcall` silencieux qui masque l'erreur ; pas de refonte au passage.
5. **Test de non-régression** si la logique est testable sans moteur (utils.lua, calculs) : l'ajouter dans `tools/tests/run.lua`.
6. `python3 tools/check.py` → 0 erreur.
7. Donner les étapes en jeu qui confirment la correction.

## 4. Compte rendu
La cause, le correctif (fichiers:lignes), comment vérifier en jeu, et les risques éventuels pour les données existantes.
