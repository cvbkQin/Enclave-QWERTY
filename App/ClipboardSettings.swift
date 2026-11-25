import SwiftUI

/// App › 键盘 › 「剪贴板」组（B1，CB4）：开关「剪贴板记录」+ 红字「清除剪贴板记录」（右边条数，要确认）。
/// 关掉开关：不再记录，已有的一起删掉。
struct ClipboardSettingsSection: View {
    /// 回到前台时换一个值，重新数一遍条数（键盘那边可能刚存过）。
    var refresh: UUID

    @State private var enabled = ClipboardHistory.isEnabled
    @State private var count = ClipboardHistory.count
    @State private var confirmsClear = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { enabled }, set: { value in
                enabled = value
                ClipboardHistory.isEnabled = value
                count = ClipboardHistory.count
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L("剪贴板记录", "Clipboard history", "クリップボード履歴"))
                        NewBadge()
                    }
                    Text(L("在键盘「常用 › 剪贴板」里留下你粘贴过的内容", "Keeps what you paste under Phrases › Clipboard on the keyboard",
                           "キーボードの「定型文 › クリップボード」に貼り付けた内容を残します"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
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
            if enabled { onFooter } else { offFooter }
        }
        .onAppear(perform: reload)
        .onChange(of: refresh) { _ in reload() }
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

    private var onFooter: some View {
        Text(L("只在你点「有新复制的内容，点一下粘贴」时才读剪贴板，这时系统会在顶部提示「飞地输入法粘贴自…」。记录只存在本机，最多 20 条，24 小时后自动删除，不备份、不同步。关掉后不再记录，已有的一起删掉。",
               "The clipboard is read only when you tap \"New copied text. Tap to paste\", and iOS shows \"Enclave pasted from…\" at the top. History stays on this iPhone, up to 20 items, deleted after 24 hours, never backed up or synced. Turning it off stops recording and deletes what's there.",
               "「新しくコピーした内容があります。タップで貼り付け」をタップしたときだけクリップボードを読み、そのとき iOS が上部に「Enclave が…からペースト」と表示します。履歴はこの iPhone にだけ最大 20 件保存され、24 時間後に自動で削除されます。バックアップや同期はしません。オフにすると記録をやめ、今ある履歴も削除します。"))
    }

    /// 关着时：说清楚现在的状态，不再说「关掉后…」。
    private var offFooter: some View {
        Text(L("剪贴板记录已关闭：键盘里照样可以粘贴，但不保存。打开后从下次粘贴开始记录，最多 20 条，24 小时后自动删除。",
               "Clipboard history is off: you can still paste on the keyboard, but nothing is kept. Once on, it records from your next paste, up to 20 items, deleted after 24 hours.",
               "クリップボード履歴はオフです：キーボードで貼り付けはできますが、保存しません。オンにすると次の貼り付けから記録し、最大 20 件、24 時間後に自動で削除します。"))
    }

    private func reload() {
        enabled = ClipboardHistory.isEnabled
        count = ClipboardHistory.count
    }
}
