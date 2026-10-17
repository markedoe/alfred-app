# Sécurité

## Modèle

L’app ne parle qu’au **relais** de la maison, sur le réseau local. Le relais est le seul à détenir un jeton
Home Assistant pour la maison. Il ouvre la WebSocket de HA avec le jeton **de la personne connectée** et ne laisse
passer qu’une **liste blanche** de commandes :
- lire les états et s’abonner à leurs changements ;
- lancer le pipeline d’Assist ;
- les lumières ;
- pause et lecture des lecteurs.

Le reste est refusé, quel que soit le compte : serrures, scripts, configuration, etc. Une app compromise ne peut pas
dépasser ce que le relais permet.

| Sujet | Mesure |
|---|---|
| **Transport** | HTTPS / WSS, TLS 1.2 au moins, ATS actif (aucune exception globale). |
| **Identité du relais** | Autorité de la maison **épinglée** : pour l’hôte du relais, seule elle est acceptée, ni les autorités du système, ni un profil installé. Les règles TLS d’iOS restent appliquées (nom d’hôte, durée, algorithmes). Tests : `AppTests/ConfianceTLSTests.swift`. |
| **Page de connexion** | Celle de Home Assistant, dans une vue web **sans mémoire** (aucun cookie ni cache gardé). Si HA la sert en http sur le réseau local, une exception ATS couvre **ce seul hôte**, injectée à la fabrication. |
| **Session** | Le cookie de session du relais, rangé dans le **trousseau** de l’appareil : jamais synchronisé, lisible après le premier déverrouillage. La déconnexion supprime le jeton dans Home Assistant. Une session révoquée est détectée à chaque connexion (`/moi`). |
| **Données** | Rien n’est gardé sur l’iPhone en dehors de la session et de deux réglages. La conversation vit en mémoire seulement. Protection des fichiers « complète ». Aucun suivi, aucun domaine de suivi (`PrivacyInfo.xcprivacy`). |
| **Micro** | Ouvert seulement pendant une conversation. Il se ferme au toucher, après 90 s de silence, quand iOS interrompt le son, ou quand l’app passe en arrière-plan. |
| **Journal** | Aucun contenu de conversation dans les journaux du système. |
| **Configuration d’une maison** | Jamais dans le dépôt : adresses, autorité et hôtes arrivent par les secrets de la CI. |

## Chaîne de fabrication

- **Actions :** épinglées par empreinte de commit, avec des permissions minimales.
- **Outils téléchargés :** vérifiés par leur SHA-256.
- **Image Swift :** épinglée par empreinte.
- **Contrôles :** gitleaks à chaque envoi ; CodeQL (Swift et workflows).
- **Secrets :** seuls les workflows `TestFlight` (lancement manuel ou étiquette) et `Certificats` (lancement manuel,
  clé d’API seule) les lisent. Ils ne sont jamais transmis à une contribution extérieure.
- **Signature :** automatique, gérée par Apple. Aucun certificat ni profil n’est stocké.

## Signaler une faille

Ouvrez un avis de sécurité privé sur GitHub (onglet *Security* → *Report a vulnerability*), plutôt qu’un ticket
public.
