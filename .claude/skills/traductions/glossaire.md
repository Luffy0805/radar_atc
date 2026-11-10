# Glossaire — traductions de radar_atc

Termes déjà employés dans `locale/*.tr` : les réutiliser pour rester cohérent. Pour un terme absent de ce tableau, chercher d'abord l'existant : `grep -i "terme" locale/radar_atc.<code>.tr`.

## Règles
- **pt = portugais européen** : aterragem, descolagem, registo, palavra-passe, contacte, controlo.
- **ru** : УВД pour ATC, полоса pour piste, вышка pour la tour, НОТАМ.
- Ne pas traduire : NOTAM (sauf ru : НОТАМ), ATC (sauf ru : УВД), ASR, les codes OACI, les commandes (`/atc`, `landing`, `takeoff`, `flyover`, `approach`, `msg`, `nearest`, `navigate`, `IR`, `RIR`), les unités (m, ft, kt, km/h, FL).
- N'ajouter ni ne retirer aucun symbole par rapport à la source. Héritage à ne pas reproduire : `Authorized` et `On hold` ont été traduits avec ✔ et ⏸ alors que la source n'en contient pas.
- Libellés alignés (`Model   : @1`) : garder un alignement lisible dans la langue cible, pas forcément le même nombre d'espaces.
- Boutons : courts (la place est limitée sur le laptop). Messages radio : style phraséologie, impératif et concis.

## Termes
| Anglais | fr | de | es | it | pt | ru |
|---|---|---|---|---|---|---|
| Airports | Aéroports | Flughäfen | Aeropuertos | Aeroporti | Aeroportos | Аэропорты |
| Runway(s) | Piste(s) | Piste(n) | Pista(s) | Pista / Piste | Pista(s) | Полоса / Полосы |
| Independent runways (no ATC) | Pistes indépendantes (sans ATC) | Unabhängige Pisten (kein ATC) | Pistas independientes (sin ATC) | Piste indipendenti (nessun ATC) | Pistas independentes (sem ATC) | Независимые полосы (без УВД) |
| tower | tour | Tower | torre | torre | torre | вышка |
| Range (radar) | Portée | Reichweite | Alcance | Portata | Alcance | Дальность |
| Range (carburant) | Autonomie | Reichweite | Autonomía | Autonomia | Autonomia | Дальность |
| Fuel | Carburant | Kraftstoff | Combustible | Carburante | Combustível | Топливо |
| Owner | Propriétaire | Eigentümer | Propietario | Proprietario | Proprietário | Владелец |
| Pilot | Pilote | Pilot | Piloto | Pilota | Piloto | Пилот |
| Heading | Cap | Kurs | Rumbo | Rotta | Rumo | Курс |
| Requests | Demandes | Anfragen | Solicitudes | Richieste | Pedidos | Запросы |
| Radio | Radio | Funk | Radio | Radio | Rádio | Радио |
| Log | Journal | Protokoll | Registro | Registro | Registo | Журнал |
| landing request | demande d'atterrissage | Landeanfrage | solicitud de aterrizaje | richiesta di atterraggio | pedido de aterragem | запрос на посадку |
| takeoff request | demande de décollage | Startanfrage | solicitud de despegue | richiesta di decollo | pedido de descolagem | запрос на взлёт |
| approach request | demande d'approche | Anfluganfrage | solicitud de aproximación | richiesta di avvicinamento | pedido de aproximação | запрос на заход |
| flyover at @1 | survol à @1 | Überflug auf @1 | sobrevuelo a @1 | sorvolo a @1 | sobrevoo a @1 | пролёт на @1 |
| Landing authorized — Runway @1 | Atterrissage autorisé — Piste @1 | Landung genehmigt — Piste @1 | Aterrizaje autorizado — Pista @1 | Atterraggio autorizzato — Pista @1 | Aterragem autorizada — Pista @1 | Посадка разрешена — Полоса @1 |
| Authorized | Autorisé | Genehmigt | Autorizado | Autorizzato | Autorizado | Разрешено |
| Refused | Refusé | Abgelehnt | Rechazado | Rifiutato | Recusado | Отказано |
| On hold | En attente | Warteschleife | En espera | In attesa | Em espera | Ожидание |
| Contact tower. | Contactez la tour. | Tower kontaktieren. | Contacte con la torre. | Contattare la torre. | Contacte a torre. | Свяжитесь с вышкой. |
| Hold your position. | Maintenez votre position. | Position halten. | Mantenga su posición. | Mantenere la posizione. | Mantenha a sua posição. | Сохраняйте позицию. |
| Remote (contrôle à distance) | Distant | Fernzugriff | Remoto | Remoto | Remoto | Удалённо |
| Transponder | Transpondeur | Transponder | Transpondedor | Transponder | Transponder | Транспондер |
| ASR Radar Antenna | Antenne radar ASR | ASR-Radarantenne | Antena radar ASR | Antenna radar ASR | Antena radar ASR | Радарная антенна ASR |
| ATC Link Antenna | Antenne de liaison ATC | ATC-Verbindungsantenne | Antena de enlace ATC | Antenna di collegamento ATC | Antena de ligação ATC | Антенна связи УВД |
| Outside airport | Hors zone aéroportuaire | Außerhalb des Flughafens | Fuera del aeropuerto | Fuori dall'aeroporto | Fora do aeroporto | За пределами аэропорта |
| Wrong password. | Mot de passe incorrect. | Falsches Passwort. | Contraseña incorrecta. | Password errata. | Palavra-passe incorreta. | Неверный пароль. |
| No active NOTAM. | Aucun NOTAM en vigueur. | Kein aktives NOTAM. | Ningún NOTAM activo. | Nessun NOTAM attivo. | Nenhum NOTAM ativo. | Нет активных НОТАМ. |
