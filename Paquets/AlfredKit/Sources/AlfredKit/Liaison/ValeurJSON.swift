import Foundation

/// Une valeur JSON quelconque : les attributs des entités et les arguments des outils n'ont pas de forme fixe.
public enum ValeurJSON: Sendable, Equatable, Hashable {
    case nul
    case booleen(Bool)
    case nombre(Double)
    case texte(String)
    case liste([ValeurJSON])
    case objet([String: ValeurJSON])

    public subscript(cle: String) -> ValeurJSON? {
        if case .objet(let o) = self { return o[cle] }
        return nil
    }

    public var texte: String? {
        if case .texte(let t) = self { return t }
        return nil
    }
    public var booleen: Bool? {
        if case .booleen(let b) = self { return b }
        return nil
    }
    public var nombre: Double? {
        if case .nombre(let n) = self { return n }
        return nil
    }
    public var liste: [ValeurJSON]? {
        if case .liste(let l) = self { return l }
        return nil
    }
    public var objet: [String: ValeurJSON]? {
        if case .objet(let o) = self { return o }
        return nil
    }
    public var estNul: Bool {
        if case .nul = self { return true }
        return false
    }

    /// Un entier exact (les identifiants de HA), jamais un nombre à virgule arrondi en douce.
    public var entier: Int? {
        guard case .nombre(let n) = self, n.rounded() == n, abs(n) < 9.0e15 else { return nil }
        return Int(n)
    }
}

extension ValeurJSON: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .nul
        } else if let b = try? c.decode(Bool.self) {
            self = .booleen(b)
        } else if let n = try? c.decode(Double.self) {
            self = .nombre(n)
        } else if let t = try? c.decode(String.self) {
            self = .texte(t)
        } else if let l = try? c.decode([ValeurJSON].self) {
            self = .liste(l)
        } else if let o = try? c.decode([String: ValeurJSON].self) {
            self = .objet(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "valeur JSON illisible")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .nul: try c.encodeNil()
        case .booleen(let b): try c.encode(b)
        case .nombre(let n):
            if n.rounded() == n, abs(n) < 9.0e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case .texte(let t): try c.encode(t)
        case .liste(let l): try c.encode(l)
        case .objet(let o): try c.encode(o)
        }
    }
}

extension ValeurJSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral, ExpressibleByFloatLiteral
{
    public init(stringLiteral v: String) { self = .texte(v) }
    public init(integerLiteral v: Int) { self = .nombre(Double(v)) }
    public init(floatLiteral v: Double) { self = .nombre(v) }
    public init(booleanLiteral v: Bool) { self = .booleen(v) }
    public init(arrayLiteral v: ValeurJSON...) { self = .liste(v) }
    public init(dictionaryLiteral v: (String, ValeurJSON)...) {
        self = .objet(Dictionary(v, uniquingKeysWith: { _, b in b }))
    }
    public init(nilLiteral: ()) { self = .nul }
}

extension ValeurJSON {
    /// Lit un texte JSON ; nil s'il est illisible (un message malformé est ignoré, comme dans la console).
    public static func lire(_ texte: String) -> ValeurJSON? {
        try? JSONDecoder().decode(ValeurJSON.self, from: Data(texte.utf8))
    }

    /// Texte JSON compact, clés triées (sortie stable pour les tests).
    public func enTexte() -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let d = try? e.encode(self) else { return "null" }
        return String(decoding: d, as: UTF8.self)
    }
}
