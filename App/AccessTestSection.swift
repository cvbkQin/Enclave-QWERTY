import SwiftUI

/// 开发者版装机（DEV_BUILD=YES）和模拟器 Debug：设置里切 AI 购买状态，测试试用、到期每天 10 次、已解锁三种样子。
/// 写进 App Group（AIAccess.setDebug），键盘下次弹出就按新状态走。TestFlight、公测、正式包不显示，也不生效（AIAccess.debugAllowed）。
struct AccessTestSection: View {
    @ObservedObject private var unlock = UnlockStore.shared
    @State private var choice: Choice = .real
    @State private var trialDays = 3
    @State private var usesLeft = AIAccess.usesLeftToday

    enum Choice: Hashable { case unlocked, real, trial, expired }

    static var shows: Bool {
        #if DEBUG
        return true
        #else
        return BuiltinAPI.isDevBuild
        #endif
    }

    var body: some View {
        Section {
            Picker(selection: $choice) {
                Text(L("已解锁", "Unlocked", "購入済み")).tag(Choice.unlocked)
                Text(L("跟随真实", "Real status", "実際の状態")).tag(Choice.real)
                Text(L("试用中", "Trial", "お試し中")).tag(Choice.trial)
                Text(L("已到期（每天 \(AIAccess.dailyFreeUses) 次）", "Expired (\(AIAccess.dailyFreeUses) a day)",
                       "期限切れ（1 日 \(AIAccess.dailyFreeUses) 回）")).tag(Choice.expired)
            } label: {
                HStack(spacing: 6) {
                    Text(L("AI 购买状态", "AI purchase status", "AI の購入状態"))
                    Text(L("测试", "Test", "テスト"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(light: 0x9A4D00, dark: 0xF2A65E))
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(light: 0xFDEBD8, dark: 0x3A2612)))
                }
            }
            .pickerStyle(.menu)
            if choice == .trial {
                Stepper(value: $trialDays, in: 1...AIAccess.trialDays) {
                    Text(L("试用剩 \(trialDays) 天", "\(trialDays) days left", "残り \(trialDays) 日"))
                }
            }
            if choice == .expired {
                HStack {
                    Text(L("今天还剩 \(usesLeft) 次", "\(usesLeft) left today", "今日の残り \(usesLeft) 回"))
                    Spacer()
                    Button(L("清零重来", "Reset", "リセット")) {
                        AIAccess.resetUsesToday()
                        usesLeft = AIAccess.usesLeftToday
                    }
                }
            }
        } footer: {
            Text(L("只在开发者版显示，用来测试试用、到期和已解锁。改完键盘马上按新状态走。",
                   "Developer builds only. Switches the trial, expired and unlocked states for testing.",
                   "開発版のみ。お試し・期限切れ・購入済みをテスト用に切り替えます。"))
        }
        .onAppear(perform: load)
        .onChange(of: choice) { _ in save() }
        .onChange(of: trialDays) { _ in save() }
    }

    private func load() {
        let value = AIAccess.debugValue ?? ""
        if value == "unlocked" || value == AIAccess.testFlightUnlock {
            choice = .unlocked
        } else if value == "expired" {
            choice = .expired
        } else if value.hasPrefix("days:") {
            trialDays = min(max(Int(value.dropFirst(5)) ?? 3, 1), AIAccess.trialDays)
            choice = .trial
        } else {
            choice = .real
        }
        usesLeft = AIAccess.usesLeftToday
    }

    private func save() {
        switch choice {
        case .unlocked: AIAccess.setDebug("unlocked")
        case .real: AIAccess.setDebug(nil)
        case .trial: AIAccess.setDebug("days:\(trialDays)")
        case .expired: AIAccess.setDebug("expired")
        }
        usesLeft = AIAccess.usesLeftToday
        unlock.reloadAccess()
    }
}
