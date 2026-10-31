# Alfred pour iPhone, iPad et Mac

L’app native d’**Alfred**, l’assistant vocal d’une maison pilotée par Home Assistant. On lui parle, il agit sur la
maison et répond de sa voix ; on voit la maison pièce par pièce, avec l’état qu’elle confirme réellement.

**C’est la console d’Alfred, en natif** (« Manor Command ») : la même roue des pièces autour du réacteur, les mêmes
jauges, les mêmes panneaux Alfred et Environnement, sombre seulement. Quatre espaces, comme la console :
**ALFRED · MAISON · MOI · SYSTÈME** — en bas de l’écran sur iPhone (et iPad à la verticale), dans un rail à gauche
au-delà de 1100 pt de large (iPad à l’horizontale, Mac à puce Apple), où ALFRED garde la disposition large de la
console, côte à côte, et MAISON replie l’assistant.

**L’app ne parle qu’à la maison**, par son relais (le serveur de la console d’Alfred). Il n’y a ni cloud, ni compte
tiers, ni suivi. La voix va de l’appareil au relais, puis à Home Assistant, et jamais sur internet.

## Ce qu’elle fait (version 1, « Parler »)

- **Parler à Alfred**
  - Un toucher sur le noyau ouvre une conversation continue : chaque phrase est un tour, et Alfred réécoute après
    avoir répondu.
  - La conversation se ferme d’un toucher, après 90 s de silence, ou quand l’app passe en arrière-plan.
  - Pendant la conversation, le bouton du micro (ou « m » au clavier) le coupe : une phrase commencée est envoyée et
    Alfred y répond, puis il n’entend plus rien ; sa réponse en cours finit, et la conversation reste ouverte (10 min au
    plus) ; un second appui et il réécoute aussitôt.
  - On l’entend répondre pendant que sa voix est synthétisée. Sous chaque réponse, comme la console : sa durée,
    « llm » ou « intent local », le nombre d’outils, et les « Détails techniques » repliés (chaque outil, ses
    arguments, fait ou échoué ; jamais le contenu d’un résultat).
  - Les pièces qu’Alfred nomme dans sa réponse bougent sur la roue ; la voix reconnue par la maison s’affiche 8 s.
- **Écrire à Alfred**
  - La réponse arrive par écrit. La lecture à voix haute est au choix, dans les réglages ; avec VoiceOver, une
    réponse qui n’est pas lue est annoncée.
  - Pendant une conversation, l’écrit en garde le fil et la conversation : la réponse est lue, puis Alfred réécoute
    (un nom que le micro comprend mal s’écrit sans tout recommencer).
  - Hors conversation, une question écrite part d’un fil neuf, sauf quand Alfred vient d’en poser une (« À quel
    moment ? ») : la réponse, écrite ou dite, reste dans le même fil.
- **La maison (la roue)**
  - Un secteur par pièce de la console (nom, température), ambre quand la lumière est allumée. Toucher un secteur
    ouvre la pièce : ses mesures et un seul bouton, Allumer ou Éteindre. Le réacteur suit la commande (crochets,
    « EXÉCUTION », puis « CONFIRMÉ »).
  - Un état n’est affiché qu’une fois **confirmé par la maison**. Sans confirmation en 8 s, l’échec est visible : il
    n’est jamais supposé ni renvoyé.
- **L’environnement** : l’extérieur (météo), les pièces mesurées, l’énergie ; les jauges en bas de la console ;
  l’état des services de la maison (pastilles).
- **MOI et SYSTÈME, comme la console connectée** (Notifications, dans l’en-tête, mène à MOI ; les pastilles d’état, à
  SYSTÈME)
  - *Documents* (MOI) : comme la console, ajouter un ou plusieurs documents (photothèque et fichiers en sélection
    multiple, scanner de documents d’iOS) dans « À envoyer » (nom et taille ; trop lourd ou type refusé : dit
    d’emblée), choisir leurs étiquettes (de la liste de la maison, ou nouvelles) et le jour qu’ils concernent, puis
    « Envoyer à Paperless » ; « En cours » suit chaque fichier, une ligne confirme ce qui est rangé ou déjà présent
    (« voir » ouvre Paperless), et un document rangé quitte la liste ; « À revoir » garde les vrais échecs, avec
    leur motif (« Réessayer », « Retirer »).
  - *Notifications* (MOI) : la copie de celles des téléphones de la personne connectée, marquées lues à l’arrivée.
  - *Connecteurs* (SYSTÈME) : tout ce à quoi Alfred est relié, une carte chacun — son logo, une ligne, son état en mots
    (« En service », « En veille · PC éteint », « En panne depuis… »), à la maison ou sur Internet, ce qu’Alfred en
    fait — et sa fiche (ce qu’il en fait, ce qu’il ne fait jamais, où vont les données, qui y a accès, à essayer,
    l’historique de la surveillance). Les textes viennent de la maison, communs avec la console.
  - *Autres systèmes* (SYSTÈME) : les liens que la maison donne selon le compte, ouverts dans Safari.
  - *Réglages & état* (SYSTÈME) : le modèle, les entités, la dernière réponse, le choix et l’essai du micro ; puis le compte,
    la lecture des réponses écrites et les engagements de confidentialité.
- **Mode invités** : quand la maison le demande, l’historique, le résumé, les documents et les notifications sont
  masqués.
- **Avec un clavier** (iPad, Mac) : espace pour parler, / pour écrire ; Échap ferme, dans l’ordre de la console, la
  liste des autres systèmes, la saisie, la pièce, puis la conversation. En disposition large, une poignée masque ou
  rend chaque panneau de côté.

## Architecture

| Élément | Rôle |
|---|---|
| `Paquets/AlfredKit` | Le cœur, sans interface ni dépendance : protocole du relais, automate du pipeline d’Assist, détection de la parole, modèle de la maison. **Testé sous Linux et macOS.** |
| `App/` | L’app SwiftUI (iOS 26, iPhone et iPad, Mac à puce Apple) : la console en natif (`App/Design`, `App/Fonctions/Console`), son (capture, voix en continu), sécurité (trousseau, épinglage TLS). |
| `App/Demo` | Une maison de démonstration (sans réseau ni micro), pour les tests d’interface, les aperçus et les captures. |
| `project.yml` | Le projet Xcode, généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen). Le `.xcodeproj` n’est jamais versionné. |
| `docs/` | Le contrat du relais (la sécurité : [`SECURITY.md`](SECURITY.md)). |

Les règles du pipeline (fin de parole décidée par le client, trame binaire de fin, événements périmés ignorés, délai
de 90 s sans renvoi d’une action…) viennent de la console d’Alfred, où elles ont été mesurées. Elles sont reprises
règle par règle dans `AlfredKit` et vérifiées par ses tests.

Aucune bibliothèque tierce : seulement les frameworks d’Apple.

## Fabriquer

Avec **Xcode 27.2** (macOS Tahoe 26.6 ou plus récent ; la CI aussi, depuis le 31.10.2026).

```sh
scripts/generer.sh                 # configuration (facultative) + projet Xcode
open Alfred.xcodeproj
```

**Sans configuration**, l’app demande l’adresse du relais au premier lancement. La configuration d’une maison
(adresse du relais, autorité à épingler, hôte de la page de connexion) **n’est jamais dans le dépôt**. Elle arrive
par l’environnement de `scripts/generer.sh`, et par les secrets de la CI pour TestFlight.

Le cœur se teste partout où Swift 6.2 tourne :

```sh
swift test --package-path Paquets/AlfredKit
```

**Démo :** l’argument de lancement `-demo` ouvre l’app sur la maison de démonstration.

**Icône :** `App/Ressources/AppIcon.icon` (format d’Icon Composer, verre liquide d’iOS 26) est produite par
`python3 scripts/outils/icone.py` ; elle ne se modifie pas à la main (un test vérifie qu’elle est à jour).

## Intégration et livraison

| Workflow | Quand | Quoi |
|---|---|---|
| `Intégration` | Chaque envoi, chaque demande de fusion | Sous Linux d’abord : gitleaks ; tests des outils Python (App Store Connect et GitHub simulés, masques des journaux, icône à jour) ; `AlfredKit` ; swift-format et tailles de texte figées (avant de réserver un Mac) ; « l’app a-t-elle changé ? ». Puis, si l’app a changé, sur trois Mac en parallèle : fabrication, `AlfredKit` sous macOS, tests unitaires et d’interface, audit d’accessibilité d’Apple (captures jointes) ; iPad en disposition large ; iPhone le plus étroit (en-tête) ; et l’icône compilée et rendue par les outils d’Apple dans ses six apparences (artefact « icone ») |
| `Doc` | Chaque envoi, chaque demande de fusion | Chaque commit qui change le code de l’app change aussi une doc (`*.md` : ce README, `docs/`), ou son message dit « Doc : inchangée — <raison> » (`scripts/outils/doc_suit.py`, réglages `scripts/outils/doc_suit.json`) ; le même contrôle refuse le commit en local (crochet `commit-msg`) |
| `CodeQL` | Chaque envoi, et chaque semaine | Analyse de sécurité du code Swift, des workflows et des outils Python |
| `TestFlight` | À la main, sur une étiquette `v*`, ou tout seul quand `Intégration` réussit sur un envoi sur `main` et que ce qui part dans l’app a changé depuis la dernière fabrication | Archive signée (signature automatique : certificat de développement unique de la CI, distribution gérée par Apple), envoi aux testeurs internes, puis aux testeurs externes après l’examen d’Apple (« externe », coché par défaut) ; à la main, « envoyer » décoché : archive et export signés seulement |
| `Testeurs externes` | À la main, ou appelé par `TestFlight` | Groupe externe sans lien public, informations de test et contact de l’examen d’Apple, envoi d’une fabrication à l’examen, invitations ; aucune donnée personnelle dans le journal (secrets masqués champ par champ) |
| `Certificats` | À la main | Inventaire des certificats de signature de l’équipe (sans aucun nom), ou création du certificat unique de la CI |
| `Fiche App Store` | À la main | Visuels « En-tête et résultats de recherche » de la version modifiable ; icône extraite de chaque fabrication ; fabrication rattachée à la version (rien n’est soumis) |

**Protections de la chaîne :**
- les actions sont épinglées par empreinte, et Dependabot les tient à jour ;
- les permissions sont minimales ;
- les outils téléchargés sont vérifiés par leur SHA-256 ;
- seuls `TestFlight`, `Testeurs externes` et `Certificats` lisent des secrets, à la main ou sur étiquette ; une
  contribution extérieure n’en reçoit jamais ;
- `TestFlight` ne part que si `Intégration` a réussi sur le même commit, et fabrique ce commit-là (lancé par
  `Intégration`, jamais depuis une copie du dépôt ni une demande de fusion) ;
- un run d’`Intégration` remplacé par un envoi plus récent s’annule, sur `main` aussi ; « l’app a-t-elle changé ? »
  compare à la dernière `Intégration` RÉUSSIE (jamais au commit précédent) et, sans base certaine, tout tourne
  (`scripts/outils/changements.py`). Une étiquette `v*` doit donc viser un commit dont l’`Intégration` a réussi ;
  sinon, lancer `Intégration` à la main sur l’étiquette ;
- les journaux sont publics : le nom du titulaire du certificat de signature y est masqué dès sa lecture, comme le
  contact de l’examen d’Apple et les testeurs.

## Sécurité

Voir [`SECURITY.md`](SECURITY.md).

**Licence :** [FSL-1.1-ALv2](LICENSE.md) (*Functional Source License*, https://fsl.software). Lire, utiliser, modifier
et redistribuer le code est permis, sauf pour en faire un produit ou un service commercial concurrent ; chaque version
devient Apache 2.0 deux ans après sa publication. Les tracés des logos de marques de la page Connecteurs viennent de
[Simple Icons](https://simpleicons.org) (CC0).
