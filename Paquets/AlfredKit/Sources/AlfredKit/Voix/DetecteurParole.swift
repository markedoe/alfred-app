import Foundation

/// Détection du début et de la fin de la parole. HA annonce `requires_external_vad: true` : il ne coupe pas tout
/// seul, c'est au client de décider.
///
/// Porté de la console (`onAudio`), avec ses réglages mesurés :
/// - **plancher de bruit glissant** : il descend aussitôt et remonte très lentement, et ne monte pas pendant la parole
///   (un étalonnage fixe calculait son seuil sur la voix de qui parlait tout de suite) ;
/// - **seuil** = max(plancher × 6, 0,035), relâché à 55 % (hystérésis) ;
/// - **4 trames de suite** au-dessus du seuil pour compter (un bruit à 0,0209 contre 0,0200 ouvrait et fermait un tour) ;
/// - **en conversation**, un tour ne s'ouvre qu'après 200 ms de son (plus courte vraie phrase : 254 ms ; un bruit qui
///   a fait inventer une phrase à Whisper : 151 ms) ;
/// - **fin** : 1 s de silence après la parole (et 1,5 s de tour au moins), 15 s au plus ; hors conversation, 10 s sans
///   parole ferment le tour.
///
/// Le temps est compté en TEMPS AUDIO (trames de 128 échantillons à 16 kHz = 8 ms), exact même si l'audio arrive par
/// paquets. Toute taille de paquet est découpée en trames de 128.
public struct DetecteurParole: Sendable {
    public struct Reglages: Sendable, Equatable {
        public var seuilMinimal: Float = 0.035
        public var facteurPlancher: Float = 6
        public var relachement: Float = 0.55
        public var tramesAttaque = 4
        public var sonMinimalMs = 200.0
        public var silenceFinMs = 1000.0
        public var dureeMinimaleMs = 1500.0
        public var dureeMaximaleMs = 15000.0
        public var sansParoleMs = 10000.0
        public var silenceCandidatMs = 300.0
        public var candidatMaximalMs = 2000.0
        public init() {}
    }

    public enum Raison: String, Sendable, Equatable {
        case silenceApresParole = "silence apres parole"
        case dureeMaximale = "duree maximale"
        case aucuneParole = "aucune parole detectee"
    }

    public enum Decision: Sendable, Equatable {
        /// Attaque de la parole (en conversation) ; `depuisMs` = temps audio où le son a commencé.
        case attaque(depuisMs: Double)
        case fin(Raison)
        /// Un son trop court pour ouvrir un tour.
        case bruitIgnore
    }

    public static let echantillonsParTrame = 128
    public static let msParTrame = 8.0

    public let reglages: Reglages
    /// Conversation continue : le tour attend une vraie attaque ; sinon (appui), il est ouvert dès le départ.
    public let conversation: Bool

    public private(set) var plancher: Float = 1
    public private(set) var crete: Float = 0
    public private(set) var parole = false
    public private(set) var termine = false
    public private(set) var bruitsIgnores = 0
    private var dernierFort = 0.0
    private var sequenceForte = 0
    private var candidat = 0
    private var candidatDernier = 0
    private var trames = 0
    private var debutTour = 0.0
    private var reste: [Float] = []

    /// `plancher` : celui du tour précédent de la même conversation (la console le garde d'un tour à l'autre).
    public init(conversation: Bool, plancher: Float = 1, reglages: Reglages = Reglages()) {
        self.conversation = conversation
        self.reglages = reglages
        self.plancher = plancher
    }

    /// La marge juste après une réponse d'Alfred (1 s dans la console) : le bruit de fond se mesure, rien n'est
    /// détecté et le temps du tour ne court pas (la fin de la voix d'Alfred ne doit pas ouvrir un tour).
    public mutating func mesurer(_ echantillons: [Float]) {
        let n = Self.echantillonsParTrame
        var i = 0
        while echantillons.count - i >= n {
            var somme: Float = 0
            for k in i..<(i + n) { somme += echantillons[k] * echantillons[k] }
            let rms = (somme / Float(n)).squareRoot()
            plancher = rms < plancher ? rms : plancher * 0.9997 + rms * 0.0003
            i += n
        }
    }

    /// Temps audio écoulé depuis le début de la capture.
    public var tempsMs: Double { Double(trames) * Self.msParTrame }

    /// Échantillons flottants (-1…1) ; rend les décisions prises, dans l'ordre. Rien après une fin.
    public mutating func analyser(_ echantillons: [Float]) -> [Decision] {
        var decisions: [Decision] = []
        reste.append(contentsOf: echantillons)
        let n = Self.echantillonsParTrame
        var i = 0
        while reste.count - i >= n, !termine {
            var somme: Float = 0
            for k in i..<(i + n) { somme += reste[k] * reste[k] }
            decisions += trame(rms: (somme / Float(n)).squareRoot())
            i += n
        }
        reste.removeFirst(min(i, reste.count))
        if termine { reste = [] }
        return decisions
    }

    /// Une trame de 8 ms, par son niveau (RMS).
    public mutating func trame(rms: Float) -> [Decision] {
        guard !termine else { return [] }
        var decisions: [Decision] = []
        let r = reglages
        let parleEnCours = parole || candidat != 0
        // le plancher ne monte pas pendant la parole (sinon la fin d'une phrase passait pour du silence)
        plancher = rms < plancher ? rms : (parleEnCours ? plancher : plancher * 0.9997 + rms * 0.0003)
        if rms > crete { crete = rms }
        let seuil = max(plancher * r.facteurPlancher, r.seuilMinimal)
        let relache = seuil * r.relachement
        trames += 1
        let maintenant = tempsMs
        let ms = Self.msParTrame

        if rms > seuil {
            sequenceForte += 1
            if sequenceForte >= r.tramesAttaque {
                if parole {
                    dernierFort = maintenant
                } else if !conversation {
                    parole = true
                    dernierFort = maintenant
                } else {
                    if candidat == 0 { candidat = trames - (r.tramesAttaque - 1) }
                    candidatDernier = trames
                    let duree = Double(trames - candidat + 1) * ms
                    if duree >= r.sonMinimalMs {
                        let debut = maintenant - duree
                        decisions.append(.attaque(depuisMs: debut))
                        debutTour = debut
                        parole = true
                        dernierFort = maintenant
                        candidat = 0
                    }
                }
            }
        } else {
            sequenceForte = 0
            if rms > relache {
                if parole { dernierFort = maintenant } else if candidat != 0 { candidatDernier = trames }
            }
            if candidat != 0 && Double(trames - candidatDernier) * ms > r.silenceCandidatMs {
                candidat = 0
                bruitsIgnores += 1
                decisions.append(.bruitIgnore)
            }
        }
        // un murmure qui n'atteint jamais le son minimal ne garde pas le tour ouvert plus de 2 s
        if candidat != 0 && !parole && Double(trames - candidat) * ms > r.candidatMaximalMs {
            candidat = 0
            bruitsIgnores += 1
            decisions.append(.bruitIgnore)
        }

        let duTour = maintenant - debutTour
        if parole && maintenant - dernierFort > r.silenceFinMs && duTour > r.dureeMinimaleMs {
            decisions.append(finir(.silenceApresParole))
        } else if parole && duTour > r.dureeMaximaleMs {
            decisions.append(finir(.dureeMaximale))
        } else if !conversation && duTour > r.dureeMaximaleMs {
            decisions.append(finir(.dureeMaximale))
        } else if !conversation && !parole && duTour > r.sansParoleMs {
            decisions.append(finir(.aucuneParole))
        }
        return decisions
    }

    private mutating func finir(_ raison: Raison) -> Decision {
        termine = true
        return .fin(raison)
    }
}

/// Les dernières trames avant l'attaque (≈ 0,48 s) : elles contiennent le début du premier mot.
/// En conversation, rien n'est envoyé avant l'attaque ; à l'attaque, l'amorce part en tête de la phrase.
public struct Amorce: Sendable {
    public let capacite: Int
    public private(set) var morceaux: [Data] = []
    private var octets = 0

    /// 60 trames de 128 échantillons de 16 bits (la console : `PREROLL_FRAMES`).
    public init(capacite: Int = 60 * DetecteurParole.echantillonsParTrame * 2) {
        self.capacite = capacite
    }

    public mutating func ajouter(_ d: Data) {
        morceaux.append(d)
        octets += d.count
        while octets - (morceaux.first?.count ?? 0) >= capacite, morceaux.count > 1 {
            octets -= morceaux.removeFirst().count
        }
    }

    public mutating func prendre() -> [Data] {
        defer {
            morceaux = []
            octets = 0
        }
        return morceaux
    }
}

/// Conversion des échantillons flottants en PCM 16 bits petit-boutiste (ce que HA attend).
public enum PCM {
    public static func enOctets(_ echantillons: [Float]) -> Data {
        let valeurs = echantillons.map { s -> Int16 in
            let c = max(-1, min(1, s))
            return Int16(c < 0 ? c * 32768 : c * 32767).littleEndian
        }
        return valeurs.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
