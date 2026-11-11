---
name: publier
description: Prépare et publie une nouvelle version du mod radar_atc — contrôles, numéro de version dans mod.conf, notes de version FR/EN, README, commit, tag git, release ContentDB. Lancé uniquement à la demande (/publier).
argument-hint: "[numéro de version, ex. 1.2.0]"
disable-model-invocation: true
---

# Publier une version

> **Contexte** — radar_atc est un mod pour **Luanti**, conçu pour le jeu **Minetest Game**. Il ajoute l'application « Radar ATC » à l'ordinateur du mod **laptop**, et son radar suit les avions des mods construits sur **airutils** d'apercy (Super Cub, PA-28, Ju 52, trike…). Ces mods doivent être installés et activés dans le monde : `depends = laptop, airutils, default` dans mod.conf (`default` est fourni par Minetest Game). Architecture et conventions : CLAUDE.md.

Version demandée : $ARGUMENTS (si rien n'est indiqué, la proposer à l'étape 3).

Chaque action visible de l'extérieur (commit, tag, push, release) attend l'accord explicite de l'utilisateur.

1. **État du dépôt** : `git status` propre ; `git pull` pour récupérer les éventuels uploads faits depuis le site GitHub, puis relire ce qu'ils ont changé (`git log -p -3`). Ces uploads ont déjà écrasé `mod.conf` et déposé des fichiers au mauvais endroit.
2. **Contrôles** : `python3 tools/check.py` → 0 erreur ; relire les avertissements. Pour relire le code modifié depuis la dernière version : agent `relecteur-luanti`. Avant une version majeure : agent `compat-airutils`.
3. **Numéro** (versionnage sémantique) : correctif → x.y.**z** ; fonctionnalité → x.**y**.0 ; migration de données ou rupture → **x**.0.0. Il doit dépasser la plus haute version de l'historique (`check.py meta` le vérifie). Le faire valider par l'utilisateur.
4. **mod.conf** : `version = X.Y.Z`.
5. **Changements** : `git log --oneline <dernier tag>..HEAD` (sans tag : depuis le dernier changement de version dans mod.conf). Rédiger des notes de version courtes, en français et en anglais. S'il n'existe pas de `CHANGELOG.md`, proposer de le créer (une seule fois), puis le tenir à jour.
6. **Documentation** : README.md et README-FR.txt décrivent les nouvelles commandes, les nouveaux réglages et objets.
7. **Test en jeu** : demander à l'utilisateur de confirmer le scénario minimal (section « Tester en jeu » de CLAUDE.md) sur la version finale.
8. **Commit** `Version X.Y.Z`, puis **tag** `vX.Y.Z` et **push** (`git push && git push --tags`), avec accord.
9. **ContentDB** (content.luanti.org) : si le paquet y est publié, créer la release à partir du tag (page du paquet, ou webhook GitHub s'il est configuré). Claude n'a pas accès au compte : donner les étapes.
10. Rappel : après tout futur upload par le site GitHub, relancer `python3 tools/check.py`.

Livrable final : les notes de version FR et EN, prêtes à coller.
