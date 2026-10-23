# Sécurité

## Modèle

L’app ne parle qu’au **relais** de la maison, sur le réseau local. Seul le relais détient des jetons de
Home Assistant ; l’app n’en voit aucun (elle n’a que le cookie de session du relais). Il ouvre la WebSocket de HA
avec le jeton **de la personne connectée** et ne laisse passer qu’une **liste blanche** de commandes :
- lire les états et s’abonner à leurs changements ;
- lancer le pipeline d’Assist ;
- les lumières ;
- pause et lecture des lecteurs ;
- un seul interrupteur, nommé d’avance (la musique coupée par Alfred).

Le reste est refusé, quel que soit le compte : serrures, scripts, configuration, etc. Une app compromise ne peut pas
dépasser ce que le relais permet.

| Sujet | Mesure |
|---|---|
| **Transport** | HTTPS / WSS, TLS 1.2 au moins, ATS actif (aucune exception globale ; les deux exceptions ci-dessous ne couvrent chacune qu’un hôte, sans ses sous-domaines). |
| **Identité du relais** | Autorité de la maison **épinglée** : pour l’hôte du relais, seule elle est acceptée, ni les autorités du système, ni un profil installé. Les règles TLS d’iOS restent appliquées (nom d’hôte, durée, algorithmes). Accepter une autorité que l’appareil ne connaît pas « assouplit » la confiance, ce qu’ATS interdit pour un domaine qu’il protège ([Apple](https://developer.apple.com/documentation/foundation/performing-manual-server-trust-authentication)) : le relais est donc une exception ATS (`NSExceptionAllowsInsecureHTTPLoads`, la clé qu’Apple prévoit pour cela), **ce seul hôte**, injectée à la fabrication avec l’autorité. L’app n’y va qu’en https : `Relais` n’admet que https et wss, et la page de connexion refuse http vers lui. Tests : `AppTests/ConfianceTLSTests.swift`. Une version distribuée par l’App Store devra justifier cette exception à la revue d’Apple. |
| **Page de connexion** | Celle de Home Assistant, dans une vue web **sans mémoire** (aucun cookie ni cache gardé). Si HA la sert en http sur le réseau local, une exception ATS couvre **ce seul hôte**, injectée à la fabrication. |
| **Session** | Le cookie de session du relais (valable un an), rangé dans le **trousseau** de l’appareil : jamais synchronisé ni sauvegardé ailleurs, lisible après le premier déverrouillage. La déconnexion supprime le jeton dans Home Assistant ; si la maison ne répond pas, l’app le dit (l’accès y reste ouvert). Une session révoquée est détectée à chaque connexion (`/moi`) : la conversation et le fil de la personne précédente disparaissent. À la déconnexion comme à la session expirée, les réponses d’Hermes qu’elle attendait disparaissent aussi : une réponse réclamée avant, arrivée après, est ignorée (ni montrée ni lue à la personne suivante). |
| **Données** | Rien n’est gardé sur l’iPhone en dehors de la session et de quelques réglages (adresse du relais saisie, lecture des réponses écrites, micro choisi, panneaux masqués). La conversation, les documents, les notifications et l’état des services vivent en mémoire seulement. Protection des fichiers « complète ». Aucun suivi, aucun domaine de suivi (`PrivacyInfo.xcprivacy`). |
| **Documents** | Un document choisi (photothèque, scanner de documents d’iOS, fichiers) part au relais, et seulement là ; l’app n’en garde aucune copie. La photothèque s’ouvre par le sélecteur d’iOS : l’app ne voit que la photo choisie, sans autorisation sur la photothèque. L’appareil photo ne sert qu’au scanner, sur demande. |
| **Liens** | Les autres systèmes (`/liens`) s’ouvrent dans Safari, jamais dans l’app ; seules les adresses http(s) sont acceptées. |
| **Micro** | Ouvert seulement pendant une conversation, ou l’essai demandé dans Réglages & état (rien n’est alors envoyé à la maison). Il se ferme au toucher, après 90 s de silence, quand iOS interrompt le son ou que le matériel audio change, quand la liaison avec la maison tombe, avec la fenêtre de l’essai, ou quand l’app passe en arrière-plan. VoiceOver se tait micro ouvert (il serait entendu). |
| **Voix d’Alfred** | Des écouteurs retirés pendant qu’il parle : il se tait, plutôt que de continuer sur le haut-parleur (une réponse peut être privée). |
| **Journal** | Aucun contenu de conversation dans les journaux du système. |
| **Configuration d’une maison** | Jamais dans le dépôt : adresses, autorité et hôtes arrivent par les secrets de la CI. |

## Chaîne de fabrication

- **Actions :** épinglées par empreinte de commit, avec des permissions minimales.
- **Outils téléchargés :** vérifiés par leur SHA-256.
- **Image Swift :** épinglée par empreinte.
- **Contrôles :** gitleaks à chaque envoi ; CodeQL (Swift, workflows et outils Python).
- **Secrets :** seuls les workflows `TestFlight` (lancement manuel ou étiquette), `Testeurs externes` (clé d’API,
  contact de l’examen d’Apple et testeurs, masqués champ par champ dans le journal) et `Certificats` (lancement manuel,
  clé d’API seule) les lisent. Ils ne sont jamais transmis à une contribution extérieure.
- **Signature :** automatique. L’archive est signée par un certificat de développement unique, gardé dans les secrets
  du dépôt et installé dans un trousseau temporaire, effacé en fin de fabrication. Le nom de son titulaire est masqué
  dans le journal public dès sa lecture. La distribution est signée par Apple (certificat « cloud »). Les profils sont
  gérés par Xcode ; aucun n’est stocké.
- **Livraison :** `TestFlight` ne part que si `Intégration` a réussi sur le même commit.

## Signaler une faille

Ouvrez un avis de sécurité privé sur GitHub (onglet *Security* → *Report a vulnerability*), plutôt qu’un ticket
public.
