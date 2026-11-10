---
name: stockage
description: Modifie en sécurité les données persistantes de radar_atc (mod_storage : aéroports, pistes, pistes indépendantes, demandes et radio ATC, NOTAM, journal, mots de passe) — ajout de champ, changement de structure, migration de format, nettoyage, limites de taille. À utiliser AVANT toute modification de storage.lua ou de la forme des tables sauvegardées (aéroport, piste, demande, conversation…), quand un serveur perd ou corrompt des aéroports, ou quand l'utilisateur parle de sauvegarde, de migration, de données ou de mod_storage.
---

# Données persistantes et migrations

> **Contexte** — radar_atc est un mod pour **Luanti**, conçu pour le jeu **Minetest Game**. Il ajoute l'application « Radar ATC » à l'ordinateur du mod **laptop**, et son radar suit les avions des mods construits sur **airutils** d'apercy (Super Cub, PA-28, Ju 52, trike…). Ces mods doivent être installés et activés dans le monde : `depends = laptop, airutils, default` dans mod.conf (`default` est fourni par Minetest Game). Architecture et conventions : CLAUDE.md.

Les schémas actuels sont décrits dans CLAUDE.md (section « État »). Sur un serveur, ces données sont le travail des joueurs (aéroports, pistes…) : une version qui ne relit plus l'ancien format les fait disparaître pour tout le monde.

## Choisir le type de changement
1. **Ajout d'un champ optionnel** (ex. `rw.frequency`) : pas de migration, à condition que chaque lecture traite l'absence (`rw.frequency or valeur_par_defaut`). C'est la solution à préférer.
2. **Changement incompatible** (renommer, changer de type, restructurer) : nouvelle clé versionnée et migration au chargement. Ne jamais réécrire l'ancienne clé : elle permet de revenir à la version précédente.

## Modèle de migration (storage.lua)
```lua
local function migrate_airports_v5_to_v6()
    local raw = ST:get_string("airports_v5")
    local list = (raw ~= "" and minetest.deserialize(raw)) or {}
    for _, a in ipairs(list) do
        -- convertir chaque aéroport vers le nouveau format
    end
    ST:set_string("airports_v6", minetest.serialize(list))
    minetest.log("action", "[radar_atc] migration airports_v5 -> v6 : " .. #list .. " aéroport(s)")
    return list
end

function get_airports()
    if not _ap_cache then
        local r = ST:get_string("airports_v6")
        _ap_cache = (r ~= "" and minetest.deserialize(r)) or migrate_airports_v5_to_v6()
    end
    return _ap_cache
end
-- … et save_airports() écrit désormais "airports_v6".
```

## Règles du stockage actuel
- `get_airports()` et `get_strips()` renvoient une table **en cache**, que les appelants modifient sur place avant `save_airports()` / `save_strips()`. Une migration doit remplir ce cache.
- `minetest.serialize` n'accepte ni fonctions, ni userdata (ObjectRef de joueur ou d'entité), ni références circulaires. `minetest.deserialize` renvoie nil sur une donnée corrompue : garder le repli `or {}`.
- **Toute liste stockée doit être bornée.** Aujourd'hui, les messages radio (`conversations[i].messages`) et les demandes non traitées de `atc_<ID>` grossissent sans limite : ne pas aggraver, et proposer une limite si l'on touche à ce code.
- Supprimer un aéroport (`ap_del_<i>` dans fields.lua) laisse `atc_<ID>`, `notam_<ID>` et `atclog_<ID>` orphelins ; un aéroport recréé avec le même identifiant en hérite. En tenir compte pour tout changement d'identifiant ou de suppression.
- Les mots de passe (`passwords_v1`) sont stockés en clair : ne jamais les écrire dans le journal ni dans le chat.

## Tester une migration
1. **Sauvegarder le monde de test** (copie du dossier `worlds/<monde>`).
2. Avec l'ancienne version : créer aéroports, pistes, NOTAM, demandes.
3. Passer à la nouvelle version : tout doit être présent, et `debug.txt` contient la ligne `[radar_atc] migration…`.
4. Redémarrer une seconde fois : pas de nouvelle migration, données intactes.
5. Emplacement des données : `worlds/<monde>/mod_storage.sqlite` (versions récentes de Luanti) ou `worlds/<monde>/mod_storage/radar_atc` (anciennes versions, fichier texte).

Ensuite : `python3 tools/check.py`, et signaler la migration dans les notes de version (skill `/publier`).
