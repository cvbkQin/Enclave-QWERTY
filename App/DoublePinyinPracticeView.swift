import SwiftUI
import UIKit

// App 里的双拼练习（双拼调研 P3-11，设计稿 SP10）：首页、练习中、按错、一组练完。
// 键盘就是用户自己的键盘：练习页有个看不见的输入框把它拉起来，飞地键盘看到 DoublePinyinPracticeLink 后字母原样上屏，
// 「跟着按键变」的提示照样按框里已经按对的键走。

enum DoublePinyinPracticePools {
    static let basic = DoublePinyinPracticeItem.parse(DoublePinyinPracticeData.basic)
    static let words = DoublePinyinPracticeItem.parse(DoublePinyinPracticeData.words)
    static let sentences = DoublePinyinPracticeItem.parse(DoublePinyinPracticeData.sentences)

    static func pool(_ level: DoublePinyinPracticeLevel) -> [DoublePinyinPracticeItem] {
        switch level {
        case .basic: return basic
        case .words: return words
        case .sentences: return sentences
        }
    }

    /// 这一级练会了多少（0…1）。
    static func progress(_ level: DoublePinyinPracticeLevel, state: DoublePinyinPracticeState) -> Double {
        let pool = pool(level)
        guard !pool.isEmpty else { return 0 }
        let texts = Set(pool.map(\.text))
        let known = Set(state.mastered[level] ?? []).intersection(texts)
        return Double(known.count) / Double(pool.count)
    }

    /// 短句在词组练到 60% 后解锁。
    static func unlocked(_ level: DoublePinyinPracticeLevel, state: DoublePinyinPracticeState) -> Bool {
        level != .sentences || progress(.words, state: state) >= 0.6
    }

    static func next(after level: DoublePinyinPracticeLevel, state: DoublePinyinPracticeState) -> DoublePinyinPracticeLevel? {
        switch level {
        case .basic: return .words
        case .words: return unlocked(.sentences, state: state) ? .sentences : nil
        case .sentences: return nil
        }
    }
}

private enum PracticeColor {
    static let green = Color(red: 0x16 / 255, green: 0xA3 / 255, blue: 0x4A / 255)
    static let red = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0x6B / 255, blue: 0x6B / 255, alpha: 1)
        : UIColor(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255, alpha: 1) })
}

/// ① 练习首页：最近 7 天、老按错的、三级进度、继续练。
struct DoublePinyinPracticeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var state = DoublePinyinPracticeStore.load()
    @State private var playing: DoublePinyinPracticeLevel?

    private var scheme: DoublePinyin { store.settings.doublePinyin ?? .flypy }

    private var continueLevel: DoublePinyinPracticeLevel {
        DoublePinyinPracticePools.unlocked(state.lastLevel, state: state) ? state.lastLevel : .words
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 0) {
                    let week = DoublePinyinPracticeStore.week(state)
                    stat(week.map { "\(Int(($0.accuracy * 100).rounded()))%" } ?? "–", L("正确率", "Accuracy", "正答率"))
                    Divider()
                    stat(week.map { "\(Int($0.perMinute.rounded()))" } ?? "–", L("字 / 分", "chars / min", "字 / 分"))
                    Divider()
                    stat(week.map { "\(Int($0.minutes.rounded()))" } ?? "–", L("分钟", "minutes", "分"))
                }
                .listRowInsets(EdgeInsets())
            } header: {
                Text(L("最近 7 天", "Last 7 days", "最近 7 日"))
            }
            let mistakes = DoublePinyinPracticeStore.topMistakes(state)
            if !mistakes.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        ForEach(Array(mistakes.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 6) {
                                MiniKeycap(letter: item.key, size: 12)
                                Text(item.unit).font(.subheadline)
                                Text("×\(item.times)").font(.caption.weight(.semibold)).foregroundStyle(PracticeColor.red)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.secondarySystemBackground)))
                        }
                        Spacer(minLength: 0)
                    }
                } header: {
                    Text(L("老按错的", "Often missed", "よく間違えるキー"))
                } footer: {
                    Text(L("这几个键在「跟着按键变」的提示里会排在前面、字更深一点。",
                           "These come first and darker in the \"Follow typing\" hints.",
                           "これらは「入力に合わせる」のヒントで先頭に、濃く表示されます。"))
                }
            }
            Section {
                ForEach(DoublePinyinPracticeLevel.allCases) { level in
                    let open = DoublePinyinPracticePools.unlocked(level, state: state)
                    Button { playing = level } label: {
                        HStack {
                            Text(level.title).foregroundStyle(open ? Color.primary : Color.secondary)
                            Spacer()
                            if open {
                                ProgressView(value: DoublePinyinPracticePools.progress(level, state: state))
                                    .tint(AppColor.purple)
                                    .frame(width: 80)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            } else {
                                Text(L("词组练到 60% 解锁", "Unlocks at 60% of Words", "単語 60% で解放")).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!open)
                }
            } header: {
                Text(L("级别", "Levels", "レベル"))
            }
            Section {
                Button { playing = continueLevel } label: {
                    Text(L("继续练「\(continueLevel.shortTitle)」", "Continue \(continueLevel.shortTitle)", "「\(continueLevel.shortTitle)」を続ける"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.purple))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(L("双拼练习", "Practice", "双拼の練習"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { state = DoublePinyinPracticeStore.load() }
        .fullScreenCover(item: $playing, onDismiss: { state = DoublePinyinPracticeStore.load() }) { level in
            DoublePinyinPracticeSessionView(scheme: scheme, level: level)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// ②③④ 练一组：上面出字，下面是用户自己的键盘；练完给结果。
struct DoublePinyinPracticeSessionView: View {
    let scheme: DoublePinyin
    @State private var level: DoublePinyinPracticeLevel
    @State private var run: DoublePinyinPracticeRun
    @State private var wrong: DoublePinyinPracticeRun.Wrong?
    @State private var wrongKey: Character?
    @State private var wrongToken = 0
    @State private var finished = false
    @State private var recorded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let keepAlive = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    init(scheme: DoublePinyin, level: DoublePinyinPracticeLevel) {
        self.scheme = scheme
        _level = State(initialValue: level)
        _run = State(initialValue: Self.makeRun(scheme: scheme, level: level))
    }

    private static func makeRun(scheme: DoublePinyin, level: DoublePinyinPracticeLevel) -> DoublePinyinPracticeRun {
        let state = DoublePinyinPracticeStore.load()
        let items = DoublePinyinPracticeItem.pick(from: DoublePinyinPracticePools.pool(level), missed: state.missed[level] ?? [],
                                                  mastered: Set(state.mastered[level] ?? []))
        return DoublePinyinPracticeRun(scheme: scheme, level: level, items: items)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if finished { results } else { practice }
            Spacer(minLength: 0)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear { DoublePinyinPracticeLink.keepAlive() }
        .onReceive(keepAlive) { _ in if !finished, scenePhase == .active { DoublePinyinPracticeLink.keepAlive() } }
        .onChange(of: scenePhase) { phase in
            if phase == .active, !finished { DoublePinyinPracticeLink.keepAlive() } else if phase != .active { DoublePinyinPracticeLink.end() }
        }
        .onDisappear {
            DoublePinyinPracticeLink.end()
            saveIfNeeded()
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            ZStack {
                Text(finished ? L("\(level.shortTitle) · 练完了", "\(level.shortTitle) · Done", "\(level.shortTitle)・完了")
                     : "\(level.shortTitle) · \(run.doneCharacters) / \(run.totalCharacters)")
                    .font(.headline)
                    .monospacedDigit()
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(AppColor.purple)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L("关闭", "Close", "閉じる"))
                    Spacer()
                }
            }
            if !finished {
                ProgressView(value: Double(run.doneCharacters), total: Double(max(run.totalCharacters, 1)))
                    .tint(AppColor.purple)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    // MARK: ②③ 练习中、按错

    private var practice: some View {
        VStack(spacing: 14) {
            if let item = run.currentItem, let syllable = run.currentSyllable {
                VStack(spacing: 10) {
                    characterLine(item)
                    Text(syllable)
                        .font(.system(size: 22, design: .rounded))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        cell(0)
                        cell(1)
                    }
                    .padding(.top, 4)
                    status(syllable: syllable)
                        .font(.subheadline)
                        .frame(minHeight: 24)
                }
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            PracticeKeyField(text: run.typed, onKey: press)
                .frame(width: 1, height: 1)
                .opacity(0.02)
                .accessibilityHidden(true)
        }
    }

    /// 字大字显示；词组、短句里当前这个字是黑的，别的字灰。
    private func characterLine(_ item: DoublePinyinPracticeItem) -> some View {
        let size: CGFloat = item.text.count == 1 ? 64 : item.text.count <= 4 ? 52 : 30
        var text = Text("")
        for (index, character) in item.characters.enumerated() {
            let current = index == run.characterIndex
            text = text + Text(String(character)).foregroundColor(current || item.text.count == 1 ? .primary : Color(.tertiaryLabel))
        }
        return text
            .font(.system(size: size, weight: .bold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 16)
    }

    private func cell(_ index: Int) -> some View {
        let typed = Array(run.typed)
        let isWrong = wrongKey != nil && index == typed.count
        let letter: String? = index < typed.count ? String(typed[index]) : isWrong ? wrongKey.map(String.init) : nil
        let current = index == typed.count && !isWrong
        let color: Color = isWrong ? PracticeColor.red : index < typed.count ? PracticeColor.green : current ? AppColor.purple : Color(.separator)
        return Text(letter ?? " ")
            .font(.system(size: 26, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 52, height: 58)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isWrong ? PracticeColor.red.opacity(0.1)
                : index < typed.count ? PracticeColor.green.opacity(0.1) : Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color, lineWidth: 2))
    }

    @ViewBuilder
    private func status(syllable: String) -> some View {
        if let wrong {
            HStack(spacing: 4) {
                Text(L("按成了 \(wrong.got)，\(wrong.unit) 在", "That's \(wrong.got). \(wrong.unit) is on", "\(wrong.got) になりました。\(wrong.unit) は"))
                MiniKeycap(letter: String(wrong.key), size: 12)
                if Loc.current == .ja { Text("にあります") }
            }
            .foregroundStyle(PracticeColor.red)
        } else if run.typed.count == 1 {
            let units = DoublePinyinPracticeRun.units(of: syllable)
            Text(DoublePinyin.split(syllable).initial.isEmpty
                 ? L("第一下对了，接着按 \(units.second)", "Good. Now the rest of \(units.second)", "1 回目 OK。続けて \(units.second)")
                 : L("声母 \(units.first) 对了，接着按 \(units.second)", "Initial \(units.first) ✓. Now \(units.second)", "声母 \(units.first) OK。続けて \(units.second)"))
                .foregroundStyle(.secondary)
        } else {
            Text(L("按这个字的双拼", "Type this character in double pinyin", "この字を双拼で"))
                .foregroundStyle(.secondary)
        }
    }

    private func press(_ key: Character) {
        guard !finished, key.isLetter, key.isASCII else { return }
        wrong = nil
        wrongKey = nil
        switch run.press(key) {
        case .right, .nextCharacter:
            break
        case .wrong(let detail):
            wrong = detail
            wrongKey = Character(key.lowercased())
            wrongToken += 1
            let token = wrongToken
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // 1 秒后红格清空，只重按这一下（SP10 ③）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if wrongToken == token { wrongKey = nil; wrong = nil }
            }
        case .finished:
            finish()
        }
    }

    private func finish() {
        saveIfNeeded()
        DoublePinyinPracticeLink.end()
        finished = true
    }

    private func saveIfNeeded() {
        guard !recorded, run.keys > 0 else { return }
        recorded = true
        var state = DoublePinyinPracticeStore.load()
        run.record(into: &state)
        DoublePinyinPracticeStore.save(state)
    }

    private func restart(_ next: DoublePinyinPracticeLevel) {
        level = next
        run = Self.makeRun(scheme: scheme, level: next)
        wrong = nil
        wrongKey = nil
        recorded = false
        finished = false
        DoublePinyinPracticeLink.keepAlive()
    }

    // MARK: ④ 一组练完

    private var results: some View {
        let seconds = Int(Date().timeIntervalSince(run.started).rounded())
        let minutes = max(Double(seconds) / 60, 1.0 / 60)
        let perMinute = Int((Double(run.doneCharacters) / minutes).rounded())
        let next = DoublePinyinPracticePools.next(after: level, state: DoublePinyinPracticeStore.load())
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 6) {
                    Text(L("这一组", "This set", "このセット")).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(Int((run.accuracy * 100).rounded()))%").font(.system(size: 56, weight: .bold)).monospacedDigit()
                    Text(L("正确率 · \(perMinute) 字 / 分 · \(duration(seconds))",
                           "accuracy · \(perMinute) chars/min · \(duration(seconds))",
                           "正答率・\(perMinute) 字/分・\(duration(seconds))"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                if !run.missedCharacters.isEmpty {
                    Text(L("这组按错的", "Missed in this set", "このセットで間違えた字"))
                        .font(.footnote).foregroundStyle(.secondary).padding(.leading, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(Array(run.missedCharacters.enumerated()), id: \.offset) { _, entry in
                            HStack(spacing: 6) {
                                Text("\(entry.character) \(entry.syllable)").font(.subheadline)
                                Spacer(minLength: 2)
                                ForEach(Array(entry.code.enumerated()), id: \.offset) { _, key in MiniKeycap(letter: String(key), size: 11) }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                        }
                    }
                }
                Button { restart(level) } label: {
                    Text(L("再来一组", "Another set", "もう 1 セット"))
                        .font(.body.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.purple))
                }
                .buttonStyle(.plain)
                if let next {
                    Button { restart(next) } label: {
                        Text(L("去练「\(next.shortTitle)」", "Try \(next.shortTitle)", "「\(next.shortTitle)」へ"))
                            .font(.body.weight(.semibold)).foregroundStyle(AppColor.purple)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func duration(_ seconds: Int) -> String {
        seconds >= 60 ? L("\(seconds / 60) 分 \(seconds % 60) 秒", "\(seconds / 60)m \(seconds % 60)s", "\(seconds / 60) 分 \(seconds % 60) 秒")
            : L("\(seconds) 秒", "\(seconds)s", "\(seconds) 秒")
    }
}

/// 把键盘拉起来的输入框：英文键盘类型、回车「前往」、不自动改正（飞地键盘认这几样，见 KeyboardModel.practiceActive）。
/// 框里只放这个字已经按对的键，键盘的「跟着按键变」看得到；字母都不真的写进去，交给 onKey。
private struct PracticeKeyField: UIViewRepresentable {
    let text: String
    let onKey: (Character) -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .asciiCapable
        field.returnKeyType = .go
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartInsertDeleteType = .no
        field.tintColor = .clear
        field.delegate = context.coordinator
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.onKey = onKey
        if field.text != text { field.text = text }
        if !field.isFirstResponder { DispatchQueue.main.async { field.becomeFirstResponder() } }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onKey: onKey) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var onKey: (Character) -> Void

        init(onKey: @escaping (Character) -> Void) { self.onKey = onKey }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            for character in string where character.isLetter && character.isASCII { onKey(character) }
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool { false }
    }
}
