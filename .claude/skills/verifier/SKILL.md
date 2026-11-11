---
name: verifier
description: Lance toutes les vérifications automatiques du mod radar_atc (syntaxe LuaJIT, globales, boutons formspec sans traitement, traductions .tr, mod.conf et médias, tests unitaires), puis explique et corrige les problèmes trouvés. À utiliser après toute modification de code ou de traduction, avant un commit, une release ou un push, et dès que l'utilisateur demande « vérifie », « teste », « est-ce que ça marche », « il y a des erreurs ? », même s'il ne cite pas l'outil.
argument-hint: "[syntax|globals|fields|i18n|meta|tests]"
---

# Vérifier le mod

> **Contexte** — radar_atc est un mod pour **Luanti**, conçu pour le jeu **Minetest Game**. Il ajoute l'application « Radar ATC » à l'ordinateur du mod **laptop**, et son radar suit les avions des mods construits sur **airutils** d'apercy (Super Cub, PA-28, Ju 52, trike…). Ces mods doivent être installés et activés dans le monde : `depends = laptop, airutils, default` dans mod.conf (`default` est fourni par Minetest Game). Architecture et conventions : CLAUDE.md.

## 1. Lancer
`python3 tools/check.py $ARGUMENTS` (sans argument : toutes les vérifications ; plusieurs noms possibles).
Code de sortie 1 = au moins une erreur. Les avertissements ne font pas échouer, mais il faut les lire.

Si `luajit` manque : `brew install luajit` (macOS) ou `sudo apt install luajit` (Debian/Ubuntu).

## 2. Interpréter et corriger

| Section | Message | Correction |
|---|---|---|
| syntax | erreur LuaJIT avec fichier:ligne | corriger la syntaxe (Lua 5.1 : pas de `goto`, `//`, `&`, `\|`, `~`) |
| globals | « lue mais jamais définie » | faute de frappe, ou fonction renommée ailleurs |
| globals | « nouvelle globale » | ajouter `local` ; si elle doit vraiment être partagée entre fichiers, la déclarer dans `tools/known_globals.txt` (nom préfixé de préférence) |
| globals | « lue au chargement mais définie plus tard » | ordre des `dofile()` dans init.lua |
| globals | « définie mais jamais utilisée » | code mort : le signaler, ne supprimer qu'avec l'accord de l'utilisateur |
| fields | « émis mais jamais traité » | ajouter le traitement dans fields.lua (skill `/interface`) ou retirer l'élément |
| fields | « lu mais jamais émis » | champ absent du formulaire dans ui_tabs.lua, ou code mort |
| i18n | marqueurs `@N` / nombre d'arguments | aligner la chaîne `S()` et ses arguments : sinon **erreur Lua, donc crash du serveur** |
| i18n | échappement invalide dans un .tr | `\n` → `@n`, `\'` → `'` |
| i18n | chaînes non traduites, clés obsolètes | skill `/traductions` |
| meta | version inférieure à l'historique | remettre dans mod.conf au moins la plus haute version déjà publiée (un upload web a écrasé le fichier) |
| meta | réglage non documenté | README.md **et** README-FR.txt, plus une ligne dans settingtypes.txt |
| meta | défaut/min/max ≠ config.lua | aligner settingtypes.txt sur `num(...)` dans config.lua (ou l'inverse) |
| i18n | template.txt pas à jour | régénérer `locale/template.txt` : `# textdomain: radar_atc` puis une ligne `clé=` par chaîne du code |
| tests | ÉCHEC | régression : corriger le code, pas le test, sauf si le comportement attendu a changé |
| tests | BUG CONNU | bug documenté, pas encore corrigé ; quand il passe, transformer `bug_connu(...)` en `test(...)` |

Corriger d'abord les erreurs, puis relancer jusqu'à « 0 erreur(s) ». Un avertissement préexistant sans rapport avec la tâche en cours se mentionne, il ne se « répare » pas d'office.

## 3. Ce que l'outil ne voit pas
Le moteur n'est pas lancé : rendu réel des formspecs, détection des avions en vol, entités 3D, multijoueur. Pour toute modification de comportement, terminer par une courte liste de vérifications en jeu (section « Tester en jeu » de CLAUDE.md). Pour une relecture approfondie d'un diff, déléguer à l'agent `relecteur-luanti`.

## 4. Compte rendu
Court : erreurs avant/après, ce qui a été corrigé, avertissements notables restants, vérifications en jeu recommandées.
