import SwiftUI

/// App › 键盘 › 「剪贴板」组（B1，CB4；T97 CA3）：开关「剪贴板记录」、「自动保存复制的内容」、「最多保存条数」10 / 20 / 50 / 100、
/// 红字「清除剪贴板记录」（右边条数，要确认）。关掉记录：不再记录，已有的一起删掉，自动保存也跟着关。
struct ClipboardSettingsSection: View {
    /// 回到前台时换一个值，重新数一遍条数（键盘那边可能刚存过）。
    var refresh: UUID

    @State private var enabled = ClipboardHistory.isEnabled
    @State private var count = ClipboardHistory.count
    @State private var autoSave = ClipboardHistory.autoSave
    /// 第一次打开自动保存先弹确认卡（CA4，挂在根视图上的居中卡片）：点「开启」才打开，点「取消」开关不动。
    @ObservedObject private var consent = AutoSaveConsent.shared
    @State private var limit = ClipboardHistory.maxItems
    /// 改小上限会删记录：先确认（CA3 ⑤），点取消分段退回原来的值。
    @State private var pendingLimit: Int?
    @State private var confirmsClear = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { enabled }, set: { value in
                enabled = value
                ClipboardHistory.isEnabled = value
                count = ClipboardHistory.count
                autoSave = ClipboardHistory.autoSave
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("剪贴板记录", "Clipboard history", "クリップボード履歴"))
                    Text(L("在键盘「常用 › 剪贴板」里留下你复制过的文字", "Keeps text you copy under Phrases › Clipboard on the keyboard",
                           "キーボードの「定型文 › クリップボード」にコピーしたテキストを残します"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            autoSaveRow
            limitRow
            Button { confirmsClear = true } label: {
                HStack {
                    Text(L("清除剪贴板记录", "Clear Clipboard History", "クリップボード履歴を消去"))
                        .foregroundStyle(count == 0 ? Color.secondary : Color(hex: 0xFF3B30))
                    Spacer()
                    Text(L("\(count) 条", "\(count)", "\(count) 件")).foregroundStyle(.secondary)
                }
            }
            .disabled(count == 0)
        } header: {
            Text(L("剪贴板", "Clipboard", "クリップボード"))
        } footer: {
            if !enabled { offFooter } else if autoSave { autoFooter } else { onFooter }
        }
        .onAppear(perform: reload)
        .onChange(of: refresh) { _ in reload() }
        // 确认卡收起（开启或取消）：照存着的值重画开关和脚注。
        .onChange(of: consent.presented) { showing in
            if !showing { autoSave = ClipboardHistory.autoSave }
        }
        .alert(shrinkTitle, isPresented: Binding(get: { pendingLimit != nil }, set: { if !$0 { pendingLimit = nil } })) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) { pendingLimit = nil }
            Button(shrinkButton, role: .destructive) {
                if let value = pendingLimit { applyLimit(value) }
                pendingLimit = nil
            }
        } message: {
            Text(shrinkMessage)
        }
        .alert(L("清除剪贴板记录？", "Clear clipboard history?", "クリップボード履歴を消去しますか？"), isPresented: $confirmsClear) {
            Button(L("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(L("清除", "Clear", "消去"), role: .destructive) {
                ClipboardHistory.clear()
                count = 0
            }
        } message: {
            Text(L("键盘「常用 › 剪贴板」里的记录会全部删除。", "Everything under Phrases › Clipboard on the keyboard will be deleted.",
                   "キーボードの「定型文 › クリップボード」の記録がすべて削除されます。"))
        }
    }

    /// 「自动保存复制的内容」（05 定的名字），带「新」标签。剪贴板记录关着时 40% 透明、拨不动，说明换一句。
    private var autoSaveRow: some View {
        Toggle(isOn: Binding(get: { enabled && autoSave }, set: { value in
            if value && ClipboardHistory.needsAutoSaveConsent(consentAt: ClipboardHistory.autoSaveConsentAt) {
                AutoSaveConsent.shared.present {
                    ClipboardHistory.autoSaveConsentAt = Date()
                    ClipboardHistory.autoSave = true
                }
                return
            }
            ClipboardHistory.autoSave = value
            autoSave = value
        })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L("自动保存复制的内容", "Auto-Save Copied Text", "コピーした内容を自動保存"))
                    NewBadge()
                }
                Text(enabled ? L("键盘显示时，新复制的文字自动存进记录，不用点开剪贴板",
                                 "Saves new copied text while the keyboard is showing, no need to open the clipboard",
                                 "キーボード表示中に、新しくコピーしたテキストを自動で履歴に保存します")
                             : L("要先打开上面的「剪贴板记录」", "Turn on Clipboard history above first", "先に上の「クリップボード履歴」をオンにしてください"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    /// 「最多保存条数」：右边分段 10 / 20 / 50 / 100，下面一行灰字。剪贴板记录关着时变灰、点不动，值保留。
    private var limitRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(L("最多保存条数", "Keep Up To", "最大保存件数"))
                Spacer(minLength: 8)
                Picker(L("最多保存条数", "Keep Up To", "最大保存件数"), selection: Binding(get: { limit }, set: { requestLimit($0) })) {
                    ForEach(ClipboardHistory.limitOptions, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Text(enabled ? L("超过就删掉最早的", "Oldest items are removed first", "超えたら古いものから削除します")
                         : L("剪贴板记录关着", "Clipboard history is off", "クリップボード履歴はオフです"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    /// 改大、或改小但现有条数不超过新上限：直接改；改小会删记录：先确认。
    private func requestLimit(_ value: Int) {
        guard value != limit else { return }
        if ClipboardHistory.removedCount(current: ClipboardHistory.count, limit: value) > 0 {
            pendingLimit = value
        } else {
            applyLimit(value)
        }
    }

    private func applyLimit(_ value: Int) {
        ClipboardHistory.setMaxItems(value)
        limit = ClipboardHistory.maxItems
        count = ClipboardHistory.count
    }

    private var shrinkTitle: String {
        let n = pendingLimit ?? limit
        return L("改成最多 \(n) 条？", "Keep only \(n) items?", "最大 \(n) 件に変更しますか？")
    }

    private var shrinkMessage: String {
        let n = pendingLimit ?? limit
        let m = ClipboardHistory.count
        let k = ClipboardHistory.removedCount(current: m, limit: n)
        return L("现在有 \(m) 条记录，最早的 \(k) 条会被删掉。", "You have \(m) items now. The oldest \(k) will be deleted.",
                 "現在 \(m) 件あります。古い \(k) 件が削除されます。")
    }

    private var shrinkButton: String {
        let n = pendingLimit ?? limit
        return L("改成 \(n) 条", "Keep \(n)", "\(n) 件にする")
    }

    /// 默认（方案 A）：点开剪贴板时才读，新复制的存成第一条、不粘贴。「20」跟着最多保存条数变。
    private var onFooter: some View {
        Text(L("点开键盘「常用 › 剪贴板」时才读剪贴板（点「帮回」时也会读取你复制的那段）：新复制的文字存成第一条，不会自动粘贴，这时系统会在顶部提示「飞地输入法粘贴自…」。密码管理器复制的密码、纯数字（如验证码）不保存。记录只存在本机，最多 \(limit) 条，24 小时后自动删除，不备份、不同步。关掉后不再记录，已有的一起删掉。",
               "The clipboard is read only when you open Phrases › Clipboard on the keyboard: newly copied text is saved as the first item and isn't pasted automatically (Help Reply also reads it when you tap it), and iOS shows \"Enclave pasted from…\" at the top. Passwords from password managers and digit-only text (like codes) aren't saved. History stays on this \(device), up to \(limit) items, deleted after 24 hours, never backed up or synced. Turning it off stops recording and deletes what's there.",
               "キーボードの「定型文 › クリップボード」を開いたときだけクリップボードを読みます（返信アシストをタップしたときも読み取ります）。新しくコピーしたテキストは先頭に保存され、自動では貼り付けません。そのとき iOS が上部に「Enclave が…からペースト」と表示します。パスワード管理アプリのパスワードや数字だけのテキスト（確認コードなど）は保存しません。履歴はこの \(device) にだけ最大 \(limit) 件保存され、24 時間後に自動で削除されます。バックアップや同期はしません。オフにすると記録をやめ、今ある履歴も削除します。"))
    }

    /// 自动保存开着：说清楚每次都会有系统提示、收起时不读。
    private var autoFooter: some View {
        Text(L("键盘显示时，一发现新复制的文字就读取并保存，每次系统都会在顶部提示「飞地输入法粘贴自…」。键盘收起时不读：收起期间复制了好几次，只存得到最后一次。密码管理器复制的密码、纯数字（如验证码）不保存。记录只存在本机，最多 \(limit) 条，24 小时后自动删除，不备份、不同步。",
               "While the keyboard is showing, newly copied text is read and saved right away, and iOS shows \"Enclave pasted from…\" at the top each time. Nothing is read while the keyboard is hidden: if you copy several times then, only the last one is saved. Passwords from password managers and digit-only text (like codes) aren't saved. History stays on this \(device), up to \(limit) items, deleted after 24 hours, never backed up or synced.",
               "キーボード表示中は、新しくコピーしたテキストをすぐに読み取って保存し、そのたびに iOS が上部に「Enclave が…からペースト」と表示します。キーボードが隠れている間は読みません。その間に何度かコピーしても、保存されるのは最後の 1 件だけです。パスワード管理アプリのパスワードや数字だけのテキスト（確認コードなど）は保存しません。履歴はこの \(device) にだけ最大 \(limit) 件保存され、24 時間後に自動で削除されます。バックアップや同期はしません。"))
    }

    /// 关着时：说清楚现在的状态，不再说「关掉后…」。
    private var offFooter: some View {
        Text(L("剪贴板记录已关闭：键盘里照样可以粘贴，但不保存，也不自动保存。打开后从下次点开剪贴板开始记录，最多 \(limit) 条，24 小时后自动删除。",
               "Clipboard history is off: you can still paste on the keyboard, but nothing is kept or auto-saved. Once on, it records from the next time you open the clipboard, up to \(limit) items, deleted after 24 hours.",
               "クリップボード履歴はオフです：キーボードで貼り付けはできますが、保存も自動保存もしません。オンにすると次にクリップボードを開いたときから記録し、最大 \(limit) 件、24 時間後に自動で削除します。"))
    }

    private var device: String { DeviceName.current }

    private func reload() {
        enabled = ClipboardHistory.isEnabled
        count = ClipboardHistory.count
        limit = ClipboardHistory.maxItems
        autoSave = ClipboardHistory.autoSave
    }
}
