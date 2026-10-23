# Le contrat du relais

Le relais est le serveur de la console d’Alfred. L’app l’utilise tel quel. Ce document décrit ce que l’app en attend,
et les tests d’`AlfredKit` le vérifient.

## Connexion (parcours web du relais)

1. **Ouverture de la page.** L’app ouvre `GET /connexion?retour=/moi` dans une vue web sans mémoire. Le relais renvoie
   vers la page de connexion de Home Assistant (OAuth « authorization code »).
2. **Échange du code.** Home Assistant renvoie vers une page qu’il sert lui-même : elle échange le code **dans la vue
   web**, puis transmet les jetons au relais (`GET /connexion/fin`, puis `POST /connexion/jeton`). La vue web doit
   donc joindre Home Assistant aussi.
3. **Pose du cookie.** Le relais crée un jeton longue durée **au nom de la personne** (un an ; elle peut le révoquer
   dans son profil Home Assistant), annule le jeton de renouvellement, et pose le cookie `alfred_session` (Secure,
   HttpOnly, SameSite=Lax, un an).
4. **Fin du parcours.** La page de fin renvoie vers `/moi`. L’app reprend alors le cookie, le range dans le
   trousseau, et ferme la vue.
5. **Requêtes suivantes.** Chaque requête porte ce cookie, dans le magasin de cookies d’une session URLSession
   éphémère.

**Déconnexion :** `GET /deconnexion` supprime le jeton dans Home Assistant, efface la session et le cookie, puis
renvoie vers `/` (302). L’app tient la maison pour prévenue sur un statut de 200 à 399 ; sinon, elle le dit.

## Routes HTTP

| Route | Réponse |
|---|---|
| `GET /moi` | `{"connecte": bool, "nom": …, "user_id": …, "titre": "Monsieur" \| "Madame" \| "Mademoiselle" \| ""}` ; `titre` vaut `null` si Home Assistant ne répond pas, `nom` et `user_id` sans session. `connecte: false` avec un cookie : le relais ne connaît plus cette session (`/ws` passerait alors par le compte invité) ; l’app retourne à l’accueil. Un jeton révoqué dans Home Assistant, ou expiré, laisse `connecte: true` et se voit par `fatal` à l’ouverture de `/ws`. |
| `GET /maison/structure` | Version 1, réservée aux personnes connectées (401 sinon). Voir le détail ci-dessous. |
| `GET /maison/console` | Version 1, réservée aux personnes connectées (401 sinon) : la roue, les jauges et la météo de la console ; 503 si le relais ne peut pas la lire. |
| `GET /tts/<jeton>` | La voix d’Alfred, servie **pendant** sa synthèse (MP3 en continu). |
| `GET /static/ack/ack-<n><suffixe>.mp3` | Les clips d’accueil (« Bien, Monsieur »). Le suffixe vaut `""`, `-madame`, `-mademoiselle` ou `-neutre`. |
| `GET /docs` | La **boîte d’arrivée** (23.10) : `{"documents": [...], "a_traiter": n, "hors_panneau": n}`, la plus récente d’abord ; seulement les cartes du panneau (en cours, refusées, rangées depuis moins de 24 h ; `?tous=1` : toutes) ; jamais le texte entier d’un document (le résumé ; pour `alerte`, de courts extraits). Chaque document : `id`, `nom`, `etat` (`pret` \| `en cours` \| `erreur`), `statut` (`lecture` \| `rangement` \| `range` \| `envoye` \| `refuse` \| `banc`), `motif` (le refus, lisible), `refus` (`illisible` : aucun texte lisible \| `lecture` : lecture impossible \| `paperless` : Paperless n’a pas répondu \| `paperless_refus` : Paperless n’a pas pu ranger ce fichier \| `paperless_absent` : pas encore rangé dans Paperless \| `doublon` : déjà dans Paperless ; l’app montre `motif` tel quel et traite un code inconnu comme un simple refus), `reessayer` (booléen), `lien` (la fiche dans Paperless, si la personne a le droit de la voir), `deja_archive` (doublon sans lien), `resume`, `resume_attente` (`pc` : le PC qui résume est éteint \| `file` : son tour vient), `erreur`, `depose_le`, `pour_le`, `paperless` (`{"etat", "document"}` quand le document est envoyé ou rangé, absent sinon), `alerte`, `quitte_le` (quand une carte rangée quitte le panneau), `etiquettes` (les noms posés, ou en attente du rangement) et `etiquettes_non_posees` (celles que Paperless n’a pas posées) — ces deux listes absentes d’un relais plus ancien. `a_traiter` : la pastille de l’en-tête (en cours et refusés). Un relais plus ancien n’envoie ni `statut` ni `a_traiter` : l’app déduit le verdict comme l’ancienne console (prêt et `paperless` : rangé ; prêt : lu ; erreur : refusé ; le reste : en lecture). 401 sans connexion ; 403 pour un compte sans documents (ou si Home Assistant ne répond pas), avec un message lisible que l’app montre. |
| `GET /docs/etiquettes` | 23.10 : les étiquettes proposées au dépôt, `{"etiquettes": [{"id": n, "nom": "…"}], "disponible": bool}`, triées par nom, sans les étiquettes techniques ; `disponible` faux : Paperless ne répond pas (liste vide ; un nom nouveau reste possible, vérifié au rangement). Mêmes droits que `/docs` (401, 403). 404 : un relais plus ancien, l’app cache le champ « Étiquettes ». |
| `POST /docs` | Dépôt multipart d’**un** fichier : `fichier` (PDF, JPEG, PNG, WebP, texte ou e-mail, 20 Mo au plus), `nom` (facultatif), `pour_le` (AAAA-MM-JJ, facultatif), `etiquette` (23.10, facultatif, répété : une valeur par étiquette, le n° décimal d’une étiquette de la liste ou le NOM d’une nouvelle, que le relais crée au rangement, sans doublon ; 10 au plus ; un nom tapé est nettoyé comme le relais le fait : NFC, caractères de contrôle, de format ou séparateurs en espaces, espaces réduits, bords retirés, 40 caractères au plus). 202 et la fiche ; 400 sans fichier, ou avec un texte lisible pour une étiquette refusée (n° inconnu, nom réservé, vide, plus de 10) ; 413 au-delà de 20 Mo ; 415 pour un autre type. Plusieurs fichiers choisis d’un coup (23.10) : une requête par fichier, l’une après l’autre, le même `pour_le` et les mêmes `etiquette` pour tout le lot (les étiquettes choisies sont vidées une fois le lot envoyé) ; un 413, un 415 ou un 400 avec un texte devient une carte « Refusé » de l’app, avec ce texte (rien n’est gardé à la maison). |
| `POST /docs/<id>/reessayer` | 23.10 : nouvel essai d’un document refusé (lecture, Paperless), corps vide : 202 et la fiche ; 404 pour un id inconnu ; 409 s’il n’y a rien à réessayer (un doublon, par exemple). |
| `DELETE /docs/<id>` | Supprime le document de la maison (sa fiche et ses copies) : `{"supprime": id}`, 404 pour un id inconnu. L’exemplaire archivé dans Paperless n’est pas supprimé. Dans l’app (23.10) : « Retirer » sur une carte refusée, « Supprimer » (en deux temps) sur un document que Paperless n’a pas ; jamais sur un document rangé (sa carte quitte le panneau seule, sa fiche reste à la maison). |
| `GET /notifications` | `{"notifications": [{"id", "t", "titre", "message", "lu"}], "non_lues": n}` : celles de la personne connectée seulement (copie de ses téléphones, réponses d’Hermes annoncées) ; une liste vide pour un compte qui n’en reçoit pas. 401 sans connexion. |
| `POST /notifications/lues` · `POST /notifications/effacer` | Tout marquer comme lu · tout effacer. |
| `GET /liens` | `[{"nom", "url", "note"}]` : les autres systèmes, selon le compte (vide pour un invité ; 503 si HA ne répond pas). L’app n’ouvre qu’une adresse http(s), dans le navigateur par défaut. |
| `GET /etat` | `{"groupes": [{"nom", "services": [{"nom", "statut": "ok" \| "attente" \| "panne" \| "eteint" \| "inconnu", "message", "depuis"}]}], "kuma": url}` : l’état des services (Uptime Kuma) ; `groupes: []` et un champ `erreur` quand Uptime Kuma ne répond pas. |

Comme la console, l’app envoie l’en-tête `Origin` du relais avec ses écritures (`POST`, `DELETE`) et à l’ouverture de
`/ws` ; le relais refuse une WebSocket d’une autre origine.

**Détail de `GET /maison/structure` :**

```json
{
  "version": 1,
  "etages": [{"id": "…", "nom": "…", "niveau": 0, "icone": null}],
  "pieces": [{"id": "…", "nom": "…", "etage": "…", "icone": null, "temperature": "sensor.…", "humidite": null}],
  "lumieres": {"light.…": "<id de la pièce>"}
}
```

Une autre version, ou une absence de la route, laisse la maison **en liste simple**.

**Détail de `GET /maison/console`** (réservée aux personnes connectées) : la roue, les jauges et la météo de la
console, telles qu’elle les montre. L’app montre la même roue ; sans cette route, elle prend les pièces de
`/maison/structure`.

```json
{
  "version": 1,
  "pieces": [{"nom": "SALON", "etage": "rdc", "lumiere": "light.…", "temperature": "sensor.…", "humidite": null, "air": null}],
  "autres": [{"nom": "CAVE", "etage": "ss", "temperature": "sensor.…", "humidite": "sensor.…"}],
  "jauges": [{"entite": "sensor.…", "libelle": "maison", "unite": "W", "max": 6000}],
  "meteo": "weather.…",
  "puissance": "sensor.…",
  "invites": "input_boolean.…",
  "voix": "sensor.…"
}
```

`pieces` est dans l’ordre de la roue (le 1er secteur en haut, puis dans le sens des aiguilles d’une montre).

Champs facultatifs de la version 1 (absents ou `null` : la fonction est simplement absente) :
- `pieces[].mots` : l’expression régulière qui reconnaît la pièce dans une réponse d’Alfred, à appliquer au texte en
  minuscules ; la roue anime les pièces citées, l’une après l’autre ;
- `invites` : le mode invités ; tant qu’il vaut `on`, l’historique, le résumé, les documents et les notifications
  sont masqués ;
- `voix` : la voix reconnue par la maison (un nom de personne en minuscules, ou `incertain`), montrée 8 s.

## WebSocket `wss://<relais>/ws`

**Ouverture.** Le relais s’authentifie auprès de HA, puis envoie `{"type": "ready", "ha_version": …}`, ou
`{"type": "fatal", "message": …}` (par exemple un jeton refusé par Home Assistant). `fatal` peut aussi arriver plus
tard ; la liaison se ferme ensuite. L’app n’envoie **rien** qui ressemble à une authentification.

**Ensuite,** ce sont les messages de l’API WebSocket de Home Assistant. Seule la liste blanche du relais passe, et
toute autre commande reçoit `{"id": <id de la commande>, "type": "result", "success": false, "error": {"code":
"refuse", "message": "<raison>"}}` ; l’`id` libère aussitôt la commande en attente. Parmi la liste blanche, l’app se
sert de :
- `get_states` ;
- `subscribe_events` (`state_changed`) ;
- `assist_pipeline/pipeline/list` (`preferred_pipeline`, et `pipelines[].conversation_engine` pour les Réglages) ;
- `assist_pipeline/run` ;
- `call_service` sur les lumières (`turn_on`, `turn_off`, `toggle`), avec `target.entity_id` ou `target.area_id`, et
  `service_data.brightness_pct` pour la luminosité ;
- `ping`.

**Taille des messages :** jusqu’à 16 Mo. L’état complet d’une maison dépasse vite la limite par défaut d’URLSession
(1 Mo).

## Le pipeline d’Assist (`assist_pipeline/run`)

Dans les deux modes : `end_stage: tts`, le pipeline préféré (`pipeline`) et le fil de la conversation
(`conversation_id`) quand ils sont connus. Un fil neuf à chaque conversation, et pour une question écrite hors
conversation.

**À l’écrit** (`start_stage: intent`, `input: {text: …}`).

**À la voix** (`start_stage: stt`, `input: {sample_rate: 16000, no_vad: true}`) :

- **L’audio** part en trames binaires `[canal][PCM 16 bits LE, 16 kHz, mono]`. Le canal est donné par
  `run-start.data.runner_data.stt_binary_handler_id`.
- **Avant `run-start`,** l’audio est mis en file, pas jeté.
- **La fin de parole est décidée par l’app** (HA demande une détection externe). Elle s’envoie comme une trame d’un
  seul octet, `[canal]`.

**Événements suivis :**
- `stt-end` : la transcription ;
- `intent-progress` : les appels d’outils (le 2e et les suivants arrivent sans `role`), leurs résultats (seul le
  succès est montré, jamais le contenu) et les morceaux de texte ;
- `run-start` et `intent-end` : le fil de la conversation (`conversation_id`) ;
- `intent-end` : la réponse, `processed_locally` (« intent local » ou « llm ») et `continue_conversation` ;
- `tts-end` : la voix, à lire par le relais (`/tts/<dernier segment de l’URL>`) ;
- `error` (`stt-no-text-recognized` : rien compris, on réécoute) ;
- `run-end`.

**Règles :**
- Un seul tour à la fois.
- Un événement d’un autre tour est ignoré.
- Un `result` en échec pour le tour le libère.
- **Au bout de 90 s, le tour échoue. Une action n’est jamais renvoyée après un délai dépassé**, car elle a pu être
  exécutée.
