import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Système XP (seuils de niveau)

enum XPSystem {
    /// XP gagnée selon les règles de jeu
    static let xpPerParticipation = 500
    static let xpPerWin = 1500
    static let xpPerGoal = 500
    static let skillPointsPerLevel = 5
    static let mvpBonusXP = 250

    /// Seuils d'XP requis pour chaque niveau (index 0 = niveau 1).
    static let levelThresholds: [Int] = [
        0, 300, 900, 1800, 3000, 4200, 4500, 5850, 7200, 9000, 9800, 10300, 11250,
        12250, 13550, 14900, 16150, 18100, 20050, 22000, 22750, 23500, 24250, 25750,
        27250, 28750, 30250, 32500, 34750, 37000, 38000, 39000, 40000, 42000, 44000,
        46000, 48000, 51000, 54000, 57000, 58150, 59300, 60450, 62750, 65050, 67350,
        69650, 73100, 76550, 80000, 81550, 83100, 84650, 87750, 90850, 93950, 97050,
        101700, 106350, 111000, 113050, 115100, 117200, 121250, 125350, 129450, 133550,
        139700, 145850, 152000, 154300, 156600, 158900, 163500, 168100, 172700, 177300,
        184200, 191100, 198000, 200850, 203700, 206550, 212250, 217950, 223650, 229350,
        237900, 246450, 255000, 259350, 263700, 268050, 276750, 285450, 294150, 302850,
        315900, 328950, 342000
    ]

    static func level(forXP xp: Int) -> Int {
        var level = 1
        for (index, threshold) in levelThresholds.enumerated() where xp >= threshold {
            level = index + 1
        }
        return level
    }

    /// Progression 0...1 dans le niveau courant.
    static func progress(forXP xp: Int) -> Double {
        let level = level(forXP: xp)
        guard level < levelThresholds.count else { return 1 }
        let current = levelThresholds[level - 1]
        let next = levelThresholds[level]
        guard next > current else { return 1 }
        return Double(xp - current) / Double(next - current)
    }

    /// XP du dernier niveau : au-delà, tout gain est ignoré (saison terminée).
    static var maxXP: Int { levelThresholds.last ?? 0 }

    static func xpToNextLevel(forXP xp: Int) -> Int {
        let level = level(forXP: xp)
        guard level < levelThresholds.count else { return 0 }
        return levelThresholds[level] - xp
    }

    static func xpGain(won: Bool, goals: Int) -> Int {
        xpPerParticipation + (won ? xpPerWin : 0) + goals * xpPerGoal
    }
}

// MARK: - Système Classé (PL) — séparé de l'XP, mesure le niveau de jeu réel
// plutôt que l'assiduité. 12 divisions calquées sur la pyramide du foot
// amateur français, pour que ça parle à un joueur français plutôt qu'un
// nom de ligue inventé.

enum RankedDivision: String, CaseIterable, Codable, Comparable {
    case district3, district2, district1
    case regional3, regional2, regional1
    case national3, national2, national1
    case ligue3, ligue2, ligue1

    /// Ordre de progression, du plus bas au plus haut — sert aussi de
    /// base à Comparable pour les comparaisons de division.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: RankedDivision, rhs: RankedDivision) -> Bool { lhs.order < rhs.order }

    var displayName: String {
        switch self {
        case .district3: return "District 3"
        case .district2: return "District 2"
        case .district1: return "District 1"
        case .regional3: return "Régional 3"
        case .regional2: return "Régional 2"
        case .regional1: return "Régional 1"
        case .national3: return "National 3"
        case .national2: return "National 2"
        case .national1: return "National 1"
        case .ligue3:    return "Ligue 3"
        case .ligue2:    return "Ligue 2"
        case .ligue1:    return "Ligue 1"
        }
    }

    /// Étage de la pyramide (0=District, 1=Régional, 2=National, 3=Ligue) —
    /// sert à grouper visuellement les 12 divisions par 3 sur la carte.
    var tier: Int { order / 3 }

    /// Code court affiché sur la carte joueur (ex: "D3", "R1", "L1").
    var shortCode: String {
        switch self {
        case .district3: return "D3"
        case .district2: return "D2"
        case .district1: return "D1"
        case .regional3: return "R3"
        case .regional2: return "R2"
        case .regional1: return "R1"
        case .national3: return "N3"
        case .national2: return "N2"
        case .national1: return "N1"
        case .ligue3:    return "L3"
        case .ligue2:    return "L2"
        case .ligue1:    return "L1"
        }
    }

    /// Couleur du palier : bronze (District), argent (Régional), or (National), diamant (Ligue).
    var tierColors: [Color] {
        switch tier {
        case 0: return [Color(hex: "CD7F32"), Color(hex: "8B5A2B")]
        case 1: return [Color(hex: "E0E0E0"), Color(hex: "9C9C9C")]
        case 2: return [Color(hex: "FFD700"), Color(hex: "B8860B")]
        default: return [Color(hex: "B9F2FF"), Color(hex: "3FA9D8")]
        }
    }

    var next: RankedDivision? {
        let all = Self.allCases
        let i = order + 1
        return i < all.count ? all[i] : nil
    }

    var previous: RankedDivision? {
        let i = order - 1
        return i >= 0 ? Self.allCases[i] : nil
    }
}

enum RankedSystem {
    static let promotionThreshold = 100    // PL requis pour monter de division
    static let relegationFloor = 0         // en dessous : rétrogradation à la prochaine défaite
    static let relegationRestartPL = 50    // PL de redémarrage après rétrogradation
    static let placementMatchesRequired = 5
    /// Plafond de placement : personne ne peut débuter plus haut que ça,
    /// même avec 5 victoires sur 5 en placement.
    static let placementCeiling: RankedDivision = .district1

    static let winPL = 15
    static let lossPL = -15
    static let lossPLWithGoals = -10       // amorti si 2+ buts marqués malgré la défaite
    static let drawPL = 2
    static let perGoalPL = 1
    static let maxGoalBonusPL = 5
    static let mvpBonusPL = 10

    /// PL gagnés/perdus pour un match Classé donné (hors placement).
    static func plChange(won: Bool, drawn: Bool, goals: Int) -> Int {
        let goalBonus = min(goals, maxGoalBonusPL) * perGoalPL
        if won { return winPL + goalBonus }
        if drawn { return drawPL + goalBonus }
        // Défaite : amortie si la perf individuelle (buts) est bonne malgré tout.
        let base = goals >= 2 ? lossPLWithGoals : lossPL
        return base + goalBonus
    }

    /// Division de départ à l'issue des 5 games de placement, plafonnée.
    static func placementResult(wins: Int) -> RankedDivision {
        // 0-1 victoire -> District 3, 2 -> District 2, 3+ -> District 1 (plafond)
        switch wins {
        case 0, 1: return .district3
        case 2:    return .district2
        default:   return placementCeiling
        }
    }
}

// MARK: - Sous-attributs (24 sous-stats -> 6 stats principales)

struct SubAttributes: Codable, Equatable {
    // VIT
    var acceleration: Int = 60
    var vitesseMax: Int = 60
    // TIR
    var placement: Int = 60
    var finition: Int = 60
    var puissanceFrappe: Int = 60
    var tirsDeLoin: Int = 60
    var volees: Int = 60
    var penaltys: Int = 60
    // PAS
    var vision: Int = 60
    var centre: Int = 60
    var passesCourtes: Int = 60
    var passesLongues: Int = 60
    // DRI
    var agilite: Int = 60
    var equilibre: Int = 60
    var controleBalle: Int = 60
    var dribble: Int = 60
    var calme: Int = 60
    // DEF
    var interceptions: Int = 60
    var tacleDebout: Int = 60
    var tacleGlisse: Int = 60
    // PHY
    var force: Int = 60
    var endurance: Int = 60
    var detente: Int = 60
    var agressivite: Int = 60

    static let base = SubAttributes()

    // MARK: Stats principales (moyennes)

    var vit: Int { avg([acceleration, vitesseMax]) }
    var tir: Int { avg([placement, finition, puissanceFrappe, tirsDeLoin, volees, penaltys]) }
    var pas: Int { avg([vision, centre, passesCourtes, passesLongues]) }
    var dri: Int { avg([agilite, equilibre, controleBalle, dribble, calme]) }
    var def: Int { avg([interceptions, tacleDebout, tacleGlisse]) }
    var phy: Int { avg([force, endurance, detente, agressivite]) }

    var main: PlayerAttributes {
        PlayerAttributes(vit: vit, tir: tir, pas: pas, dri: dri, def: def, phy: phy)
    }

    var overall: Int { avg([vit, tir, pas, dri, def, phy]) }

    private func avg(_ values: [Int]) -> Int {
        values.isEmpty ? 0 : values.reduce(0, +) / values.count
    }

    // MARK: Accès générique par clé (pour l'UI d'allocation)

    static let groups: [(main: String, subs: [(key: String, label: String)])] = [
        ("VIT", [("acceleration", "Accélération"), ("vitesseMax", "Vitesse max")]),
        ("TIR", [("placement", "Placement"), ("finition", "Finition"), ("puissanceFrappe", "Puissance de frappe"),
                 ("tirsDeLoin", "Tirs de loin"), ("volees", "Volées"), ("penaltys", "Pénaltys")]),
        ("PAS", [("vision", "Vision"), ("centre", "Centre"), ("passesCourtes", "Passes courtes"),
                 ("passesLongues", "Passes longues")]),
        ("DRI", [("agilite", "Agilité"), ("equilibre", "Équilibre"), ("controleBalle", "Contrôle de balle"),
                 ("dribble", "Dribble"), ("calme", "Calme")]),
        ("DEF", [("interceptions", "Interceptions"), ("tacleDebout", "Tacle debout"), ("tacleGlisse", "Tacle glissé")]),
        ("PHY", [("force", "Force"), ("endurance", "Endurance"), ("detente", "Détente"), ("agressivite", "Agressivité")])
    ]

    func value(for key: String) -> Int {
        switch key {
        case "acceleration": return acceleration
        case "vitesseMax": return vitesseMax
        case "placement": return placement
        case "finition": return finition
        case "puissanceFrappe": return puissanceFrappe
        case "tirsDeLoin": return tirsDeLoin
        case "volees": return volees
        case "penaltys": return penaltys
        case "vision": return vision
        case "centre": return centre
        case "passesCourtes": return passesCourtes
        case "passesLongues": return passesLongues
        case "agilite": return agilite
        case "equilibre": return equilibre
        case "controleBalle": return controleBalle
        case "dribble": return dribble
        case "calme": return calme
        case "interceptions": return interceptions
        case "tacleDebout": return tacleDebout
        case "tacleGlisse": return tacleGlisse
        case "force": return force
        case "endurance": return endurance
        case "detente": return detente
        case "agressivite": return agressivite
        default: return 0
        }
    }

    mutating func add(_ points: Int, to key: String) {
        let newValue = min(99, value(for: key) + points)
        switch key {
        case "acceleration": acceleration = newValue
        case "vitesseMax": vitesseMax = newValue
        case "placement": placement = newValue
        case "finition": finition = newValue
        case "puissanceFrappe": puissanceFrappe = newValue
        case "tirsDeLoin": tirsDeLoin = newValue
        case "volees": volees = newValue
        case "penaltys": penaltys = newValue
        case "vision": vision = newValue
        case "centre": centre = newValue
        case "passesCourtes": passesCourtes = newValue
        case "passesLongues": passesLongues = newValue
        case "agilite": agilite = newValue
        case "equilibre": equilibre = newValue
        case "controleBalle": controleBalle = newValue
        case "dribble": dribble = newValue
        case "calme": calme = newValue
        case "interceptions": interceptions = newValue
        case "tacleDebout": tacleDebout = newValue
        case "tacleGlisse": tacleGlisse = newValue
        case "force": force = newValue
        case "endurance": endurance = newValue
        case "detente": detente = newValue
        case "agressivite": agressivite = newValue
        default: break
        }
    }

    var asDictionary: [String: Int] {
        SubAttributes.groups.flatMap(\.subs).reduce(into: [:]) { dict, sub in
            dict[sub.key] = value(for: sub.key)
        }
    }
}

// MARK: - Pied fort

enum StrongFoot: String, Codable, CaseIterable, Identifiable {
    case gauche = "Gauche"
    case droit = "Droit"
    case lesDeux = "Les deux"

    var id: String { rawValue }
}

// MARK: - Utilisateur

struct AppUser: Identifiable, Codable {
    @DocumentID var id: String?
    var pseudo: String
    var email: String
    var coins: Int
    var xp: Int
    var skillPoints: Int
    var position: PlayerPosition
    var attributes: PlayerAttributes      // legacy, conservé pour compat
    var friends: [String]
    var teamIds: [String]
    var createdAt: Date

    // Champs ajoutés après coup -> optionnels pour la compat des anciens comptes
    var ownedItems: [String]?
    var nickname: String?
    var matchesPlayed: Int?
    var goals: Int?
    var wins: Int?
    var draws: Int?
    var losses: Int?
    var subAttributes: SubAttributes?

    // Infos perso (dos de la carte)
    var heightCm: Int?
    var weightKg: Int?
    var favoriteTeam: String?
    var strongFoot: StrongFoot?
    var lastSeen: Date?
    var photoBase64: String? = nil  // LEGACY : ancien stockage, conservé en lecture pour compat
    var photoURL: String? = nil     // nouveau stockage : URL Firebase Storage (CDN, peu coûteux)
    var bestGoalsInMatch: Int? = nil
    var friendRequests: [String]? = nil   // uids des demandes d'ami reçues
    var title: String? = nil              // titre style League of Legends
    var pinnedFriends: [String]? = nil    // uids épinglés (meilleurs amis)
    var mutedFriends: [String]? = nil     // uids mis en sourdine (DMs)
    var fcmToken: String? = nil      // token FCM pour les notifications push
    var gender: String? = nil        // sexe choisi à l'inscription, non modifiable ensuite
    var pseudoLower: String? = nil   // pseudo en minuscules, pour la recherche insensible à la casse
    var matchesOrganized: Int? = nil
    var dismissedMatches: [String]? = nil  // ids des matchs clôturés masqués par l'utilisateur
    var blockedUsers: [String]? = nil      // uids bloqués par l'utilisateur      // matchs organisés (incrémenté à la création)
    var isPremium: Bool? = nil             // abonnement premium actif
    var premiumExpiresAt: Date? = nil      // date d'expiration de l'abonnement
    var city: String? = nil                // ville de résidence choisie à l'inscription — sert au classement Régional
    var activeSessionId: String? = nil     // identifiant de la session active — permet de forcer la déconnexion des autres appareils

    // ===== Système Classé (séparé de l'XP/carte) =====
    var rankedDivision: String? = nil      // nil = pas encore placé (games de placement à faire)
    var rankedPL: Int? = nil               // points dans la division actuelle (0-99)
    var rankedPlacementsPlayed: Int? = nil // 0 à 5
    var rankedPlacementWins: Int? = nil    // sert à calculer la division de départ

    // ===== Bilan de saison Classé (dos de la carte) =====
    var rankedWins: Int? = nil
    var rankedDraws: Int? = nil
    var rankedLosses: Int? = nil
    var bestDivisionReached: String? = nil // meilleure division jamais atteinte (rawValue RankedDivision)
    var currentStreakType: String? = nil   // "win" | "loss" — nil si pas de série en cours
    var currentStreakCount: Int? = nil
    var mvpCount: Int? = nil               // nombre de fois élu MVP (matchs Classé)

    // ===== Infos joueur (sheet séparée de la carte) =====
    var age: Int? = nil                    // optionnel, éditable dans le profil
    var reliabilitySum: Int? = nil         // somme des notes reçues (1-5 par vote)
    var reliabilityCount: Int? = nil       // nombre de votes reçus
    var clubIds: [String]? = nil           // clubs Classé dont ce joueur fait partie (max 3)
    var clubIdsValue: [String] { clubIds ?? [] }

    /// Accesseurs non-optionnels pratiques — les champs restent optionnels
    /// au stockage (comptes créés avant cette fonctionnalité), mais tout le
    /// reste du code peut lire des valeurs par défaut sûres.
    var rankedPLValue: Int { rankedPL ?? 0 }
    var rankedPlacementsPlayedValue: Int { rankedPlacementsPlayed ?? 0 }
    var rankedPlacementWinsValue: Int { rankedPlacementWins ?? 0 }
    var reliabilitySumValue: Int { reliabilitySum ?? 0 }
    var reliabilityCountValue: Int { reliabilityCount ?? 0 }
    var rankedWinsValue: Int { rankedWins ?? 0 }
    var rankedDrawsValue: Int { rankedDraws ?? 0 }
    var rankedLossesValue: Int { rankedLosses ?? 0 }
    var mvpCountValue: Int { mvpCount ?? 0 }
    var bestDivisionReachedEnum: RankedDivision? { bestDivisionReached.flatMap { RankedDivision(rawValue: $0) } }

    /// Description courte de la série en cours, ex: "3 victoires d'affilée".
    var streakDescription: String? {
        guard let type = currentStreakType, let count = currentStreakCount, count > 0 else { return nil }
        let word = type == "win" ? "victoire" : "défaite"
        return "\(count) \(word)\(count > 1 ? "s" : "") d'affilée"
    }

    /// Note moyenne de fiabilité, affichée seulement à partir de 5 votes
    /// pour éviter qu'un seul avis (positif ou négatif) ne fasse basculer
    /// l'affichage d'un compte encore récent.
    var reliabilityAverage: Double? {
        guard reliabilityCountValue >= 5 else { return nil }
        return Double(reliabilitySumValue) / Double(reliabilityCountValue)
    }

    /// Division actuelle sous forme typée, nil tant que le placement n'est pas terminé.
    var rankedDivisionEnum: RankedDivision? {
        rankedDivision.flatMap { RankedDivision(rawValue: $0) }
    }

    // MARK: Calculés

    /// Source de vérité des stats : sous-attributs si présents, sinon legacy.
    var subs: SubAttributes { subAttributes ?? .base }
    var displayAttributes: PlayerAttributes { subAttributes?.main ?? attributes }
    /// Générale affichée : les stats brutes, relevées par un plancher qui
    /// grimpe avec le niveau (≈40 au début, 74 au niveau 100), plafonnée à 99.
    var overall: Int {
        let base = displayAttributes.overall
        let levelFloor = 40 + Int((Double(level) * 0.34).rounded())
        return min(99, max(base, levelFloor))
    }

    var level: Int { XPSystem.level(forXP: xp) }
    var levelProgress: Double { XPSystem.progress(forXP: xp) }
    var xpToNext: Int { XPSystem.xpToNextLevel(forXP: xp) }

    /// Premium actif si le flag est vrai ET que la date d'expiration n'est pas dépassée.
    var hasPremium: Bool {
        guard isPremium == true else { return false }
        if let exp = premiumExpiresAt { return exp > Date() }
        return true
    }

    var owned: [String] { ownedItems ?? [] }
    var totalMatches: Int { matchesPlayed ?? 0 }
    var totalGoals: Int { goals ?? 0 }
    var totalWins: Int { wins ?? 0 }
    var totalDraws: Int { draws ?? 0 }
    var totalLosses: Int { losses ?? 0 }

    var goalsPerMatch: Double {
        totalMatches > 0 ? Double(totalGoals) / Double(totalMatches) : 0
    }

    var initials: String { String(pseudo.prefix(2)).uppercased() }

    var bestInOneMatch: Int { bestGoalsInMatch ?? 0 }
    var incomingRequests: [String] { friendRequests ?? [] }
    var blockedUids: [String] { blockedUsers ?? [] }
    func hasBlocked(_ uid: String?) -> Bool { uid != nil && blockedUids.contains(uid!) }

    var isOnlineRTDB: Bool? = nil  // miroir Realtime Database, fiable et instantané

    var isOnline: Bool {
        // Priorité au statut RTDB (mis à jour en temps réel au connect/
        // disconnect réel, via la Cloud Function miroir).
        if let rtdb = isOnlineRTDB { return rtdb }
        // Repli legacy pour les comptes pas encore migrés / avant déploiement
        // de la Cloud Function miroir.
        guard let lastSeen else { return false }
        return Date().timeIntervalSince(lastSeen) < 360
    }

    var levelTitle: String {
        switch level {
        case ..<3: return "Débutant"
        case ..<7: return "Amateur"
        case ..<11: return "Confirmé"
        case ..<16: return "Semi-Pro"
        case ..<21: return "Pro"
        default: return "Légende"
        }
    }

    static func new(uid: String, pseudo: String, email: String, city: String) -> AppUser {
        var user = AppUser(
            id: uid,
            pseudo: pseudo,
            email: email,
            coins: 20,
            xp: 0,
            skillPoints: 0,
            position: .mil,
            attributes: .base,
            friends: [],
            teamIds: [],
            createdAt: Date(),
            ownedItems: [],
            nickname: nil,
            matchesPlayed: 0,
            goals: 0,
            wins: 0,
            draws: 0,
            losses: 0,
            subAttributes: .base,
            heightCm: nil,
            weightKg: nil,
            favoriteTeam: nil,
            strongFoot: nil,
            lastSeen: Date()
        )
        user.city = city
        return user
    }
}

enum Gender: String, Codable, CaseIterable, Identifiable {
    case homme = "Homme"
    case femme = "Femme"
    case autre = "Autre"
    var id: String { rawValue }
}

enum PlayerPosition: String, Codable, CaseIterable, Identifiable {
    case gar = "GAR"
    case def = "DEF"
    case mil = "MIL"
    case att = "ATT"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gar: return "Gardien"
        case .def: return "Défenseur"
        case .mil: return "Milieu"
        case .att: return "Attaquant"
        }
    }
}

// MARK: - Attributs principaux (affichage carte)

struct PlayerAttributes: Codable, Equatable {
    var vit: Int
    var tir: Int
    var pas: Int
    var dri: Int
    var def: Int
    var phy: Int

    static let base = PlayerAttributes(vit: 60, tir: 60, pas: 60, dri: 60, def: 60, phy: 60)

    var overall: Int { (vit + tir + pas + dri + def + phy) / 6 }

    var all: [(key: String, value: Int)] {
        [("VIT", vit), ("TIR", tir), ("PAS", pas), ("DRI", dri), ("DEF", def), ("PHY", phy)]
    }
}

// MARK: - Match

enum MatchType: String, Codable, CaseIterable, Identifiable {
    case five = "5v5"
    case seven = "7v7"
    case eleven = "11v11"

    var id: String { rawValue }

    var maxPlayers: Int {
        switch self {
        case .five: return 10
        case .seven: return 14
        case .eleven: return 22
        }
    }

    var displayName: String {
        switch self {
        case .five: return "Five"
        case .seven: return "7v7"
        case .eleven: return "Foot"
        }
    }

    var subtitle: String {
        switch self {
        case .five: return "Match à 5 contre 5"
        case .seven: return "Le bon équilibre"
        case .eleven: return "Match classique"
        }
    }
}

enum MatchTag: String, Codable {
    case mixte
    case filles
}

enum MatchStatus: String, Codable {
    case open, played, cancelled
    case pendingValidation  // score soumis, en attente du vote des participants
    case contested          // 30%+ de contestation
}

struct Match: Identifiable, Codable {
    @DocumentID var id: String?
    var organizerId: String
    var organizerPseudo: String
    var type: MatchType
    var location: String
    var date: Date
    var maxPlayers: Int
    var participants: [String]
    var status: MatchStatus
    var teamId: String?
    var isPrivate: Bool?   // optionnel pour compat anciens matchs
    var tag: String? = nil // "mixte" ou "filles" ; absent = mixte (compat anciens matchs)
    var zone: String?      // zone géographique (ex : "Paris 15e")
    var createdAt: Date?   // pour le quota journalier
    var unavailable: [String]? = nil   // joueurs déclarés indisponibles (matchs d'équipe)
    var scoreA: Int? = nil             // score final équipe A (1re moitié des inscrits)
    var scoreB: Int? = nil             // score final équipe B (2e moitié)
    var scorers: [String: Int]? = nil  // uid -> buts marqués
    var slotAssignments: [String: Int]? = nil  // uid -> slot choisi sur la feuille
    var scoreSubmittedAt: Date? = nil            // timestamp de la soumission du score
    var validationVotes: [String: String]? = nil // uid -> "validate"|"contest" (cache rapide)
    var isRanked: Bool? = nil          // match Classé (PL) vs Normal (XP) — jamais les deux
    var isRankedMatch: Bool { isRanked ?? false }
    var mvpUid: String? = nil          // désigné à la clôture, majorité des votes MVP

    var isFull: Bool { participants.count >= maxPlayers }
    var isPrivateMatch: Bool { isPrivate ?? false }
    var isGirlsOnly: Bool { tag == MatchTag.filles.rawValue }
    var unavailableIds: [String] { unavailable ?? [] }

    /// Répartition terrain : slots choisis prioritaires, le reste comble
    /// dans l'ordre d'inscription. 1re moitié des slots = Équipe A.
    var halfSlots: Int { maxPlayers / 2 }

    /// Tableau de taille maxPlayers : occupant de chaque slot (nil = libre).
    var resolvedSlots: [String?] {
        var slots = [String?](repeating: nil, count: maxPlayers)
        let assignments = slotAssignments ?? [:]
        // 1. Les joueurs qui ont choisi leur place
        for uid in participants {
            if let slot = assignments[uid], slot >= 0, slot < maxPlayers, slots[slot] == nil {
                slots[slot] = uid
            }
        }
        // 2. Les autres comblent les premiers slots libres
        for uid in participants where !slots.contains(uid) {
            if let free = slots.firstIndex(of: nil) {
                slots[free] = uid
            }
        }
        return slots
    }

    var teamA: [String?] { Array(resolvedSlots.prefix(halfSlots)) }
    var teamB: [String?] { Array(resolvedSlots.dropFirst(halfSlots)) }

    func side(of uid: String) -> Int? {
        guard let slot = resolvedSlots.firstIndex(of: uid) else { return nil }
        return slot < halfSlots ? 0 : 1
    }

    func isOrganizer(_ uid: String?) -> Bool { uid == organizerId }
    func isParticipant(_ uid: String?) -> Bool {
        guard let uid else { return false }
        return participants.contains(uid)
    }
}

// MARK: - Équipe

struct Team: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var ownerId: String
    var memberIds: [String]
    var createdAt: Date
    var crestIcon: String? = nil        // SF Symbol de l'écusson
    var crestColorName: String? = nil   // couleur de l'écusson
}

// MARK: - Club Classé (roster fixe, sert à rejoindre un match Classé)

struct Club: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var captainId: String
    var starterIds: [String]        // titulaires — max 5
    var substituteIds: [String]     // remplaçants — max 3
    var createdAt: Date
    var crestIcon: String? = nil
    var crestColorName: String? = nil

    static let maxStarters = 5
    static let maxSubstitutes = 3
    static let maxClubsPerUser = 3

    var rosterCount: Int { starterIds.count + substituteIds.count }
    var isFull: Bool { starterIds.count >= Self.maxStarters && substituteIds.count >= Self.maxSubstitutes }
    /// Prêt à jouer un match Classé : il faut les 5 titulaires au complet.
    var isReadyForRanked: Bool { starterIds.count >= Self.maxStarters }
}

enum CrestPalette {
    static let icons = ["shield.fill", "flame.fill", "bolt.fill", "crown.fill", "star.fill", "pawprint.fill", "hare.fill", "tornado"]
    static let colors: [(name: String, color: Color)] = [
        ("teal", Pitcha.teal), ("navy", Pitcha.navy), ("red", .red), ("orange", .orange),
        ("purple", .purple), ("green", .green), ("pink", .pink), ("indigo", .indigo)
    ]

    static func color(named name: String?) -> Color {
        colors.first { $0.name == name }?.color ?? Pitcha.teal
    }
}

// MARK: - Historique de matchs (sous-collection users/{uid}/history)

struct MatchRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var date: Date
    var title: String
    var goals: Int
    var result: String      // "win" / "draw" / "loss"
    var xpGained: Int? = nil       // absent sur les entrées Classé (voir plGained)
    var ranked: Bool? = nil
    var plGained: Int? = nil
    var newDivision: String? = nil

    var isRankedRecord: Bool { ranked ?? false }
    var xpGainedValue: Int { xpGained ?? 0 }
    var plGainedValue: Int { plGained ?? 0 }

    var resultLabel: String {
        switch result {
        case "win": return "Victoire"
        case "draw": return "Nul"
        default: return "Défaite"
        }
    }

    var resultColor: Color {
        switch result {
        case "win": return .green
        case "draw": return .orange
        default: return .red
        }
    }
}

// MARK: - Message (chat équipe / amis)

struct ChatMessage: Identifiable, Codable {
    @DocumentID var id: String?
    var senderId: String
    var senderPseudo: String
    var text: String
    var sentAt: Date
}

// MARK: - Invitation à un match (entre amis)

struct MatchInvite: Identifiable, Codable {
    @DocumentID var id: String?    // = matchId (une seule invitation active par match/ami)
    var matchId: String
    var matchTitle: String
    var invitedBy: String
    var invitedByPseudo: String
    var createdAt: Date
}
