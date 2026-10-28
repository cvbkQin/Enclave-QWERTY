import SwiftUI

// 接口页「选择」模型（ML1–ML4）：模型一栏右边的小按钮，和点开后的列表 sheet。

/// 模型一栏右边的「选择」：高 28、圆角 14、#ECEAFD 底、#4A3BD6 字。
struct ModelPickButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet").font(.system(size: 12, weight: .semibold))
                Text(L("选择", "Choose", "選択")).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color(light: 0x4A3BD6, dark: 0xB4A9FF))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(Color(light: 0xECEAFD, dark: 0x2E2766)))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L("从服务商的列表选择模型", "Choose a model from the provider's list", "サービスの一覧からモデルを選択"))
    }
}

/// 选择模型的 sheet：转圈 → 列表（或失败卡）。点一个即填入并关闭，不自动测试。
struct ModelPickerSheet: View {
    let baseURL: String
    let apiKey: String
    let current: String
    /// 问答页不标「深度思考 · 较慢」。
    let answer: Bool
    var onPick: (String) -> Void
    /// 「手动输入模型名」：关掉 sheet、聚焦模型一栏。
    var onManual: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var models: [String]?
    @State private var failure: ModelList.Failure?
    @State private var query = ""
    @State private var loadID = 0

    private var provider: Provider { Provider.detect(baseURL) }
    private var host: String { URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host ?? baseURL }
    private var recommended: String? { answer ? provider.answerPreset?.model : provider.preset?.model }

    private var shown: [String] {
        let all = ModelList.ordered(models ?? [], current: current)
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(DashColor.page.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .task(id: loadID) { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("选择模型", "Choose a model", "モデルを選択")).font(.system(size: 20, weight: .bold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            roundButton("arrow.clockwise", L("重新获取", "Reload", "再取得")) { loadID += 1 }
                .disabled(models == nil && failure == nil)
            roundButton("xmark", L("关闭", "Close", "閉じる")) { dismiss() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        var parts = [String]()
        if provider != .custom { parts.append(provider.title) }
        parts.append(host)
        if let models { parts.append(L("共 \(models.count) 个", "\(models.count) models", "\(models.count) 件")) }
        return parts.joined(separator: " · ")
    }

    private func roundButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var content: some View {
        if let failure {
            failureCard(failure)
        } else if let models {
            if models.isEmpty {
                failureCard(nil)
            } else {
                list(models)
            }
        } else {
            VStack(spacing: 10) {
                ProgressView()
                Text(L("正在向服务商获取…", "Asking the provider…", "サービスに問い合わせ中…")).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func list(_ models: [String]) -> some View {
        List {
            if models.count > 8 {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(L("搜索模型", "Search models", "モデルを検索"), text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }
            Section {
                ForEach(shown, id: \.self) { model in
                    Button {
                        onPick(model)
                        dismiss()
                    } label: {
                        row(model)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(L("列表来自 \(host) 的 \(ModelList.isOllama(baseURL) ? "/api/tags" : "/models") 接口。点一个即填入模型一栏并关闭，不会自动测试。",
                       "From \(host)'s \(ModelList.isOllama(baseURL) ? "/api/tags" : "/models") endpoint. Tap one to fill in the model field. It isn't tested automatically.",
                       "\(host) の \(ModelList.isOllama(baseURL) ? "/api/tags" : "/models") から取得した一覧です。タップするとモデル欄に入力して閉じます。自動ではテストしません。"))
            }
            Section {
                manualButton
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity)
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func row(_ model: String) -> some View {
        let isCurrent = model == current.trimmingCharacters(in: .whitespaces)
        return HStack(spacing: 8) {
            Text(model)
                .font(.system(size: 16, weight: isCurrent ? .bold : .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            if isCurrent { tag(L("当前", "Current", "現在"), fill: Color(light: 0xECEAFD, dark: 0x2E2766), text: Color(light: 0x4A3BD6, dark: 0xB4A9FF)) }
            if model == recommended { tag(L("推荐", "Recommended", "おすすめ"), fill: Color(light: 0xE3F4EA, dark: 0x173A24), text: Color(light: 0x248A3D, dark: 0x6EE7A0)) }
            if !answer, ModelList.isThinking(model) {
                tag(L("深度思考 · 较慢", "Thinking · slower", "深い思考・遅め"), fill: Color(light: 0xFFF4E5, dark: 0x3A2810), text: Color(light: 0xB45309, dark: 0xFDBA74))
            }
            Spacer(minLength: 4)
            if isCurrent { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(DashColor.ai) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    private func tag(_ title: String, fill: Color, text: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill))
            .fixedSize()
    }

    /// 失败（或者服务商给了空列表）时的白卡。
    private func failureCard(_ failure: ModelList.Failure?) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                DashCard {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(hex: 0xFF9500))
                        Text(L("未能获取模型列表", "Couldn't load the model list", "モデル一覧を取得できませんでした")).font(.headline)
                        Text(failure?.message ?? L("服务商返回的列表是空的。", "The provider returned an empty list.", "サービスから空の一覧が返されました。"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if failure != .unsupported {
                            Button { loadID += 1 } label: {
                                Text(L("重试", "Retry", "再試行"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 28)
                                    .frame(height: 36)
                                    .background(Capsule().fill(DashColor.ai))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                manualButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private var manualButton: some View {
        Button(L("手动输入模型名", "Type a model name", "モデル名を手入力")) {
            dismiss()
            onManual()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(DashColor.ai)
    }

    private func load() async {
        models = nil
        failure = nil
        do {
            let list = try await ModelList.fetch(baseURL: baseURL, apiKey: apiKey)
            models = list
        } catch let error as ModelList.Failure {
            failure = error
        } catch {
            failure = .network
        }
    }
}
