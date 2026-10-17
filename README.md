# Alfred pour iPhone, iPad et Mac

L’app native d’**Alfred**, l’assistant vocal d’une maison pilotée par Home Assistant. On lui parle, il agit sur la
maison et répond de sa voix ; on voit la maison pièce par pièce, avec l’état qu’elle confirme réellement.

**C’est la console d’Alfred, en natif** (« Manor Command ») : la même roue des pièces autour du réacteur, les mêmes
jauges, les mêmes panneaux Alfred et Environnement, sombre seulement. Sur iPhone (et iPad à la verticale), trois vues
choisies en bas de l’écran ; au-delà de 1100 pt de large (iPad à l’horizontale, Mac à puce Apple), la disposition
large de la console, côte à côte.

**L’app ne parle qu’à la maison**, par son relais (le serveur de la console d’Alfred). Il n’y a ni cloud, ni compte
tiers, ni suivi. La voix va de l’appareil au relais, puis à Home Assistant, et jamais sur internet.

## Ce qu’elle fait (version 1, « Parler »)

- **Parler à Alfred**
  - Un toucher sur le noyau ouvre une conversation continue : chaque phrase est un tour, et Alfred réécoute après
    avoir répondu.
  - La conversation se ferme d’un toucher, après 90 s de silence, ou quand l’app passe en arrière-plan.
  - On voit ce qu’Alfred fait (« Allumer · Cuisine ✓ ») et on l’entend répondre pendant que sa voix est synthétisée.
- **Écrire à Alfred**
  - La réponse arrive par écrit. La lecture à voix haute est au choix, dans les réglages.
- **La maison (la roue)**
  - Un secteur par pièce de la console (nom, température), ambre quand la lumière est allumée. Toucher un secteur
    ouvre la pièce : ses mesures et un seul bouton, Allumer ou Éteindre. Le réacteur suit la commande (crochets,
    « EXÉCUTION », puis « CONFIRMÉ »).
  - Un état n’est affiché qu’une fois **confirmé par la maison**. Sans confirmation en 8 s, l’échec est visible : il
    n’est jamais supposé ni renvoyé.
- **L’environnement** : l’extérieur (météo), les pièces mesurées, l’énergie ; les jauges en bas de la console.

## Architecture

| Élément | Rôle |
|---|---|
| `Paquets/AlfredKit` | Le cœur, sans interface ni dépendance : protocole du relais, automate du pipeline d’Assist, détection de la parole, modèle de la maison. **Testé sous Linux et macOS.** |
| `App/` | L’app SwiftUI (iOS 26, iPhone et iPad, Mac à puce Apple) : la console en natif (`App/Design`, `App/Fonctions/Console`), son (capture, voix en continu), sécurité (trousseau, épinglage TLS). |
| `App/Demo` | Une maison de démonstration (sans réseau ni micro), pour les tests d’interface, les aperçus et les captures. |
| `project.yml` | Le projet Xcode, généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen). Le `.xcodeproj` n’est jamais versionné. |
| `docs/` | Le contrat du relais, la sécurité. |

Les règles du pipeline (fin de parole décidée par le client, trame binaire de fin, événements périmés ignorés, délai
de 90 s sans renvoi d’une action…) viennent de la console d’Alfred, où elles ont été mesurées. Elles sont reprises
règle par règle dans `AlfredKit` et vérifiées par ses tests.

Aucune bibliothèque tierce : seulement les frameworks d’Apple.

## Fabriquer

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

## Intégration et livraison

| Workflow | Quand | Quoi |
|---|---|---|
| `Intégration` | Chaque envoi, chaque demande de fusion | gitleaks ; `AlfredKit` sous Linux et macOS ; swift-format ; fabrication ; tests unitaires et d’interface ; audit d’accessibilité d’Apple en clair et en sombre (captures jointes) |
| `CodeQL` | Chaque envoi, et chaque semaine | Analyse de sécurité du code Swift et des workflows |
| `TestFlight` | À la main, ou sur une étiquette `v*` | Archive signée (signature automatique, clé d’API App Store Connect), envoi aux testeurs internes |
| `Certificats` | À la main | Inventaire des certificats de signature de l’équipe (sans aucun nom), ou création du certificat unique de la CI |

**Protections de la chaîne :**
- les actions sont épinglées par empreinte, et Dependabot les tient à jour ;
- les permissions sont minimales ;
- les outils téléchargés sont vérifiés par leur SHA-256 ;
- seuls `TestFlight` et `Certificats` lisent des secrets, à la main ou sur étiquette ; une contribution extérieure n’en
  reçoit jamais.

## Sécurité

Voir [`SECURITY.md`](SECURITY.md).

**Licence :** aucune. Le code est visible, tous droits réservés.
