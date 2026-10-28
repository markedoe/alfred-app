import Foundation

/// La réponse RÉELLE du relais à `GET /connecteurs` (28.10, PC du bureau éteint), nettoyée : adresses en `.example`,
/// aucun nom de la maison. Sert aux tests des connecteurs et des tracés SVG.
enum ExempleConnecteurs {
    static let json = Data(
        #"""
        {
          "groupes": [
            {
              "nom": "Maison",
              "connecteurs": [
                {
                  "id": "home-assistant",
                  "nom": "Home Assistant",
                  "phrase": "Lumières, Velux, volets, musique et capteurs de toute la maison.",
                  "icone": {
                    "forme": "marque",
                    "d": "M22.939 10.627 13.061.749a1.505 1.505 0 0 0-2.121 0l-9.879 9.878C.478 11.21 0 12.363 0 13.187v9c0 .826.675 1.5 1.5 1.5h9.227l-4.063-4.062a2.034 2.034 0 0 1-.664.113c-1.13 0-2.05-.92-2.05-2.05s.92-2.05 2.05-2.05 2.05.92 2.05 2.05c0 .233-.041.456-.113.665l3.163 3.163V9.928a2.05 2.05 0 0 1-1.15-1.84c0-1.13.92-2.05 2.05-2.05s2.05.92 2.05 2.05a2.05 2.05 0 0 1-1.15 1.84v8.127l3.146-3.146A2.051 2.051 0 0 1 18 12.239c1.13 0 2.05.92 2.05 2.05s-.92 2.05-2.05 2.05c-.25 0-.488-.047-.709-.13L12.9 20.602v3.088h9.6c.825 0 1.5-.675 1.5-1.5v-9c0-.825-.477-1.977-1.061-2.561z"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "agit",
                  "mode_mot": "Agit",
                  "etat": {
                    "statut": "ok",
                    "mot": "En service",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "Home Assistant",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": "http://maison.example:8123",
                  "fiche": {
                    "fait": "Allume, éteint, ouvre et règle la musique ; lit les températures, l'énergie et l'historique des pièces.",
                    "jamais": "Jamais la serrure ; « éteins tout » n'éteint que les lumières, jamais les Velux ni les volets.",
                    "donnees": "Tout reste à la maison, sur le serveur.",
                    "acces": "Toute la famille ; un invité, seulement avec l'accord d'une personne de la maison.",
                    "essayer": [
                      "Allume le salon",
                      "Quelle température au salon ?",
                      "Combien consomme la maison ?"
                    ]
                  }
                },
                {
                  "id": "alertes",
                  "nom": "Alertes vitales",
                  "phrase": "Fumée, CO, fuite d'eau : annonce à voix haute et sur les téléphones.",
                  "icone": {
                    "forme": "trait",
                    "d": "M6 16v-5a6 6 0 0 1 12 0v5l2 2H4z M10 20a2 2 0 0 0 4 0 M12 3v1"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "parle",
                  "mode_mot": "Parle",
                  "etat": {
                    "statut": "ok",
                    "mot": "En service",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "Piper (alertes vocales)",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Annonce l'alerte dans la maison et l'envoie aux téléphones de la famille.",
                    "jamais": "Ne dépend pas du PC du bureau : marche même quand il est éteint ; n'est jamais arrêtée.",
                    "donnees": "Tout reste à la maison.",
                    "acces": "Toute la famille.",
                    "essayer": []
                  }
                }
              ]
            },
            {
              "nom": "Voix et cerveau",
              "connecteurs": [
                {
                  "id": "modele",
                  "nom": "Modèle d'Alfred",
                  "phrase": "Le cerveau d'Alfred (gemma), sur le PC du bureau.",
                  "icone": {
                    "forme": "marque",
                    "d": "M16.361 10.26a.894.894 0 0 0-.558.47l-.072.148.001.207c0 .193.004.217.059.353.076.193.152.312.291.448.24.238.51.3.872.205a.86.86 0 0 0 .517-.436.752.752 0 0 0 .08-.498c-.064-.453-.33-.782-.724-.897a1.06 1.06 0 0 0-.466 0zm-9.203.005c-.305.096-.533.32-.65.639a1.187 1.187 0 0 0-.06.52c.057.309.31.59.598.667.362.095.632.033.872-.205.14-.136.215-.255.291-.448.055-.136.059-.16.059-.353l.001-.207-.072-.148a.894.894 0 0 0-.565-.472 1.02 1.02 0 0 0-.474.007Zm4.184 2c-.131.071-.223.25-.195.383.031.143.157.288.353.407.105.063.112.072.117.136.004.038-.01.146-.029.243-.02.094-.036.194-.036.222.002.074.07.195.143.253.064.052.076.054.255.059.164.005.198.001.264-.03.169-.082.212-.234.15-.525-.052-.243-.042-.28.087-.355.137-.08.281-.219.324-.314a.365.365 0 0 0-.175-.48.394.394 0 0 0-.181-.033c-.126 0-.207.03-.355.124l-.085.053-.053-.032c-.219-.13-.259-.145-.391-.143a.396.396 0 0 0-.193.032zm.39-2.195c-.373.036-.475.05-.654.086-.291.06-.68.195-.951.328-.94.46-1.589 1.226-1.787 2.114-.04.176-.045.234-.045.53 0 .294.005.357.043.524.264 1.16 1.332 2.017 2.714 2.173.3.033 1.596.033 1.896 0 1.11-.125 2.064-.727 2.493-1.571.114-.226.169-.372.22-.602.039-.167.044-.23.044-.523 0-.297-.005-.355-.045-.531-.288-1.29-1.539-2.304-3.072-2.497a6.873 6.873 0 0 0-.855-.031zm.645.937a3.283 3.283 0 0 1 1.44.514c.223.148.537.458.671.662.166.251.26.508.303.82.02.143.01.251-.043.482-.08.345-.332.705-.672.957a3.115 3.115 0 0 1-.689.348c-.382.122-.632.144-1.525.138-.582-.006-.686-.01-.853-.042-.57-.107-1.022-.334-1.35-.68-.264-.28-.385-.535-.45-.946-.03-.192.025-.509.137-.776.136-.326.488-.73.836-.963.403-.269.934-.46 1.422-.512.187-.02.586-.02.773-.002zm-5.503-11a1.653 1.653 0 0 0-.683.298C5.617.74 5.173 1.666 4.985 2.819c-.07.436-.119 1.04-.119 1.503 0 .544.064 1.24.155 1.721.02.107.031.202.023.208a8.12 8.12 0 0 1-.187.152 5.324 5.324 0 0 0-.949 1.02 5.49 5.49 0 0 0-.94 2.339 6.625 6.625 0 0 0-.023 1.357c.091.78.325 1.438.727 2.04l.13.195-.037.064c-.269.452-.498 1.105-.605 1.732-.084.496-.095.629-.095 1.294 0 .67.009.803.088 1.266.095.555.288 1.143.503 1.534.071.128.243.393.264.407.007.003-.014.067-.046.141a7.405 7.405 0 0 0-.548 1.873c-.062.417-.071.552-.071.991 0 .56.031.832.148 1.279L3.42 24h1.478l-.05-.091c-.297-.552-.325-1.575-.068-2.597.117-.472.25-.819.498-1.296l.148-.29v-.177c0-.165-.003-.184-.057-.293a.915.915 0 0 0-.194-.25 1.74 1.74 0 0 1-.385-.543c-.424-.92-.506-2.286-.208-3.451.124-.486.329-.918.544-1.154a.787.787 0 0 0 .223-.531c0-.195-.07-.355-.224-.522a3.136 3.136 0 0 1-.817-1.729c-.14-.96.114-2.005.69-2.834.563-.814 1.353-1.336 2.237-1.475.199-.033.57-.028.776.01.226.04.367.028.512-.041.179-.085.268-.19.374-.431.093-.215.165-.333.36-.576.234-.29.46-.489.822-.729.413-.27.884-.467 1.352-.561.17-.035.25-.04.569-.04.319 0 .398.005.569.04a4.07 4.07 0 0 1 1.914.997c.117.109.398.457.488.602.034.057.095.177.132.267.105.241.195.346.374.43.14.068.286.082.503.045.343-.058.607-.053.943.016 1.144.23 2.14 1.173 2.581 2.437.385 1.108.276 2.267-.296 3.153-.097.15-.193.27-.333.419-.301.322-.301.722-.001 1.053.493.539.801 1.866.708 3.036-.062.772-.26 1.463-.533 1.854a2.096 2.096 0 0 1-.224.258.916.916 0 0 0-.194.25c-.054.109-.057.128-.057.293v.178l.148.29c.248.476.38.823.498 1.295.253 1.008.231 2.01-.059 2.581a.845.845 0 0 0-.044.098c0 .006.329.009.732.009h.73l.02-.074.036-.134c.019-.076.057-.3.088-.516.029-.217.029-1.016 0-1.258-.11-.875-.295-1.57-.597-2.226-.032-.074-.053-.138-.046-.141.008-.005.057-.074.108-.152.376-.569.607-1.284.724-2.228.031-.26.031-1.378 0-1.628-.083-.645-.182-1.082-.348-1.525a6.083 6.083 0 0 0-.329-.7l-.038-.064.131-.194c.402-.604.636-1.262.727-2.04a6.625 6.625 0 0 0-.024-1.358 5.512 5.512 0 0 0-.939-2.339 5.325 5.325 0 0 0-.95-1.02 8.097 8.097 0 0 1-.186-.152.692.692 0 0 1 .023-.208c.208-1.087.201-2.443-.017-3.503-.19-.924-.535-1.658-.98-2.082-.354-.338-.716-.482-1.15-.455-.996.059-1.8 1.205-2.116 3.01a6.805 6.805 0 0 0-.097.726c0 .036-.007.066-.015.066a.96.96 0 0 1-.149-.078A4.857 4.857 0 0 0 12 3.03c-.832 0-1.687.243-2.456.698a.958.958 0 0 1-.148.078c-.008 0-.015-.03-.015-.066a6.71 6.71 0 0 0-.097-.725C8.997 1.392 8.337.319 7.46.048a2.096 2.096 0 0 0-.585-.041Zm.293 1.402c.248.197.523.759.682 1.388.03.113.06.244.069.292.007.047.026.152.041.233.067.365.098.76.102 1.24l.002.475-.12.175-.118.178h-.278c-.324 0-.646.041-.954.124l-.238.06c-.033.007-.038-.003-.057-.144a8.438 8.438 0 0 1 .016-2.323c.124-.788.413-1.501.696-1.711.067-.05.079-.049.157.013zm9.825-.012c.17.126.358.46.498.888.28.854.36 2.028.212 3.145-.019.14-.024.151-.057.144l-.238-.06a3.693 3.693 0 0 0-.954-.124h-.278l-.119-.178-.119-.175.002-.474c.004-.669.066-1.19.214-1.772.157-.623.434-1.185.68-1.382.078-.062.09-.063.159-.012z"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "comprend",
                  "mode_mot": "Comprend",
                  "etat": {
                    "statut": "eteint",
                    "mot": "En veille · PC éteint",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "Ollama (desktop)",
                        "statut": "eteint",
                        "mot": "En veille · PC éteint",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      },
                      {
                        "nom": "gemma chargé",
                        "statut": "eteint",
                        "mot": "En veille · PC éteint",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Comprend les demandes, choisit l'outil, rédige la réponse.",
                    "jamais": "N'agit jamais lui-même : chaque action passe par la garde.",
                    "donnees": "Sur le PC de la maison ; rien ne part sur Internet.",
                    "acces": "Toute la famille, par la voix, la console et l'app.",
                    "essayer": [
                      "Pourquoi fait-il chaud au bureau ?"
                    ]
                  }
                },
                {
                  "id": "ecoute",
                  "nom": "Écoute",
                  "phrase": "Transcrit la voix et reconnaît qui parle.",
                  "icone": {
                    "forme": "trait",
                    "d": "M12 4a3 3 0 0 1 3 3v5a3 3 0 0 1-6 0V7a3 3 0 0 1 3-3z M6 11a6 6 0 0 0 12 0 M12 17v3 M9 20h6"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "ecoute",
                  "mode_mot": "Écoute",
                  "etat": {
                    "statut": "eteint",
                    "mot": "En veille · PC éteint",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "Écoute (relais)",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      },
                      {
                        "nom": "Whisper (desktop)",
                        "statut": "eteint",
                        "mot": "En veille · PC éteint",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Transforme la parole en texte (Whisper, sur le PC) et reconnaît la voix des personnes enrôlées.",
                    "jamais": "Les empreintes de voix ne quittent jamais la maison.",
                    "donnees": "À la maison : le relais et le PC du bureau.",
                    "acces": "Toute la famille.",
                    "essayer": []
                  }
                },
                {
                  "id": "voix",
                  "nom": "Voix d'Alfred",
                  "phrase": "La voix d'Alfred, produite sur le PC du bureau.",
                  "icone": {
                    "forme": "trait",
                    "d": "M4 10h4l5-4v12l-5-4H4z M16 9a4 4 0 0 1 0 6 M18.5 6.5a7.5 7.5 0 0 1 0 11"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "parle",
                  "mode_mot": "Parle",
                  "etat": {
                    "statut": "eteint",
                    "mot": "En veille · PC éteint",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "XTTS (desktop)",
                        "statut": "eteint",
                        "mot": "En veille · PC éteint",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Lit les réponses d'Alfred à voix haute.",
                    "jamais": "Rien ne part sur Internet.",
                    "donnees": "À la maison, sur le PC du bureau.",
                    "acces": "Toute la famille.",
                    "essayer": []
                  }
                },
                {
                  "id": "garde",
                  "nom": "Garde",
                  "phrase": "Vérifie chaque action d'Alfred avant qu'elle parte.",
                  "icone": {
                    "forme": "trait",
                    "d": "M12 3l7 3v6c0 4.2-2.9 7.6-7 9-4.1-1.4-7-4.8-7-9V6z M9 12l2 2 4-4"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "verifie",
                  "mode_mot": "Vérifie",
                  "etat": {
                    "statut": "ok",
                    "mot": "En service",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "Garde",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Laisse passer ce qui est permis, refuse le reste et le signale ; relance Alfred quand il annonce sans faire.",
                    "jamais": "Ne laisse jamais une action partir après un texte venu de l'extérieur (e-mail, document, page web).",
                    "donnees": "À la maison.",
                    "acces": "S'applique à tout le monde, invités compris.",
                    "essayer": []
                  }
                }
              ]
            },
            {
              "nom": "Ce qu'Alfred sait",
              "connecteurs": [
                {
                  "id": "memoire",
                  "nom": "Mémoire",
                  "phrase": "Ce qu'on lui demande de retenir, une mémoire par personne.",
                  "icone": {
                    "forme": "trait",
                    "d": "M7 7h10v10H7z M10 10h4v4h-4z M10 4v3 M14 4v3 M10 17v3 M14 17v3 M4 10h3 M4 14h3 M17 10h3 M17 14h3"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "retient",
                  "mode_mot": "Retient",
                  "etat": {
                    "statut": "ok",
                    "mot": "En service",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "Lecteurs",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Retient sur demande, répond aussitôt aux questions simples, oublie sur demande.",
                    "jamais": "La mémoire d'une personne n'est jamais lue pour une autre.",
                    "donnees": "À la maison.",
                    "acces": "Chacun la sienne ; la mémoire de la famille, pour tous.",
                    "essayer": [
                      "Retiens que la clé du garage est dans le tiroir de l'entrée",
                      "Qu'est-ce que je t'ai demandé de retenir ?"
                    ]
                  }
                },
                {
                  "id": "documents",
                  "nom": "Documents",
                  "phrase": "Les documents rangés dans Paperless : Alfred et Hermès y cherchent, même par le sens.",
                  "icone": {
                    "forme": "marque",
                    "d": "M6.338 23.028c-.117-.56-.353-1.678-.382-1.678-4.977-2.975-4.388-8.128-2.739-11.073.353 3.71 6.92 6.273 3.092 10.808-.03.059.177.765.353 1.413.766-1.296 1.915-2.856 1.856-3.004C3.806 8.01 18.53 7.126 21.592 0c1.385 6.89-.706 17.55-12.544 20.26-.06.03-2.15 3.71-2.238 3.74 0-.059-.884-.03-.766-.324.059-.177.177-.412.294-.648zm-.147-2.768c1.502-1.737-.265-4.712-1.325-5.683 1.796 3.092 1.679 4.888 1.325 5.683z"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "lit_range",
                  "mode_mot": "Lit et range",
                  "etat": {
                    "statut": "ok",
                    "mot": "En service",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "Paperless",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      },
                      {
                        "nom": "Paperless-GPT",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": "http://documents.example:8000",
                  "fiche": {
                    "fait": "Range ce qu'on dépose, retrouve un document par ses mots ou par son sens, le résume.",
                    "jamais": "Ne montre pas les documents d'une personne à une autre ; rien n'est effacé.",
                    "donnees": "À la maison (Paperless).",
                    "acces": "Chacun ses documents ; ceux de la maison, pour la famille.",
                    "essayer": [
                      "Ai-je un document pour demain ?",
                      "Résume-moi le dernier document que j'ai déposé"
                    ]
                  }
                },
                {
                  "id": "emails",
                  "nom": "E-mails",
                  "phrase": "Lit les e-mails reçus pour en garder l'essentiel ; n'écrit jamais.",
                  "icone": {
                    "forme": "marque",
                    "d": "m15.24 8.998 3.656-3.073v15.81H2.482C1.11 21.735 0 20.609 0 19.223V6.944l7.58 6.38a2.186 2.186 0 0 0 2.871-.042l4.792-4.284h-.003zm-5.456 3.538 1.809-1.616a2.438 2.438 0 0 1-1.178-.533L.905 2.395A.552.552 0 0 0 0 2.826v2.811l8.226 6.923a1.186 1.186 0 0 0 1.558-.024zM23.871 2.463a.551.551 0 0 0-.776-.068l-3.199 2.688v16.653h1.623c1.371 0 2.481-1.127 2.481-2.513V2.824a.551.551 0 0 0-.129-.36z"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "lit",
                  "mode_mot": "Lit",
                  "etat": {
                    "statut": "ok",
                    "mot": "En service",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "E-mails (lecteur)",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      },
                      {
                        "nom": "E-mails : aucune écriture",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Lit les e-mails reçus (expéditeur, résumé, montant, échéance) et range les PDF utiles dans Paperless.",
                    "jamais": "N'envoie, ne déplace et n'efface jamais un e-mail : vérifié chaque nuit.",
                    "donnees": "Lus à la maison, par un relais en lecture seule.",
                    "acces": "Le titulaire de la boîte seulement.",
                    "essayer": [
                      "Quels e-mails aujourd'hui ?",
                      "Ai-je reçu quelque chose du garage ?"
                    ]
                  }
                },
                {
                  "id": "agenda",
                  "nom": "Agenda",
                  "phrase": "Les rendez-vous, lus par Home Assistant.",
                  "icone": {
                    "forme": "marque",
                    "d": "M15.172 14.818V21.85h-4.276v-1.147c0-.584.21-1.151.592-1.596l3.684-4.288zm-4.93 5.884c0-.741.266-1.46.75-2.022l4.673-5.32c.522-.591 1.524-.92 2.262-.92h.967V7.007a1.919 1.919 0 0 0-1.928-1.914H0v14.295c0 1.36 1.11 2.462 2.482 2.462h7.76v-1.147zM18.8 5.197c.483.485.749 1.128.747 1.81v5.434H24V4.613c0-1.36-1.11-2.462-2.482-2.462H2.482A2.473 2.473 0 0 0 .006 4.438h16.96c.694 0 1.345.27 1.834.76zm.34 14.742c.817 0 1.45-.451 1.45-1.136a.953.953 0 0 0-.79-.971v-.013a.962.962 0 0 0 .485-.346.944.944 0 0 0 .185-.565c0-.632-.549-1.081-1.343-1.081-.99 0-1.384.712-1.415 1.21h.843a.54.54 0 0 1 .577-.495c.318 0 .549.196.549.48 0 .283-.213.473-.732.473h-.3v.713h.346c.536 0 .807.176.807.492s-.26.532-.655.532a.673.673 0 0 1-.686-.51h-.873c.063.733.683 1.222 1.551 1.217zm2-3.39v.806l.79-.532v3.06h.82v-3.988h-.635l-.974.655z"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "lit",
                  "mode_mot": "Lit",
                  "etat": {
                    "statut": "ok",
                    "mot": "En service",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "Home Assistant",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Dit ce qui est prévu aujourd'hui, demain ou à une date.",
                    "jamais": "Ne crée ni ne modifie aucun rendez-vous.",
                    "donnees": "Lu à la maison par Home Assistant.",
                    "acces": "Toute la famille.",
                    "essayer": [
                      "Qu'est-ce que j'ai demain ?"
                    ]
                  }
                },
                {
                  "id": "web",
                  "nom": "Recherche web",
                  "phrase": "Cherche sur Internet, sans compte ni pistage.",
                  "icone": {
                    "forme": "marque",
                    "d": "m13.716 17.261 6.873 6.582L24 20.282l-6.824-6.536a9.11 9.11 0 0 0 1.143-4.43c0-5.055-4.105-9.159-9.16-9.159S0 4.261 0 9.316c0 5.055 4.104 9.159 9.159 9.159a9.11 9.11 0 0 0 4.557-1.214ZM9.159 2.773a6.546 6.546 0 0 1 6.543 6.543 6.545 6.545 0 0 1-6.543 6.542 6.545 6.545 0 0 1-6.542-6.542 6.545 6.545 0 0 1 6.542-6.543ZM7.26 5.713a4.065 4.065 0 0 1 4.744.747 4.064 4.064 0 0 1 .707 4.749l1.157.611a5.376 5.376 0 0 0-.935-6.282 5.377 5.377 0 0 0-6.274-.987l.601 1.162Z"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "cherche",
                  "mode_mot": "Cherche",
                  "etat": {
                    "statut": "eteint",
                    "mot": "En veille · PC éteint",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "SearXNG (desktop)",
                        "statut": "eteint",
                        "mot": "En veille · PC éteint",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": "http://recherche.example:8888",
                  "fiche": {
                    "fait": "Cherche quand on commence par « cherche… » et résume ce qu'il trouve.",
                    "jamais": "N'agit jamais sur la maison après une recherche.",
                    "donnees": "La question part aux moteurs de recherche, sans compte.",
                    "acces": "Toute la famille.",
                    "essayer": [
                      "Cherche la recette du gâteau aux noix"
                    ]
                  }
                }
              ]
            },
            {
              "nom": "Agents",
              "connecteurs": [
                {
                  "id": "hermes",
                  "nom": "Hermès",
                  "phrase": "Le cabinet : les questions longues, croiser documents et e-mails.",
                  "icone": {
                    "forme": "trait",
                    "d": "M12 3v18 M12 7C10 5 7 4.5 4 5.5c2 1 5 2 8 3 M12 7c2-2 5-2.5 8-1.5-2 1-5 2-8 3 M9 12c2 1.6 4 1.6 6 0 M9 16c2 1.6 4 1.6 6 0"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "lit",
                  "mode_mot": "Lit",
                  "etat": {
                    "statut": "ok",
                    "mot": "En service",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "Hermes",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      },
                      {
                        "nom": "Lecteurs",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      },
                      {
                        "nom": "Cage d'Hermes",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Prend les questions qui demandent de lire et de croiser ; Alfred lui passe la main de lui-même.",
                    "jamais": "Ne commande jamais rien dans la maison (il peut seulement en lire l'état) ; enfermé dans une cage vérifiée chaque nuit.",
                    "donnees": "À la maison, sur une machine isolée.",
                    "acces": "Chacun son profil et sa mémoire.",
                    "essayer": [
                      "Compare les deux offres de toiture"
                    ]
                  }
                },
                {
                  "id": "claude",
                  "nom": "Claude",
                  "phrase": "Seulement quand on dit « demande à Claude ».",
                  "icone": {
                    "forme": "marque",
                    "d": "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"
                  },
                  "lieu": "cloud",
                  "lieu_mot": "Internet",
                  "mode": "lit",
                  "mode_mot": "Lit",
                  "etat": {
                    "statut": "demande",
                    "mot": "À la demande",
                    "depuis": null,
                    "services": []
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Répond à la question posée, quand on le demande explicitement.",
                    "jamais": "N'a aucun accès à la maison ni à la mémoire.",
                    "donnees": "La question part chez Anthropic, sur Internet.",
                    "acces": "Toute la famille, sur demande.",
                    "essayer": [
                      "Demande à Claude de m'expliquer la facture d'électricité"
                    ]
                  }
                }
              ]
            },
            {
              "nom": "Surveillance",
              "connecteurs": [
                {
                  "id": "kuma",
                  "nom": "Uptime Kuma",
                  "phrase": "Surveille chaque service, jour et nuit.",
                  "icone": {
                    "forme": "marque",
                    "d": "M11.759.955c-4.071 0-7.93 2.265-10.06 5.774l-.16.263-.116.284c-1.81 4.44-2.188 9.118.621 12.459 2.67 3.174 6.221 3.328 9.477 3.308 3.256-.02 6.323-.482 8.995-2.032C22.75 19.714 24 16.917 24 14.53c0-2.388-.724-4.698-1.882-7.343l-.112-.257-.148-.238C19.683 3.2 15.83.955 11.758.955Zm0 3.868c2.919 0 5.19 1.305 6.816 3.914 2.076 4.747 2.076 7.724 0 8.929-3.116 1.808-11.234 2.359-13.57-.42-1.558-1.853-1.558-4.69 0-8.51 1.584-2.608 3.835-3.913 6.754-3.913z"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "surveille",
                  "mode_mot": "Surveille",
                  "etat": {
                    "statut": "ok",
                    "mot": "En service",
                    "depuis": null,
                    "services": []
                  },
                  "lien": "http://surveillance.example:3001",
                  "fiche": {
                    "fait": "Vérifie chaque service en continu ; ses mesures donnent les pastilles et l'état de chaque carte.",
                    "jamais": "N'agit sur rien.",
                    "donnees": "À la maison.",
                    "acces": "Les pastilles pour tous ; le détail pour l'administrateur.",
                    "essayer": []
                  }
                },
                {
                  "id": "nuit",
                  "nom": "Revue de nuit",
                  "phrase": "Chaque nuit : bancs d'essai, sauvegardes et contrôles, sans lumière ni son.",
                  "icone": {
                    "forme": "trait",
                    "d": "M19 14.5A7.5 7.5 0 1 1 9.5 5a6 6 0 0 0 9.5 9.5z M15 4l.6 1.4L17 6l-1.4.6L15 8l-.6-1.4L13 6l1.4-.6z"
                  },
                  "lieu": "local",
                  "lieu_mot": "À la maison",
                  "mode": "verifie",
                  "mode_mot": "Vérifie",
                  "etat": {
                    "statut": "ok",
                    "mot": "En service",
                    "depuis": "2026-10-28 06:00:00",
                    "services": [
                      {
                        "nom": "Revue de nuit",
                        "statut": "ok",
                        "mot": "En service",
                        "depuis": "2026-10-28 06:00:00",
                        "message": ""
                      }
                    ]
                  },
                  "lien": null,
                  "fiche": {
                    "fait": "Teste Alfred, vérifie les sauvegardes et la cage d'Hermès, puis envoie un résumé.",
                    "jamais": "N'allume rien et ne fait aucun bruit la nuit.",
                    "donnees": "À la maison.",
                    "acces": "Le résumé, pour l'administrateur.",
                    "essayer": []
                  }
                }
              ]
            }
          ],
          "veille": {
            "texte": "Le PC du bureau est éteint : modèle d'Alfred, écoute, voix d'Alfred et recherche web en veille, c'est normal. Toujours là : Home Assistant, alertes vitales, garde, mémoire, documents, e-mails, agenda, Hermès, Uptime Kuma et revue de nuit."
          },
          "historique": "http://surveillance.example:3001/status/alfred"
        }
        """#.utf8)
}
