---
name: interface
description: Modifie l'interface de l'application Radar ATC sur le laptop (formspecs) — onglets Radar, Aéroports, ATC et Admin, leurs vues, boutons, champs, listes paginées, couleurs. Couvre le dessin (ui_tabs.lua) ET le traitement des clics (fields.lua), qui doivent toujours évoluer ensemble. À utiliser pour toute demande qui touche l'écran du laptop — « ajoute un bouton », « nouvel onglet », « le texte déborde », « ce bouton ne fait rien », « affiche X sur le radar », pagination, formulaire — même si le mot formspec n'est pas prononcé.
---

# Modifier l'interface (formspec du laptop)

> **Contexte** — radar_atc est un mod pour **Luanti**, conçu pour le jeu **Minetest Game**. Il ajoute l'application « Radar ATC » à l'ordinateur du mod **laptop**, et son radar suit les avions des mods construits sur **airutils** d'apercy (Super Cub, PA-28, Ju 52, trike…). Ces mods doivent être installés et activés dans le monde : `depends = laptop, airutils, default` dans mod.conf (`default` est fourni par Minetest Game). Architecture et conventions : CLAUDE.md.

## Où est quoi
- `ui_tabs.lua` : dessin. `build_fs()` trace la barre d'onglets puis appelle `tab_radar`, `tab_myairport`, `tab_atc` ou `tab_admin` selon `data.tab`. Chaque fonction remplit une table `fs` et renvoie `table.concat(fs)`.
- `fields.lua` : `do_fields()` reçoit les clics, avec un bloc par onglet : `if data.tab == "radar"`, `"myap"`, `"admin"`, `"atc"`. Un traitement met à jour `data`, sauvegarde si besoin, puis `return true` (= redessiner).
- Sous-vues : Admin → `data.av` (`list`, `new_ap`, `rw_list`, `new_rw`, `strips`, `new_strip`, `pw_manage`) ; ATC → `data.atc_sub` (`requests`, `radio`, `notam`, `log`) ; Aéroports → `data.myap_view`.
- Le laptop fournit le cadre (taille, fond, barre de lancement) : ne pas émettre `size[]`, `formspec_version[]` ni `bgcolor[]`.

## Grille (constantes de config.lua — pas de coordonnées en dehors de ces bornes)
| Zone | Valeurs |
|---|---|
| Barre du laptop | y ≤ 0.30 : ne rien y dessiner |
| Onglets | y = `CFG.TAB_Y` (0.32), hauteur `CFG.TAB_H` (0.55) |
| Contenu | de `CFG.CY` (0.97) à `CFG.Y_MAX` (9.62) ; x de 0 à `CFG.X_MAX` (14.80) |
| Radar | x `CFG.RX`, y `CFG.RY`, largeur `CFG.RW` (6.80), hauteur `CFG.RH` (7.60) |
| Panneau droit de l'onglet Radar | x `CFG.PX`, largeur `CFG.PW` |

Méthode : un curseur `local py = CFG.CY`, augmenté après chaque ligne. Avant d'ajouter une ligne, vérifier `py + hauteur <= CFG.Y_MAX` ; sinon paginer.

## Écrire un élément
```lua
table.insert(fs, string.format("button[%.2f,%.2f;2.7,0.44;atc_ref_%d;%s]",
    0.10, py, ri, fe(clr("#FF4444", S("✕ Refuse")))))
```
- **Tout texte variable passe par `fe()`** (formspec_escape) : noms d'aéroports et de pistes, NOTAM, messages radio, noms saisis, coordonnées tapées. `clr()` (= `minetest.colorize`) colore mais n'échappe rien. Un `]` ou un `;` non échappé casse le formulaire, et un pilote pourrait injecter des éléments par un message radio.
- Libellés en `S("...")`, puis skill `/traductions`.
- Couleurs du thème : fond radar `#001800`, avion en mouvement `#00FF44`, sélection `#FFAA00`, demande ATC `#FF3333`, aéroports `#88CCFF`, pistes indépendantes `#CC8833` / `#FFAA44`, erreurs `#FF4444`, admin et mots de passe `#CC88FF`.

## Nommer les champs
- snake_case préfixé par la zone : `tab_*`, `pl_*` (liste radar), `ctrl_*` (contrôle à distance), `ap_*`, `rw_*`, `strip_*`, `av_*` (navigation admin), `atc_*`, `radio_*`, `notam_*`.
- Index dynamiques : `ap_del_<i>`, `atc_rw_<demande>_<piste>_<seuil>`.
- Un préfixe dynamique ne doit pas être le début d'un autre nom traité à part (`rw_` lu en boucle et `rw_prev` se confondent) : choisir des préfixes distincts.

## Traiter le clic (fields.lua) — pour CHAQUE élément ajouté
1. Dans le bloc `if data.tab == "<onglet>"` correspondant, avant tout `return` qui l'empêcherait d'être atteint.
2. **Droits vérifiés côté serveur** : un client modifié peut envoyer n'importe quel nom de champ, même si le bouton n'est pas affiché. Actions admin : `data._admin_ok[data._player_name]` ; mots de passe : `minetest.check_player_privs(nom, {radar_atc=true})`.
3. Les champs texte arrivent avec n'importe quel clic du formulaire : les lire au moment du bouton de validation et les recopier dans `data.n_*`, pour qu'un redessin ne vide pas la saisie (modèle : `ap_create`, `rw_create`).
4. Boucles d'index : borner sur la taille réelle de la liste plutôt que sur une constante (`for i = 1, 60`).
5. Persister (`save_airports()`, `save_strips()`, `save_shared_atc(id, state)`, `save_notam(...)`), puis `return true`.

Pagination : page dans `data.<x>_page`, boutons `<x>_prev` / `<x>_next` traités dans fields.lua, page bornée au moment du dessin (modèle : `ap_prev` / `ap_next`).

Menu déroulant : par défaut, `fields.<nom>` contient le libellé de l'entrée choisie, **traduit par le client** : il ne correspond pas au texte de `S()` côté serveur. Dès qu'une entrée est traduite, dessiner avec `mkdd(..., true)` (`index_event`) : `fields.<nom>` contient alors le numéro de l'entrée. Mémoriser au dessin la liste numéro → identifiant dans `data`, comme `data._myap_choices` pour `myap_sel`. `mkdd()` échappe les entrées. Tester tout menu déroulant en jeu avec une autre langue que l'anglais.

## État
`data` (= `mtos.bdev:get_app_storage('ram', 'radar')`) appartient au laptop, pas au joueur : plusieurs joueurs peuvent le partager, et `data._player_name` est le dernier qui a cliqué. Un état propre à un joueur s'indexe par son nom (`data._admin_ok[nom]`). Après un redémarrage, `data` peut être vide : toujours prévoir une valeur par défaut.

## Ne pas faire laguer
L'écran est stocké dans la métadonnée du laptop. Toutes les 3 s, laptop le reconstruit, et Luanti le renvoie **entier** à chaque joueur à moins de ~100 blocs dès qu'il diffère du précédent.
- Rien ne doit changer tout seul d'un tick à l'autre : pas d'horloge, d'âge en secondes ni de compteur animé (âges en minutes).
- Étiquette d'une seule couleur : `ce(couleur, texte)` (ui_tabs.lua) plutôt que `clr()`, plus court. Ligne pointillée : `dotted()`, qui proportionne le nombre de points à la longueur.
- Un onglet qui n'a pas besoin d'être redessiné par le timer s'ajoute à la condition `idle` d'`on_timer` (init.lua) ; l'onglet Admin ne l'est jamais (la saisie serait perturbée).
- Les avions viennent de `data.planes` (rafraîchi par `formspec_func`) et les traînées de `radar_atc.tracker.trails` : ne jamais parcourir le monde pendant le dessin.

## Vérifier
1. `python3 tools/check.py fields i18n globals syntax tests` → 0 erreur (`tests` inclut les seuils de performance de `tools/bench.lua --check`). Pour un changement de l'onglet Radar, comparer `luajit tools/bench.lua` avant et après.
2. À indiquer à l'utilisateur pour le test en jeu : l'onglet s'affiche sans débordement ; le bouton agit ; une saisie survit à un redessin ; un texte contenant `[ ] ; ,` ne casse pas la vue ; un second joueur sur le même laptop ne voit pas l'état privé du premier.
