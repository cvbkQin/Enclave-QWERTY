import Foundation

/// App 里的双拼练习（双拼调研 P3-11，设计稿 SP10）和键盘之间的约定：练习页开着时 App 每几秒在共享存储里写一个「到这个时间为止」，
/// 键盘看到它、输入框又是练习页那种（asciiCapable、回车是「下一项」）时，字母不进拼音引擎，原样上屏，练习页看按的是哪个键。
/// App 退到后台、离开练习页时马上清掉；万一没清，最多 20 秒后自己失效。
enum DoublePinyinPracticeLink {
    private static let key = "doublePinyin.practiceUntil"

    static var isActive: Bool {
        (SharedStorage.defaults.object(forKey: key) as? Date).map { $0 > Date() } ?? false
    }

    static func keepAlive(now: Date = Date()) {
        SharedStorage.defaults.set(now.addingTimeInterval(20), forKey: key)
    }

    static func end() {
        SharedStorage.defaults.removeObject(forKey: key)
    }
}

/// 练习的三级（SP10 ①）。
enum DoublePinyinPracticeLevel: String, Codable, CaseIterable, Identifiable {
    case basic, words, sentences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return L("基础 · 看字按键", "Basics · see and type", "基礎・見て打つ")
        case .words: return L("词组", "Words", "単語")
        case .sentences: return L("短句", "Sentences", "短文")
        }
    }

    var shortTitle: String {
        switch self {
        case .basic: return L("基础", "Basics", "基礎")
        case .words: return L("词组", "Words", "単語")
        case .sentences: return L("短句", "Sentences", "短文")
        }
    }
}

/// 练习记录：每组的成绩、老按错的、每级练会了哪些。存在共享存储里，键盘读「老按错的」把这几个韵母在提示里写深一点。
struct DoublePinyinPracticeState: Codable, Equatable {
    struct Session: Codable, Equatable {
        var date: Date
        var level: DoublePinyinPracticeLevel
        /// 这组练了几个字、按了几下键、按错几下、用了几秒。
        var characters: Int
        var keys: Int
        var wrong: Int
        var seconds: Double
    }

    var sessions: [Session] = []
    /// 按错的次数，键是「键|该按的声母或韵母」（l|iang）。
    var mistakes: [String: Int] = [:]
    /// 每级第一次就按对的字词（练会了），算进度条。
    var mastered: [DoublePinyinPracticeLevel: [String]] = [:]
    /// 上一组按错过的字词，下一组先出。
    var missed: [DoublePinyinPracticeLevel: [String]] = [:]
    /// 最近练的哪一级，首页按钮「继续练」用。
    var lastLevel: DoublePinyinPracticeLevel = .basic
}

enum DoublePinyinPracticeStore {
    private static let key = "doublePinyin.practice.v1"

    static func load() -> DoublePinyinPracticeState {
        guard let data = SharedStorage.defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(DoublePinyinPracticeState.self, from: data) else { return DoublePinyinPracticeState() }
        return state
    }

    static func save(_ state: DoublePinyinPracticeState) {
        var state = state
        if state.sessions.count > 300 { state.sessions.removeFirst(state.sessions.count - 300) }
        if let data = try? JSONEncoder().encode(state) { SharedStorage.defaults.set(data, forKey: key) }
    }

    /// 最近 7 天：正确率（按键）、字 / 分、分钟。没练过时 nil。
    static func week(_ state: DoublePinyinPracticeState, now: Date = Date()) -> (accuracy: Double, perMinute: Double, minutes: Double)? {
        let recent = state.sessions.filter { now.timeIntervalSince($0.date) < 7 * 86400 }
        let keys = recent.reduce(0) { $0 + $1.keys }
        guard keys > 0 else { return nil }
        let wrong = recent.reduce(0) { $0 + $1.wrong }
        let seconds = recent.reduce(0) { $0 + $1.seconds }
        let characters = recent.reduce(0) { $0 + $1.characters }
        return (Double(keys - wrong) / Double(keys), seconds > 0 ? Double(characters) / (seconds / 60) : 0, seconds / 60)
    }

    /// 「双拼方案」页练习那一行右边：最近一次的正确率，没练过写「没练过」。
    static var summary: String {
        guard let last = load().sessions.last, last.keys > 0 else { return L("没练过", "Not yet", "未練習") }
        let percent = Int((Double(last.keys - last.wrong) / Double(last.keys) * 100).rounded())
        return L("正确率 \(percent)%", "\(percent)% correct", "正答率 \(percent)%")
    }

    /// 最常按错的几个：(键, 声母或韵母, 次数)。
    static func topMistakes(_ state: DoublePinyinPracticeState, count: Int = 3) -> [(key: String, unit: String, times: Int)] {
        state.mistakes.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(count).compactMap { entry in
            let parts = entry.key.split(separator: "|", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1], entry.value) : nil
        }
    }

    /// 键盘提示里写深一点的韵母（和 zh / ch / sh）：老按错的前三个。
    static var weakUnits: Set<String> {
        Set(topMistakes(load()).map(\.unit))
    }
}

/// 一条练习：字词和每个字的全拼（ü 写 v）。
struct DoublePinyinPracticeItem: Equatable, Hashable {
    let text: String
    let syllables: [String]

    var characters: [Character] { Array(text) }

    /// 读「字词<TAB>空格分开的全拼」，字数和音节数对不上的丢掉。
    static func parse(_ data: String) -> [DoublePinyinPracticeItem] {
        data.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let text = String(parts[0])
            let syllables = parts[1].split(separator: " ").map(String.init)
            guard !syllables.isEmpty, text.count == syllables.count else { return nil }
            return DoublePinyinPracticeItem(text: text, syllables: syllables)
        }
    }

    /// 挑一组：先出上次按错的，再按常用程度出还没练会的，都练会了就随机复习；凑够 count 个字为止。
    static func pick(from pool: [DoublePinyinPracticeItem], missed: [String], mastered: Set<String>, count: Int = 30) -> [DoublePinyinPracticeItem] {
        let byText = Dictionary(pool.map { ($0.text, $0) }, uniquingKeysWith: { first, _ in first })
        var picked: [DoublePinyinPracticeItem] = []
        var used = Set<String>()
        var characters = 0
        func add(_ item: DoublePinyinPracticeItem) {
            guard characters < count, !used.contains(item.text) else { return }
            picked.append(item)
            used.insert(item.text)
            characters += item.text.count
        }
        missed.compactMap { byText[$0] }.forEach(add)
        pool.filter { !mastered.contains($0.text) }.forEach(add)
        pool.shuffled().forEach(add)
        return picked
    }
}

/// 一组练习进行中：每个字按两下，按对的留下，按错的那一下 1 秒后清掉重按（SP10 ②③）。纯逻辑，界面在 App 里。
struct DoublePinyinPracticeRun {
    struct Wrong: Equatable {
        /// 按成了什么：能拼上的写韵母（ing），拼不上写键（k）。
        let got: String
        /// 该按的声母或韵母（iang、sh；零声母写整个音节）和它在哪个键。
        let unit: String
        let key: Character
    }

    enum Outcome: Equatable {
        case right
        case nextCharacter
        case wrong(Wrong)
        case finished
    }

    let scheme: DoublePinyin
    let level: DoublePinyinPracticeLevel
    let items: [DoublePinyinPracticeItem]
    let started: Date

    private(set) var itemIndex = 0
    private(set) var characterIndex = 0
    /// 这个字已经按对的键（0 或 1 个）。
    private(set) var typed = ""
    private(set) var keys = 0
    private(set) var wrong = 0
    /// 按错过的字词（按出现顺序），和按错过的字（「这组按错的」列表用）。
    private(set) var missedItems: [String] = []
    private(set) var missedCharacters: [(character: String, syllable: String, code: String)] = []
    /// 键|单元 → 次数。
    private(set) var mistakes: [String: Int] = [:]
    /// 没按错一下就打完的字词。
    private(set) var cleanItems: [String] = []
    private var itemHadError = false
    private var characterHadError = false

    init(scheme: DoublePinyin, level: DoublePinyinPracticeLevel, items: [DoublePinyinPracticeItem], started: Date = Date()) {
        self.scheme = scheme
        self.level = level
        self.items = items
        self.started = started
    }

    var totalCharacters: Int { items.reduce(0) { $0 + $1.text.count } }
    var doneCharacters: Int { items.prefix(itemIndex).reduce(0) { $0 + $1.text.count } + characterIndex }
    var isFinished: Bool { itemIndex >= items.count }
    var currentItem: DoublePinyinPracticeItem? { isFinished ? nil : items[itemIndex] }
    var currentSyllable: String? { currentItem?.syllables[characterIndex] }
    /// 这个字要按的两个键（主按法）。
    var currentCode: String? { currentSyllable.flatMap(scheme.code(for:)) }

    /// 这个音节所有能按的：主按法加另一种（ad＝ai、xv＝xu）。
    private func accepted(_ syllable: String) -> [String] {
        guard let main = scheme.code(for: syllable) else { return [] }
        let others = scheme.codes.first { $0.syllable == syllable }?.alternates ?? []
        return [main] + others
    }

    /// 第一下、第二下各是什么单元：声母（sh）和韵母（iang）；零声母两下都算这个音节。
    static func units(of syllable: String) -> (first: String, second: String) {
        let (initial, final) = DoublePinyin.split(syllable)
        return initial.isEmpty ? (syllable, syllable) : (initial, final)
    }

    mutating func press(_ key: Character) -> Outcome {
        guard let item = currentItem, let syllable = currentSyllable, let main = scheme.code(for: syllable) else { return .finished }
        let key = Character(key.lowercased())
        keys += 1
        let codes = accepted(syllable)
        let attempt = typed + String(key)
        if codes.contains(where: { $0.hasPrefix(attempt) }) {
            typed = attempt
            guard typed.count == 2 else { return .right }
            finishCharacter(item: item, syllable: syllable, code: main)
            return isFinished ? .finished : .nextCharacter
        }
        wrong += 1
        itemHadError = true
        characterHadError = true
        let units = Self.units(of: syllable)
        let position = typed.count
        let expectedCode = codes.first { $0.hasPrefix(typed) } ?? main
        let expectedKey = Array(expectedCode)[position]
        let unit = position == 0 ? units.first : units.second
        mistakes["\(expectedKey)|\(unit)", default: 0] += 1
        var got = String(key)
        if position == 1, let reading = scheme.readings[attempt] {
            got = Self.units(of: reading).second
        } else if position == 0, let initial = DoublePinyin.retroflexKeys.first(where: { $0.value == key })?.key {
            got = initial
        }
        return .wrong(Wrong(got: got, unit: unit, key: expectedKey))
    }

    private mutating func finishCharacter(item: DoublePinyinPracticeItem, syllable: String, code: String) {
        if characterHadError {
            missedCharacters.append((String(item.characters[characterIndex]), syllable, code))
        }
        characterHadError = false
        typed = ""
        characterIndex += 1
        guard characterIndex >= item.syllables.count else { return }
        if itemHadError { missedItems.append(item.text) } else { cleanItems.append(item.text) }
        itemHadError = false
        characterIndex = 0
        itemIndex += 1
    }

    /// 这组的成绩：按键正确率。
    var accuracy: Double { keys > 0 ? Double(keys - wrong) / Double(keys) : 0 }

    /// 练完记进练习记录。
    func record(into state: inout DoublePinyinPracticeState, now: Date = Date()) {
        state.sessions.append(.init(date: now, level: level, characters: doneCharacters, keys: keys, wrong: wrong,
                                    seconds: max(now.timeIntervalSince(started), 1)))
        for (key, times) in mistakes { state.mistakes[key, default: 0] += times }
        var mastered = state.mastered[level] ?? []
        let known = Set(mastered)
        mastered += cleanItems.filter { !known.contains($0) }
        state.mastered[level] = mastered
        state.missed[level] = missedItems
        state.lastLevel = level
    }
}
