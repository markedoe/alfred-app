# Le contrat du relais

Le relais est le serveur de la console d’Alfred. L’app l’utilise tel quel. Ce document décrit ce que l’app en attend,
et les tests d’`AlfredKit` le vérifient.

## Connexion (parcours web du relais)

1. **Ouverture de la page.** L’app ouvre `GET /connexion?retour=/moi` dans une vue web sans mémoire. Le relais renvoie
   vers la page de connexion de Home Assistant (OAuth « authorization code »).
2. **Pose du cookie.** Le relais échange le code, crée un jeton longue durée **au nom de la personne**, et pose le
   cookie `alfred_session` (Secure, HttpOnly).
3. **Fin du parcours.** Le relais renvoie vers `/moi`. L’app reprend alors le cookie, le range dans le trousseau, et
   ferme la vue.
4. **Requêtes suivantes.** Chaque requête porte ce cookie, dans le magasin de cookies d’une session URLSession
   éphémère.

**Déconnexion :** `GET /deconnexion` supprime le jeton dans Home Assistant et efface la session.

## Routes HTTP

| Route | Réponse |
|---|---|
| `GET /moi` | `{"connecte": bool, "nom": …, "user_id": …, "titre": "Monsieur" \| "Madame" \| "Mademoiselle" \| ""}`. `connecte: false` avec un cookie signifie que la session a été révoquée. |
| `GET /maison/structure` | Version 1, réservée aux personnes connectées. Voir le détail ci-dessous. |
| `GET /maison/console` | Version 1, réservée aux personnes connectées : la roue, les jauges et la météo de la console. |
| `GET /tts/<jeton>` | La voix d’Alfred, servie **pendant** sa synthèse (MP3 en continu). |
| `GET /static/ack/ack-<n><suffixe>.mp3` | Les clips d’accueil (« Bien, Monsieur »). Le suffixe vaut `""`, `-madame`, `-mademoiselle` ou `-neutre`. |
| `GET /docs` | `{"documents": [{"id", "nom", "etat": "pret" \| "en cours" \| "erreur", "resume", "erreur", "depose_le", "pour_le", "paperless", "alerte"}]}`, la plus récente d’abord ; jamais le texte d’un document. 401 sans connexion, 403 pour un compte sans documents. |
| `POST /docs` | Dépôt multipart : `fichier` (PDF, JPEG, PNG, WebP, texte ou e-mail, 20 Mo au plus), `nom`, `pour_le` (AAAA-MM-JJ, facultatif). 202 et la fiche ; 415 pour un autre type. |
| `DELETE /docs/<id>` | Supprime le document partout. |
| `GET /notifications` | `{"notifications": [{"id", "t", "titre", "message", "lu"}], "non_lues": n}` : celles de la personne connectée seulement (copie de ses téléphones, réponses d’Hermes annoncées). 401 sans connexion. |
| `POST /notifications/lues` · `POST /notifications/effacer` | Tout marquer comme lu · tout effacer. |
| `GET /liens` | `[{"nom", "url", "note"}]` : les autres systèmes, selon le compte (vide pour un invité ; 503 si HA ne répond pas). L’app n’ouvre qu’une adresse http(s), dans Safari. |
| `GET /etat` | `{"groupes": [{"nom", "services": [{"nom", "statut": "ok" \| "attente" \| "panne" \| "eteint" \| "inconnu", "message", "depuis"}]}], "kuma": url}` : l’état des services (Uptime Kuma). |

Les écritures (`POST`, `DELETE`) portent l’en-tête `Origin` du relais, comme la console.

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
`{"type": "fatal", "message": …}`. L’app n’envoie **rien** qui ressemble à une authentification.

**Ensuite,** ce sont les messages de l’API WebSocket de Home Assistant. Seule la liste blanche passe, et toute autre
commande reçoit `{"type": "result", "success": false, "error": {"code": "refuse"}}`. Messages permis :
- `get_states` ;
- `subscribe_events` (`state_changed`) ;
- `assist_pipeline/pipeline/list` ;
- `assist_pipeline/run` ;
- `call_service` sur les lumières (`turn_on`, `turn_off`, `toggle`), avec `entity_id` ou `area_id` ;
- `ping`.

**Taille des messages :** jusqu’à 16 Mo. L’état complet d’une maison dépasse vite la limite par défaut d’URLSession
(1 Mo).

## Le pipeline d’Assist (`assist_pipeline/run`)

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
- `intent-end` : la réponse, et `continue_conversation` ;
- `tts-end` : la voix, à lire par le relais (`/tts/<dernier segment de l’URL>`) ;
- `error` (`stt-no-text-recognized` : rien compris, on réécoute) ;
- `run-end`.

**Règles :**
- Un seul tour à la fois.
- Un événement d’un autre tour est ignoré.
- Un `result` en échec pour le tour le libère.
- **Au bout de 90 s, le tour échoue. Une action n’est jamais renvoyée après un délai dépassé**, car elle a pu être
  exécutée.
