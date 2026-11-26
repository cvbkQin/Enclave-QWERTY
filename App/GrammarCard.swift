import SwiftUI

/// 设置 › 键盘 › 词库里的「整句模型」卡（design/dict-update DU1，对齐清单第 99 条）。
/// 大数字后面一个彩色小标签一眼看出状态：未下载、正在下载、已暂停、网络断了、下载失败、正在装进词库、已下载（关掉开关时「已关闭」）。
/// 下载线路两段选择：「非中国大陆 / 万象 GitHub」第一，「中国大陆 / 飞地服务器」第二；下载中、暂停、重试时点另一段从头下，不弹确认。
/// 内测版自带模型的那张（只能停用）样子不变。
struct GrammarCard: View {
    @ObservedObject private var grammar = GrammarDownloader.shared
    @ObservedObject private var deployer = RimeDeployer.shared
    @ObservedObject private var catalog = ExtDictStore.shared
    @Binding var confirmDelete: Bool

    var body: some View {
        DashCard {
            DashCardHeader(icon: "sparkles", title: L("整句模型", "Sentence model", "文章モデル"), color: DashColor.input, note: "CC BY 4.0")
            if GrammarModel.isBundled {
                bundled
            } else {
                VStack(alignment: .leading, spacing: 12) { content }
            }
        }
    }

    // MARK: 内测版自带（不变）

    @ViewBuilder
    private var bundled: some View {
        DashBigNumber(value: GrammarModel.installedSize.map { "\($0 / 1_000_000)" } ?? "380",
                      unit: grammar.enabled ? L("MB · 已内置", "MB · Built in", "MB · 内蔵") : L("MB · 已内置 · 已停用", "MB · Built in · Off", "MB · 内蔵 · オフ"))
        Toggle(L("使用整句模型", "Use sentence model", "文章モデルを使う"),
               isOn: Binding(get: { grammar.enabled }, set: { grammar.setEnabled($0) }))
            .tint(AppColor.purple)
            .disabled(deployer.state == .deploying)
        Text(L("内测版已自带整句模型，不用下载，也不能删除；不想用可以停用。",
               "The beta comes with the sentence model built in. It can't be deleted, but you can turn it off.",
               "ベータ版には文章モデルが内蔵されています。削除はできませんが、オフにできます。"))
            .font(.system(size: 13)).foregroundStyle(.secondary)
    }

    // MARK: 七种状态

    @ViewBuilder
    private var content: some View {
        let phase = grammar.phase
        switch phase {
        case .notDownloaded:
            header(value: megabytes(grammar.expectedSize), unit: "MB", badge: .notDownloaded)
            Text(L("按词和词常在一起出现的统计挑出最通顺的整句，整句打完首选更准。完全在本机运行，不联网。",
                   "Picks the most natural sentence from statistics of which words go together, so whole sentences come out right more often. Runs fully on this iPhone, offline.",
                   "語と語のつながりの統計から自然な文を選ぶので、文をまとめて入力したときの第一候補が正確になります。すべて端末内で動作し、通信しません。"))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            linePicker(showsNote: false)
            Button(L("下载", "Download", "ダウンロード")) { grammar.download() }
                .buttonStyle(PrimaryButtonStyle())

        case .downloading:
            header(value: percent, unit: "%", badge: .downloading)
            GrammarBar(fraction: grammar.progress?.fraction ?? 0, color: GrammarBadge.Kind.downloading.text)
            VStack(alignment: .leading, spacing: 2) {
                progressText
                Text(L("切到别的 App 也会接着下", "Keeps downloading if you switch apps", "ほかのアプリに切り替えても続きます"))
            }
            .font(.system(size: 13)).foregroundStyle(.secondary)
            linePicker(showsNote: true)
            Button(L("暂停", "Pause", "一時停止")) { grammar.pause() }
                .buttonStyle(SoftPurpleButtonStyle())

        case .paused:
            header(value: percent, unit: "%", badge: .paused)
            GrammarBar(fraction: grammar.progress?.fraction ?? 0, color: Color(.systemGray))
            progressText.font(.system(size: 13)).foregroundStyle(.secondary)
            linePicker(showsNote: true)
            Button(L("继续下载", "Resume", "再開")) { grammar.download() }
                .buttonStyle(PrimaryButtonStyle())

        case .retrying(let attempt, let at):
            header(value: percent, unit: "%", badge: .retrying)
            GrammarBar(fraction: grammar.progress?.fraction ?? 0, color: GrammarBadge.Kind.retrying.text)
            RetryCountdown(attempt: attempt, at: at)
            progressText.font(.system(size: 13)).foregroundStyle(.secondary)
            linePicker(showsNote: true)
            Button(L("暂停", "Pause", "一時停止")) { grammar.pause() }
                .buttonStyle(SoftPurpleButtonStyle())

        case .failed(let message):
            header(value: percent, unit: "%", badge: .failed)
            GrammarBar(fraction: grammar.progress?.fraction ?? 0, color: GrammarBadge.Kind.failed.text)
            Text(message).font(.system(size: 13)).foregroundStyle(GrammarBadge.Kind.failed.text)
            if grammar.progress != nil {
                progressText.font(.system(size: 13)).foregroundStyle(.secondary)
            }
            // 失败时不另外显示线路选择：换线路就用下面这个按钮，从头下。
            VStack(spacing: 8) {
                Button(L("重试", "Retry", "再試行")) { grammar.download() }
                    .buttonStyle(PrimaryButtonStyle())
                Button(grammar.line == .global
                       ? L("换到中国大陆线路下载", "Switch to Mainland China source", "中国本土から再ダウンロード")
                       : L("换到非中国大陆线路下载", "Switch to outside-Mainland source", "中国本土以外から再ダウンロード")) {
                    grammar.switchLine(to: grammar.line.other)
                }
                .buttonStyle(SoftPurpleButtonStyle())
            }

        case .installing:
            header(value: megabytes(GrammarModel.installedSize ?? grammar.expectedSize), unit: "MB", badge: .installing)
            FlowingBar(color: GrammarBadge.Kind.installing.text)
            Text(L("还要\(RimeDeployer.durationText)，装好后键盘就能用上。可以离开这页，也可以先用键盘打字。",
                   "About \(RimeDeployer.durationText.replacingOccurrences(of: "about ", with: "")) to go; the keyboard can use it once it's in. You can leave this page or keep typing meanwhile.",
                   "あと\(RimeDeployer.durationText)で、キーボードで使えるようになります。このページを離れても、先に入力していても大丈夫です。"))
                .font(.system(size: 13)).foregroundStyle(.secondary)

        case .installed:
            installed
        }
    }

    @ViewBuilder
    private var installed: some View {
        header(value: megabytes(GrammarModel.installedSize ?? grammar.expectedSize), unit: "MB", badge: grammar.enabled ? .installed : .off)
        if let version = grammar.updateVersion {
            updateBar(version)
        }
        // 关掉时模型留着，随时再打开，方便对比。切换后重新部署词库。
        Toggle(L("使用整句模型", "Use sentence model", "文章モデルを使う"),
               isOn: Binding(get: { grammar.enabled }, set: { grammar.setEnabled($0) }))
            .font(.system(size: 17))
            .tint(AppColor.purple)
            .disabled(deployer.state == .deploying)
        VStack(alignment: .leading, spacing: 6) {
            if let source = downloadedText {
                Text(source)
            }
            Text(grammar.enabled
                 ? L("长句一次打对的更多，键盘内存会多用一些。", "Whole sentences come out right more often; the keyboard uses a little more memory.", "長い文が一度で正しく出やすくなります。キーボードのメモリ使用は少し増えます。")
                 : L("关掉后模型留着，随时再打开。", "The model stays on your iPhone; turn it back on any time.", "オフにしてもモデルは残り、いつでもオンに戻せます。"))
        }
        .font(.system(size: 13)).foregroundStyle(.secondary)
        if let error = grammar.installError {
            Text(error).font(.system(size: 13)).foregroundStyle(GrammarBadge.Kind.failed.text)
        }
        Button(L("删除模型", "Delete model", "モデルを削除"), role: .destructive) { confirmDelete = true }
            .font(.system(size: 13, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(deployer.state == .deploying)
    }

    /// ⑧ 有新版本：只提示，点「更新」才下（391 MB 太大），装好前旧模型照常用。
    private func updateBar(_ version: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColor.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("有新版本（\(ExtDictStore.versionText(version))）", "New version (\(ExtDictStore.versionText(version)))", "新しい版（\(ExtDictStore.versionText(version))）"))
                    .font(.system(size: 15, weight: .semibold))
                Text(L("约 \(megabytes(grammar.expectedSize)) MB，不会自动下载", "About \(megabytes(grammar.expectedSize)) MB; not downloaded automatically", "約 \(megabytes(grammar.expectedSize)) MB、自動ではダウンロードしません"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(L("更新", "Update", "更新")) { grammar.download() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(AppColor.purple))
                .buttonStyle(.plain)
                .disabled(deployer.state == .deploying)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColor.softFill))
    }

    // MARK: 部件

    /// 大数字 + 单位 + 状态小标签。读屏念「45%，正在下载」。
    private func header(value: String, unit: String, badge: GrammarBadge.Kind) -> some View {
        HStack(alignment: .center, spacing: 10) {
            DashBigNumber(value: value, unit: unit)
            GrammarBadge(kind: badge)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value + (unit == "%" ? "%" : " " + unit) + L("，", ", ", "、") + badge.title)
    }

    private var percent: String { "\(grammar.progress?.percent ?? 0)" }

    /// 「176 / 391 MB · 非中国大陆线路」。
    private var progressText: some View {
        let progress = grammar.progress
        let line = progress?.line ?? grammar.line
        return Text("\(megabytes(progress?.received ?? 0)) / \(megabytes(progress?.expected ?? grammar.expectedSize)) MB · " + GrammarDownloader.lineName(line))
    }

    /// 「非中国大陆线路 · 11月26日下载」。
    private var downloadedText: String? {
        guard let line = GrammarModel.downloadedLine else { return nil }
        guard let date = GrammarModel.downloadedAt else { return GrammarDownloader.lineName(line) }
        return GrammarDownloader.lineName(line) + " · " + L("\(Loc.monthDay(date))下载", "downloaded \(Loc.monthDay(date))", "\(Loc.monthDay(date))にダウンロード")
    }

    private func megabytes(_ bytes: Int64) -> String {
        "\(Int((Double(bytes) / 1_000_000).rounded()))"
    }

    /// 「下载线路」两段选择；有进度时下面一行灰字「换线路要从头下」。
    private func linePicker(showsNote: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("下载线路", "Download source", "ダウンロード元")).font(.system(size: 13)).foregroundStyle(.secondary)
            LinePicker(selection: grammar.line) { grammar.switchLine(to: $0) }
            if showsNote {
                Text(L("换线路要从头下", "Switching starts over", "切り替えると最初から"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 小标签

/// 高 24、圆角 12、字 12.5 半粗、前面图标 13。颜色：灰 systemGray5；紫 #5B4BE8 12%；橙 #FF9F0A 16%；红 #FF3B30 12%；绿 #34C759 15%。
struct GrammarBadge: View {
    enum Kind {
        case notDownloaded, downloading, paused, retrying, failed, installing, installed, off

        var title: String {
            switch self {
            case .notDownloaded: return L("未下载", "Not downloaded", "未ダウンロード")
            case .downloading: return L("正在下载", "Downloading", "ダウンロード中")
            case .paused: return L("已暂停", "Paused", "一時停止中")
            case .retrying: return L("网络断了", "Connection lost", "接続が切れました")
            case .failed: return L("下载失败", "Download failed", "ダウンロード失敗")
            case .installing: return L("正在装进词库", "Installing", "辞書に追加中")
            case .installed: return L("已下载", "Downloaded", "ダウンロード済み")
            case .off: return L("已关闭", "Off", "オフ")
            }
        }

        var icon: String? {
            switch self {
            case .notDownloaded: return "arrow.down.to.line"
            case .paused: return "pause.fill"
            case .retrying: return "wifi.exclamationmark"
            case .failed: return "exclamationmark.circle"
            case .installed: return "checkmark"
            case .downloading, .installing, .off: return nil
            }
        }

        var text: Color {
            switch self {
            case .notDownloaded, .paused, .off: return .secondary
            case .downloading, .installing: return AppColor.purple
            case .retrying: return Color(light: 0xB86200, dark: 0xFFB340)
            case .failed: return Color(light: 0xD70015, dark: 0xFF6961)
            case .installed: return Color(light: 0x248A3D, dark: 0x30D158)
            }
        }

        var fill: Color {
            switch self {
            case .notDownloaded, .paused, .off: return Color(.systemGray5)
            case .downloading, .installing: return AppColor.purple.opacity(0.12)
            case .retrying: return Color(hex: 0xFF9F0A).opacity(0.16)
            case .failed: return Color(hex: 0xFF3B30).opacity(0.12)
            case .installed: return Color(hex: 0x34C759).opacity(0.15)
            }
        }
    }

    let kind: Kind
    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            switch kind {
            case .downloading:
                // 前面的小点一闪一闪。
                Circle().fill(kind.text).frame(width: 6, height: 6)
                    .opacity(blink ? 0.25 : 1)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { blink = true }
                    }
            case .installing:
                ProgressView().controlSize(.mini).tint(kind.text)
            default:
                if let icon = kind.icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
            }
            Text(kind.title).font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(kind.text)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(kind.fill))
        .fixedSize()
    }
}

/// 进度条：高 6、圆角 3，颜色跟标签走。
private struct GrammarBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule().fill(color).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.25), value: fraction)
        .accessibilityHidden(true)
    }
}

/// 安装中：紫色进度条来回流动（不知道确切进度）。
private struct FlowingBar: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            GeometryReader { proxy in
                let width = proxy.size.width
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                let x = (reduceMotion ? 0.5 : (1 - cos(t * 2 * .pi)) / 2) * width * 0.65
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color).frame(width: width * 0.35).offset(x: x)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// 重试中：倒计时小圈「8 秒后自动重试（第 2 次，共 3 次）」，一秒一跳。
private struct RetryCountdown: View {
    let attempt: Int
    let at: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = pow(2, Double(attempt))
            let left = max(0, Int(at.timeIntervalSince(context.date).rounded(.up)))
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(GrammarBadge.Kind.retrying.fill, lineWidth: 2)
                    Circle().trim(from: 0, to: Double(left) / total)
                        .stroke(GrammarBadge.Kind.retrying.text, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 13, height: 13)
                Text(L("\(left) 秒后自动重试（第 \(attempt) 次，共 \(GrammarDownloader.maxRetries) 次）",
                       "Retrying in \(left) s (try \(attempt) of \(GrammarDownloader.maxRetries))",
                       "\(left) 秒後に自動で再試行（\(GrammarDownloader.maxRetries) 回中 \(attempt) 回目）"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GrammarBadge.Kind.retrying.text)
            }
        }
    }
}

/// 两段选择，每段两行。选中的那段白底（深色 #636366）带淡阴影。
private struct LinePicker: View {
    let selection: GrammarLine
    let choose: (GrammarLine) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(GrammarLine.allCases) { line in
                let selected = line == selection
                Button { choose(line) } label: {
                    VStack(spacing: 1) {
                        Text(title(line)).font(.system(size: 15, weight: selected ? .semibold : .regular))
                        Text(subtitle(line)).font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? Color(light: 0xFFFFFF, dark: 0x636366) : .clear)
                            .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 3, y: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(line) + L("，", ", ", "、") + subtitle(line))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(.tertiarySystemFill)))
    }

    private func title(_ line: GrammarLine) -> String {
        switch line {
        case .global: return L("非中国大陆", "Outside Mainland China", "中国本土以外")
        case .cn: return L("中国大陆", "Mainland China", "中国本土")
        }
    }

    private func subtitle(_ line: GrammarLine) -> String {
        switch line {
        case .global: return L("万象 GitHub", "Wanxiang GitHub", "万象 GitHub")
        case .cn: return L("飞地服务器", "Enclave server", "Enclave サーバー")
        }
    }
}

/// 浅紫整条按钮：「暂停」「换到…线路下载」。
struct SoftPurpleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(AppColor.purple.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.softFill.opacity(configuration.isPressed ? 0.7 : 1)))
    }
}
