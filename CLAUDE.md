# radar_atc — guide de maintenance

## Contexte
**radar_atc** est un mod pour **Luanti** (anciennement Minetest), conçu pour le jeu **Minetest Game**. Il ajoute l'application « Radar ATC » à l'ordinateur du mod **laptop** : radar aérien en temps réel, gestion d'aéroports et de pistes, demandes ATC des pilotes, radio, NOTAM. C'est un complément des mods **airutils** d'apercy : le radar suit les avions des mods construits sur airutils (Super Cub, PA-28, Ju 52, trike…) en lisant leurs champs internes.

- Dépendances obligatoires, installées et activées dans le monde : `depends = laptop, airutils, default` (mod.conf). `default` vient de Minetest Game (matériaux des recettes, sons). airutils est une bibliothèque : les avions eux-mêmes viennent d'autres mods qui en dépendent.
- `min_minetest_version = 5.4` : pas d'API Luanti plus récente sans relever ce minimum.
- Lua 5.1 / LuaJIT : pas de `goto`, `//`, opérateurs bit à bit, ni `table.unpack` (utiliser `unpack`).
- Le dossier du dépôt **est** le dossier du mod (`mods/radar_atc/`). Luanti ignore `tools/`, `.claude/` et `.github/`.

## Commandes
| Commande | Rôle |
|---|---|
| `python3 tools/check.py` | toutes les vérifications ; code de sortie 1 s'il y a des erreurs |
| `python3 tools/check.py syntax globals fields i18n meta tests` | une ou plusieurs vérifications ciblées |
| `python3 tools/check.py i18n --missing` | chaînes à traduire, au format .tr |
| `luajit tools/tests/run.lua` | tests unitaires (utils.lua, suivi des avions, migration, réglages, transpondeur) |
| `luajit tools/bench.lua` | banc d'essai des performances : laptops, avions, entités simulés ; entités examinées, octets envoyés aux joueurs, taille de l'écran. `--check` = seuils (lancé par `check.py tests`) ; un dossier en argument mesure une autre version du mod |

Prérequis : `python3` et `luajit` (`brew install luajit` / `apt install luajit`). Aucun test ne lance le moteur : un changement de comportement se vérifie aussi en jeu (voir « Tester en jeu »).

## Architecture
Pas de système de modules : chaque fichier définit des **fonctions globales**, et `init.lua` les charge dans cet ordre. Une globale utilisée au chargement doit venir d'un fichier chargé avant.

| Ordre | Fichier | Contenu |
|---|---|---|
| 1 | config.lua | table `CFG` : réglages `radar_atc.*` et constantes de mise en page |
| — | init.lua | privilège `radar_atc`, espace de noms `radar_atc`, table `active_nodes`, enregistrement de l'application laptop (politique de redessin) |
| 2 | storage.lua | persistance mod_storage (aéroports, pistes, ATC, NOTAM, journal, mots de passe) |
| 3 | utils.lua | conversions, géométrie (caps, noms de piste, projection radar), helpers formspec `fe`, `clr`, `mkdd` |
| 4 | transponder.lua | nœuds transpondeur ASR et antenne de liaison, entités 3D, objets et recettes |
| 5 | scan.lua | suivi global des avions (`radar_atc.tracker` : un relevé partagé, traînées) ; `scan()` = avions dans le rayon d'un radar |
| 6 | ui_tabs.lua | formspecs : `build_fs`, `tab_radar`, `tab_myairport`, `tab_atc`, `tab_admin` |
| 7 | fields.lua | `do_fields` : tous les clics et saisies des formspecs |
| 8 | commands.lua | commandes chat `/atc` et `/notam` (côté pilote) |

Flux : `laptop.register_app` (init.lua) → `formspec_func` → `build_fs()` ; clic → `receive_fields_func` → `do_fields()` (renvoie `true` = redessiner). Toutes les `CFG.timer_interval` s, laptop appelle `on_timer` **puis** `formspec_func`, et écrit le résultat dans la métadonnée du nœud ; Luanti ne l'envoie aux joueurs proches que si elle a changé. `on_timer` décide s'il faut redessiner : personne à moins de 16 blocs, onglet Admin, ou onglet Aéroports sans événement ATC → `formspec_func` renvoie `false` (rien construit, rien envoyé). Sinon `formspec_func` rafraîchit `data.planes` (onglet Radar) puis appelle `build_fs()`.

## État
**RAM du laptop** : `mtos.bdev:get_app_storage('ram', 'radar')`, nommée `data` dans le code. Elle appartient au laptop et est partagée par tous les joueurs qui l'utilisent ; `data._player_name` est le dernier joueur qui a cliqué. Un état propre à un joueur s'indexe par son nom (ex. `data._admin_ok[nom]`). Elle peut être vide après un redémarrage. laptop la sérialise dans la métadonnée toutes les 5 à 15 s : n'y ranger que de petites données (les traînées des avions sont dans `radar_atc.tracker`, pas dans `data`).

**Données persistantes** (mod_storage, `minetest.serialize`) :

| Clé | Contenu |
|---|---|
| `airports_v5` | liste `{id, name, pos, has_transponder, runways = {{name, width, p1, p2, approaches = {[seuil] = "X,Z"}}}}` |
| `indep_strips_v1` | pistes indépendantes `{name, p1, p2, width, note}` |
| `atc_<ID>` | `{requests = {{player, airport, req_type, alt, time, status, model, owner}}, conversations = {{pilot, messages = {{from, text, time}}}}}` |
| `notam_<ID>` | liste de chaînes |
| `atclog_<ID>` | `{time, player, model, req_type, decision, runway}`, le plus récent en premier |
| `passwords_v1` | `{admin, remote}`, prioritaires sur les valeurs de config.lua |
| `rwy_names_fixed_v1` | entier, 1 = migration des noms de piste déjà faite |

Changer la forme d'une de ces tables impose une migration (skill `/stockage`) : sur un serveur, ce sont les données des joueurs.

## Couplage avec airutils (champs internes, sans API garantie)
- Lus dans scan.lua et commands.lua : `_vehicle_name`, `_max_plane_hp`, `_climb_rate`, `driver_name`, `co_pilot`, `_command_is_given`, `owner`, `_yaw`, `hp_max`, `_energy`, `_max_fuel`, `_power_lever`.
- Un avion = entité avec `_vehicle_name` et (`_max_plane_hp` ou `_climb_rate ~= nil`). Les avions sans pilote sont masqués. Le joueur est attaché à un siège, lui-même attaché à l'avion (`in_aircraft` vérifie deux niveaux). Cette condition existe en double dans scan.lua et commands.lua.
- Autonomie : table `AUTONOMY_DIVISORS` (scan.lua) indexée par `_vehicle_name` ; le suivi en déduit `autonomy_known` pour chaque avion (plus de liste dupliquée dans ui_tabs.lua). Ajouter un avion : skill `/ajouter-avion`.
- Le suivi parcourt `minetest.luaentities` (table documentée des entités actives) au plus une fois par seconde, et seulement quand un radar le demande.
- Après une mise à jour d'airutils, d'un avion ou de laptop : agent `compat-airutils`.

API laptop utilisée : `laptop.register_app`, `laptop.os_get(pos)`, `mtos.bdev:get_app_storage('ram', 'radar')`, `mtos:save()`, `mtos.pos`, `app:get_timer()`.

## Conventions
**Formspec** (skill `/interface`) :
- Coordonnées via `CFG` uniquement : onglets à `CFG.TAB_Y`, contenu de `CFG.CY` (0.97) à `CFG.Y_MAX` (9.62), largeur ≤ `CFG.X_MAX` (14.80). Au-dessus de y = 0.30 se trouve la barre du laptop : n'y rien dessiner.
- Tout texte venant d'un joueur ou d'un admin (noms, NOTAM, radio…) passe par `fe()`. `clr()` colore mais n'échappe pas.
- Chaque `button`, `field` ou `dropdown` émis dans ui_tabs.lua doit être traité dans fields.lua (`check.py fields` le vérifie).
- Les droits se vérifient dans fields.lua, pas seulement en masquant un bouton : un client modifié peut envoyer n'importe quel champ.

**Traductions** (skill `/traductions`) :
- `local S = minetest.get_translator("radar_atc")` en tête de fichier ; chaînes source en anglais.
- 6 langues dans `locale/radar_atc.<code>.tr` : fr, de, es, it, pt (européen), ru. Un `.tr` hors de `locale/` n'est pas chargé par Luanti.
- Dans un .tr : saut de ligne = `@n` (jamais `\n`), `=` littéral = `@=`. Dans `S()`, les `@1`…`@9` vont dans l'ordre et en nombre égal aux arguments, sinon erreur Lua à l'exécution.

**Globales** : toute nouvelle globale doit être voulue et déclarée dans `tools/known_globals.txt`, sinon `check.py globals` échoue. Préférer `local`. Des noms courts comme `scan`, `fe`, `clr` ou `pk` peuvent entrer en conflit avec d'autres mods : préfixer les nouveaux.

**Réglages** : en ajouter un = (1) dans `CFG` (config.lua) : `num("cle", défaut, min, max)` pour un nombre (valeur invalide → défaut, puis bornée), `bool("cle", défaut)` ou `setting("cle", "défaut")` pour un texte ; (2) une ligne dans `settingtypes.txt` (seul nom de fichier que Luanti lit, affiché dans Paramètres → Tous les paramètres → Mods) avec **le même défaut et les mêmes bornes** ; (3) le bloc « Configuration » de README.md **et** de README-FR.txt. `check.py meta` compare config.lua et settingtypes.txt et signale les réglages non documentés.

## Pièges connus
- **Uploads par le site GitHub** : ils ont déjà écrasé `mod.conf` (version revenue de 1.1.0 à 1.0.5, deux fois) et déposé des `.tr` à la racine. Après chaque upload, relancer `python3 tools/check.py` ; `check.py meta` détecte une version qui recule.
- `find_nodes_in_area` est limité à 4 096 000 nœuds (= 160³) : un cube de rayon r en compte (2r+1)³. C'est pourquoi `transponder_link_r` est plafonné à 79 dans config.lua ; tout nouveau rayon de recherche doit l'être aussi.
- **Rien dans un formspec ne doit changer tout seul d'un tick à l'autre** (horloge, âge en secondes, compteur…) : chaque changement renvoie tout l'écran (plusieurs Ko) à chaque joueur à moins de ~100 blocs, toutes les 3 s et pour chaque laptop. Jusqu'en 1.1.1, l'horloge « UPD hh:mm:ss » faisait renvoyer l'écran à chaque tick même sans aucun avion. Âges en minutes, pas d'horloge. `tools/bench.lua --check` le vérifie.
- Pour réduire la taille d'un écran : `ce(couleur, texte)` (ui_tabs.lua) pour une étiquette d'une seule couleur (sans le code de retour au blanc de `clr()`), pointillés proportionnés à la longueur (`dotted()`).
- `scan()` ne parcourt plus le monde : il filtre le relevé partagé du suivi. Ne pas rappeler `get_objects_inside_radius` à grand rayon dans un chemin de timer ou de dessin.
- **Lag serveur jusqu'au redémarrage (corrigé en 1.1.1)** : `transponder_ok()` lançait `find_nodes_in_area` sur 3,4 millions de blocs à chaque rafraîchissement de l'onglet Radar, et chargeait depuis le disque environ 1 000 mapblocks en contrôle à distance. Ne jamais appeler `find_nodes_in_area` dans un chemin de dessin ou de timer : passer par `node_in_cube()` (transponder.lua), qui garde le résultat en cache 60 s et ne fouille pas une zone non chargée. Le test « transponder_ok » de `tools/tests/run.lua` compte les fouilles.
- `minetest.get_node` renvoie `ignore` en zone non chargée ; `get_luaentity()` et `get_player_by_name()` peuvent renvoyer nil.
- Convention de cap du mod : +X = est, +Z = nord, cap = `atan2(dx, dz)`, partout (`bearing()`, `/atc navigate`, radar). Jusqu'à 1.1.0, `bearing()` inversait nord et sud : les pistes en diagonale déjà enregistrées sont renommées une fois au démarrage (storage.lua, drapeau `rwy_names_fixed_v1`).

## Tester en jeu
Prérequis : Luanti avec le jeu Minetest Game, et les mods laptop, airutils et au moins un avion (ex. Super Cub) activés dans le monde avec radar_atc. Installation de développement : lien symbolique du dépôt dans le dossier `mods/` de Luanti (`ln -s "$PWD" <dossier_luanti>/mods/radar_atc`). Erreurs : `debug.txt` du dossier utilisateur de Luanti.

Scénario minimal : poser un laptop et ouvrir Radar ATC ; dans Admin (mot de passe par défaut `admin`), créer un aéroport puis une piste ; décoller avec un avion et vérifier son point sur le radar ; envoyer `/atc <ID> landing` en vol ; autoriser la demande depuis l'onglet ATC et vérifier le message reçu par le pilote.

## Outillage Claude Code
- Skills (`.claude/skills/`) : `/verifier`, `/interface`, `/commande-chat`, `/ajouter-avion`, `/traductions`, `/stockage`, `/diagnostiquer`, `/publier`.
- Agents (`.claude/agents/`) : `relecteur-luanti` (relecture avant commit), `compat-airutils` (compatibilité des dépendances), `traducteur` (traductions en lot).
- Hook (`.claude/settings.json`) : après chaque modification d'un `.lua`, compilation LuaJIT automatique (`tools/hooks/lua_syntax.sh`).
- Intégration continue (`.github/workflows/verifier.yml`) : `python3 tools/check.py` à chaque push et pull request, seuils de performance compris.
- Banc d'essai (`tools/bench.lua`) : mesurer avant/après toute modification du radar, du timer ou des formspecs (`git archive <commit> | tar -x -C <dossier>` puis `luajit tools/bench.lua <dossier>/` pour l'ancienne version).
