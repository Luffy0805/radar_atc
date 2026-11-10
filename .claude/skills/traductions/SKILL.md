---
name: traductions
description: Crée, corrige et synchronise les traductions de radar_atc (locale/radar_atc.<langue>.tr pour fr, de, es, it, pt, ru) — chaînes manquantes, clés obsolètes, échappements invalides (\n au lieu de @n), marqueurs @1, ajout d'une langue. À utiliser après tout ajout ou changement de texte visible (interface, chat, descriptions d'objets), quand check.py signale un problème i18n, ou quand l'utilisateur parle de traduction, de langue, de français, d'allemand… ou d'un texte resté en anglais en jeu.
---

# Traductions

> **Contexte** — radar_atc est un mod pour **Luanti**, conçu pour le jeu **Minetest Game**. Il ajoute l'application « Radar ATC » à l'ordinateur du mod **laptop**, et son radar suit les avions des mods construits sur **airutils** d'apercy (Super Cub, PA-28, Ju 52, trike…). Ces mods doivent être installés et activés dans le monde : `depends = laptop, airutils, default` dans mod.conf (`default` est fourni par Minetest Game). Architecture et conventions : CLAUDE.md.

## Fichiers
- `locale/radar_atc.<code>.tr` pour fr, de, es, it, pt (portugais européen) et ru. Luanti ne charge que ces fichiers.
- `locale/template.txt` : mode d'emploi pour les traducteurs (ce n'est pas une liste de clés).
- Des `.tr` à la racine du dépôt sont des copies obsolètes, ignorées par Luanti : proposer de les supprimer.
- Côté code : `local S = minetest.get_translator("radar_atc")` ; la chaîne source anglaise sert de clé.

## Format .tr (Luanti)
- Première ligne : `# textdomain: radar_atc`. Les lignes `#` sont des commentaires ; les sections `### Radar tab ###` servent à s'y retrouver.
- Une entrée par ligne : `source anglaise exacte=traduction`. La source doit être identique, au caractère près, à la chaîne de `S()`, espaces de tête et d'alignement compris (`  Use /atc navigate IR <n> for full details.`, `Model   : @1`).
- Saut de ligne : **`@n`**. Le `\n` du code Lua s'écrit `@n` dans le .tr ; un `\n` littéral rend l'entrée inutilisable.
- `=` littéral : `@=` ; `@` littéral : `@@`.
- `@1`…`@9` : arguments. La traduction contient le même ensemble ; l'ordre peut changer.
- Aucun échappement à la manière du Lua (`\'`, `\"`) : écrire le caractère tel quel, en UTF-8.

## Procédure
1. `python3 tools/check.py i18n` : erreurs (échappements, marqueurs, fichier absent) et avertissements (chaînes non traduites, clés obsolètes, doublons).
2. Corriger d'abord les erreurs de format, mécaniquement.
3. Chaînes manquantes : `python3 tools/check.py i18n --missing` produit des lignes `clé=` prêtes à compléter. Au-delà de quelques chaînes, ou pour plusieurs langues, déléguer à l'agent `traducteur` ; sinon traduire directement en suivant [glossaire.md](glossaire.md).
4. Clé obsolète : si la phrase anglaise a seulement changé, mettre la clé à jour dans les 6 fichiers en adaptant la traduction ; ne supprimer l'entrée que si le texte a disparu du code.
5. Relancer jusqu'à 0 erreur et 0 chaîne manquante.
6. À vérifier en jeu : régler la langue du client (`language = fr`), puis relancer le jeu.

## Modifier un texte source
Changer l'anglais dans `S("...")` change la clé : sans mise à jour des 6 fichiers, la traduction est perdue sans le moindre message. Toujours répercuter le changement.

## Ajouter une langue
Copier la structure de `radar_atc.fr.tr` vers `radar_atc.<code>.tr` (code ISO 639-1), traduire chaque valeur, ajouter le code à `EXPECTED_LANGS` dans `tools/check.py` et citer la langue dans les README.
