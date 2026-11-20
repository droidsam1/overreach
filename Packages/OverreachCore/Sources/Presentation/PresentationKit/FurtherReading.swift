import Domain
import Foundation

/// A reading that explains the idea behind a rule (ADR-0027).
public struct Reading: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        /// A trial or a meta-analysis.
        case study
        /// A plain-language article.
        case article
    }

    public let title: String
    /// Author or outlet, e.g. "Fitness Revolucionario (Marcos Vázquez)".
    public let source: String
    /// Publication year; `nil` for an undated guide page.
    public let year: Int?
    public let url: URL
    /// ISO 639-1 code of the text's language.
    public let languageCode: String
    public let kind: Kind
    /// A caveat shown with it, when it agrees with the register only in part.
    public let note: String?

    public var id: URL { url }

    /// "Fitness Revolucionario (Marcos Vázquez) · 2020 · in Spanish" — the language only when it is not the user's.
    public func detail(userLanguage: String = L10n.languageCode) -> String {
        var parts = [source] + (year.map { [String($0)] } ?? [])
        if languageCode != userLanguage {
            parts.append(languageCode == "es" ? L10n.text("in Spanish") : L10n.text("in English"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Curated further reading per evidence key (ADR-0027, `docs/evidence-review-2026-11.md` §6).
///
/// Rules for adding one: a person has read it and it agrees with the register entry of its key. An article that
/// contradicts the entry is not linked, whoever wrote it (e.g. Fitness Revolucionario's 2016 article on training by
/// cycle phase, and its older advice that short rests build more muscle). `scripts/check-reading-links.py` reports
/// links that no longer resolve.
public enum FurtherReading {
    /// At most this many readings per explanation.
    public static let limit = 3

    /// Readings for the given evidence keys, those in the user's language first, without repeats.
    public static func readings(
        for references: [EvidenceReference], userLanguage: String = L10n.languageCode
    ) -> [Reading] {
        var seen = Set<URL>()
        var result: [Reading] = []
        for reference in references {
            for reading in catalogue[reference.key] ?? [] where !seen.contains(reading.url) {
                seen.insert(reading.url)
                result.append(reading)
            }
        }
        let own = result.filter { $0.languageCode == userLanguage }
        let others = result.filter { $0.languageCode != userLanguage }
        return Array((own + others).prefix(limit))
    }

    /// Readings for one evidence key.
    public static func readings(for reference: EvidenceReference, userLanguage: String = L10n.languageCode) -> [Reading] {
        readings(for: [reference], userLanguage: userLanguage)
    }

    // MARK: - Catalogue

    private static let fitnessRevolucionario = "Fitness Revolucionario (Marcos Vázquez)"

    private static func fr(_ title: String, _ year: Int?, _ path: String, note: String? = nil) -> Reading {
        Reading(
            title: title, source: fitnessRevolucionario, year: year,
            url: URL(string: "https://www.fitnessrevolucionario.com" + path)!, languageCode: "es", kind: .article,
            note: note
        )
    }

    private static func study(_ title: String, _ source: String, _ year: Int, _ url: String) -> Reading {
        Reading(title: title, source: source, year: year, url: URL(string: url)!, languageCode: "en", kind: .study,
                note: nil)
    }

    // Plain-language articles (Spanish).
    private static let autoregulation = fr(
        "Autorregulación: usa tus percepciones para mejorar tu entrenamiento y tus resultados", 2020,
        "/2020/07/29/autorregulacion-entrenamiento/"
    )
    private static let strengthBasics = fr(
        "Qué es el entrenamiento de fuerza y cómo empezar", 2022, "/2022/10/08/entrenar-fuerza/"
    )
    private static let buildMuscle = fr("Cómo ganar masa muscular", nil, "/ganar-musculo/")
    private static let fiveThreeOne = fr(
        "Aumenta tu fuerza y musculatura con 5/3/1", 2013, "/2013/06/03/aumenta-tu-fuerza-y-musculatura-con-531/"
    )
    private static let sleep = fr(
        "Entrenamiento invisible: estrategias para acelerar la recuperación (sueño)", 2021,
        "/2021/08/23/acelerar-recuperacion-descanso/"
    )
    private static let hrvIntro = fr(
        "¿Por qué quieres un corazón irregular? O el indicador más importante de tu salud", 2016,
        "/2016/02/13/por-que-quieres-un-corazon-irregular-o-el-indicador-mas-importante-de-tu-salud/",
        note: L10n.text(
            "An older introduction. Overreach compares your 7-day average with your own usual range, not a single morning."
        )
    )
    private static let soreness = fr("La ciencia de las agujetas: qué son y cómo combatirlas", 2019, "/2019/01/10/agujetas/")
    private static let walking = fr(
        "La magia de caminar, y consejos para dar más pasos", 2014,
        "/2014/03/08/la-magia-de-caminar-y-consejos-para-dar-mas-pasos/"
    )

    // Studies and reviews (English, open access where possible).
    private static let plotkin = study(
        "Progressive overload without progressing load? The effects of load or repetition progression",
        "Plotkin et al., PeerJ", 2022, "https://peerj.com/articles/14142/"
    )
    private static let robinson = study(
        "Exploring the dose–response relationship between estimated resistance training proximity to failure, "
            + "strength gain, and muscle hypertrophy", "Robinson et al., Sports Medicine", 2024,
        "https://sportrxiv.org/index.php/server/preprint/view/295"
    )
    private static let pelland = study(
        "The resistance training dose response: meta-regressions exploring the effects of weekly volume and "
            + "frequency", "Pelland et al., Sports Medicine", 2026,
        "https://sportrxiv.org/index.php/server/preprint/view/460"
    )
    private static let singer = study(
        "Give it a rest: a systematic review with Bayesian meta-analysis on the effect of inter-set rest interval "
            + "duration on muscle hypertrophy", "Singer et al., Frontiers in Sports and Active Living", 2024,
        "https://www.frontiersin.org/articles/10.3389/fspor.2024.1429789/full"
    )
    private static let moesgaard = study(
        "Effects of periodization on strength and muscle hypertrophy in volume-equated resistance training "
            + "programs", "Moesgaard et al., Sports Medicine", 2022, "https://pubmed.ncbi.nlm.nih.gov/35044672/"
    )
    private static let grgicPeriodization = study(
        "Effects of linear and daily undulating periodized resistance training programs on measures of muscle "
            + "hypertrophy", "Grgic et al., PeerJ", 2017, "https://peerj.com/articles/3695"
    )
    private static let rogerson = study(
        "Deloading practices in strength and physique sports: a cross-sectional survey",
        "Rogerson et al., Sports Medicine – Open", 2024, "https://pmc.ncbi.nlm.nih.gov/articles/PMC10948666"
    )
    private static let lolli = study(
        "Mathematical coupling causes spurious correlation within the conventional acute-to-chronic workload "
            + "ratio calculations", "Lolli et al., British Journal of Sports Medicine", 2019,
        "https://bjsm.bmj.com/content/53/15/921.full"
    )
    private static let hrvGuided = study(
        "Heart rate variability-guided training for enhancing cardiac-vagal modulation, aerobic fitness, and "
            + "endurance performance", "Manresa-Rocamora et al., Int J Environ Res Public Health", 2021,
        "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8507742/"
    )
    private static let schmalenberger = study(
        "A systematic review and meta-analysis of within-person changes in cardiac vagal activity across the "
            + "menstrual cycle", "Schmalenberger et al., Journal of Clinical Medicine", 2019,
        "https://doi.org/10.3390/jcm8111946"
    )
    private static let saw = study(
        "Monitoring the athlete training response: subjective self-reported measures trump commonly used objective "
            + "measures", "Saw, Main & Gastin, British Journal of Sports Medicine", 2016,
        "https://bjsm.bmj.com/content/50/5/281"
    )
    private static let schumann = study(
        "Compatibility of concurrent aerobic and strength training for skeletal muscle size and function",
        "Schumann et al., Sports Medicine", 2022, "https://link.springer.com/article/10.1007/s40279-021-01587-7"
    )
    private static let ding = study(
        "Daily steps and health outcomes in adults: a systematic review and dose-response meta-analysis",
        "Ding et al., The Lancet Public Health", 2025, "https://pubmed.ncbi.nlm.nih.gov/40713949/"
    )
    private static let schyvens = study(
        "A performance validation of six commercial wrist-worn wearable sleep-tracking devices",
        "Schyvens et al., Sleep Advances", 2025, "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12038347/"
    )
    private static let molinaGarcia = study(
        "Validity of estimating the maximal oxygen consumption by consumer wearables",
        "Molina-García et al., Sports Medicine", 2022, "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9213394/"
    )

    /// Evidence key → readings. Keys must exist in `docs/evidence.md` (checked by a test).
    static let catalogue: [String: [Reading]] = [
        "progression-load-or-reps": [strengthBasics, plotkin],
        "proximity-to-failure": [autoregulation, robinson],
        "rir-based-rpe": [autoregulation],
        "rir-estimation": [autoregulation],
        "autoregulation-load": [autoregulation],
        "effective-set-threshold": [buildMuscle, robinson],
        "volume-dose-response": [buildMuscle, pelland],
        "frequency-volume-equated": [buildMuscle, pelland],
        "loading-by-goal": [buildMuscle],
        "rest-hypertrophy": [singer],
        "periodization": [fiveThreeOne, moesgaard, grgicPeriodization],
        "stall-heuristics": [strengthBasics],
        "deload-design": [rogerson],
        "deload-practice": [rogerson],
        "weekly-load-change": [lolli],
        "warm-up-general": [strengthBasics],
        "readiness-hrv": [hrvIntro, hrvGuided],
        "hrv-cycle-phase": [schmalenberger],
        "cycle-phase-baselines": [schmalenberger],
        "readiness-sleep": [sleep],
        "readiness-subjective": [soreness, saw],
        "walking-active-recovery": [walking],
        "walking-no-interference": [schumann],
        "low-steps-exercise-resistance": [walking, ding],
        "wearable-sleep-stages": [schyvens],
        "wearable-vo2max": [molinaGarcia],
    ]
}
