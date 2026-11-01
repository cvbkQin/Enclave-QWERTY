import SwiftUI

// 接口配置页的模型下拉（AC3，对齐清单第 60 条）：点模型一栏右边的「当前模型 ▼」，在这一行下面就地展开，不再弹 sheet。

/// 宽 300、圆角 14、阴影。顶行灰字「api.deepseek.com · 共 4 个」+「↻ 重新获取」；每行等宽字体模型名，
/// 当前的打 ✓ 加粗，「推荐」绿标签、「深度思考 · 较慢」橙标签（问答页不标）；隔一道灰缝，最后一行「✎ 手动输入模型名」。
/// 转圈、失败、空列表都在下拉里同一个位置。点一个即填入并收起，不自动测试。
struct ModelDropdown: View {
    let baseURL: String
    let apiKey: String
    let current: String
    /// 问答页不标「深度思考 · 较慢」。
    let answer: Bool
    var onPick: (String) -> Void
    /// 「手动输入模型名」：收起下拉、模型一栏换成输入框并聚焦。
    var onManual: () -> Void

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
        VStack(alignment: .leading, spacing: 0) {
            header
            content
            Rectangle().fill(Color(.systemGroupedBackground)).frame(height: 6)
            Button(action: onManual) {
                Label(L("手动输入模型名", "Type a model name", "モデル名を手入力"), systemImage: "pencil")
                    .font(.system(size: 15))
                    .foregroundStyle(DashColor.ai)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: 300)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(light: 0xFFFFFF, dark: 0x2C2C2E)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.18), radius: 14, y: 6)
        .padding(.bottom, 4)
        .task(id: loadID) { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Button { loadID += 1 } label: {
                Label(L("重新获取", "Reload", "再取得"), systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DashColor.ai)
            }
            .buttonStyle(.borderless)
            .disabled(models == nil && failure == nil)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private var subtitle: String {
        guard let models else { return host }
        return host + " · " + L("共 \(models.count) 个", "\(models.count) models", "\(models.count) 件")
    }

    @ViewBuilder
    private var content: some View {
        if let failure {
            failureView(failure.message, retry: failure != .unsupported)
        } else if let models {
            if models.isEmpty {
                failureView(L("服务商返回的列表是空的。", "The provider returned an empty list.", "サービスから空の一覧が返されました。"), retry: true)
            } else {
                list
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("正在向服务商获取…", "Asking the provider…", "サービスに問い合わせ中…")).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
    }

    /// 超过 8 个先给一行搜索；最多露出约 6 行，多了在框里滑。
    private var list: some View {
        VStack(spacing: 0) {
            if (models?.count ?? 0) > 8 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
                    TextField(L("搜索模型", "Search models", "モデルを検索"), text: $query)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemFill)))
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown, id: \.self) { model in
                        Button { onPick(model) } label: { row(model) }
                            .buttonStyle(.borderless)
                        if model != shown.last { Divider().padding(.leading, 38) }
                    }
                }
            }
            .frame(maxHeight: min(CGFloat(shown.count), 6) * 44)
        }
    }

    private func row(_ model: String) -> some View {
        let isCurrent = model == current.trimmingCharacters(in: .whitespaces)
        return HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DashColor.ai)
                .opacity(isCurrent ? 1 : 0)
                .frame(width: 16)
            Text(model)
                .font(.system(size: 14.5, weight: isCurrent ? .bold : .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if model == recommended { tag(L("推荐", "Recommended", "おすすめ"), fill: Color(light: 0xE3F4EA, dark: 0x173A24), text: Color(light: 0x248A3D, dark: 0x6EE7A0)) }
            if !answer, ModelList.isThinking(model) {
                tag(L("深度思考 · 较慢", "Thinking · slower", "深い思考・遅め"), fill: Color(light: 0xFFF4E5, dark: 0x3A2810), text: Color(light: 0xB45309, dark: 0xFDBA74))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    private func tag(_ title: String, fill: Color, text: Color) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill))
            .fixedSize()
    }

    /// 失败（或者服务商给了空列表）：原失败卡的文案 +「重试」。
    private func failureView(_ message: String, retry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: 0xFF9500))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("未能获取模型列表", "Couldn't load the model list", "モデル一覧を取得できませんでした")).font(.system(size: 14, weight: .semibold))
                    Text(message).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if retry {
                Button { loadID += 1 } label: {
                    Text(L("重试", "Retry", "再試行"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .background(Capsule().fill(DashColor.ai))
                }
                .buttonStyle(.borderless)
                .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func load() async {
        models = nil
        failure = nil
        do {
            models = try await ModelList.fetch(baseURL: baseURL, apiKey: apiKey)
        } catch let error as ModelList.Failure {
            failure = error
        } catch {
            failure = .network
        }
    }
}
