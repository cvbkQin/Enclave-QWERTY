import SwiftUI

/// 使用指引「一键应用」后键盘上的小手指引导（NH1–NH6）：只设好键盘、不自动执行，小手指一步步指给人点。
/// 没要求的场景 ✨ → 替换，有要求的场景 执行 → 替换，错字校对 ✨ → ▲▼。点了别处、开始打字或 10 秒没动就结束。
extension KeyboardModel {
    /// 小手指能指的按钮。
    typealias CoachTarget = LabCoachMark.Step

    struct Coach: Equatable {
        var steps: [CoachTarget]
        var index = 0
        /// 快速模式：唯一一步点完后变淡停在原处，等替换成功或失败再淡出。
        var finishing = false
    }

    /// 现在该点第几步：▲▼ 那一步只有一个版本时跳过，直接指下一步。
    private func coachStep(_ coach: Coach) -> Int {
        let index = coach.index
        guard coach.steps[index] == .versions, index + 1 < coach.steps.count,
              (session?.versions.count ?? 0) <= 1 else { return index }
        return index + 1
    }

    /// 小手现在指哪颗按钮：上一步点完、结果还没出来时停在上一颗按钮上变淡（dimmed）。
    var coachDisplay: (target: CoachTarget, dimmed: Bool)? {
        guard let coach, gate == nil else { return nil }
        if coach.finishing { return (coach.steps[coach.index], true) }
        let ready = coach.index == 0 || (!isRunning && hasResult)
        return ready ? (coach.steps[coachStep(coach)], false) : (coach.steps[coach.index - 1], true)
    }

    func startCoach(_ mark: LabCoachMark) {
        // 替换 / 插入场景展开结果区；快速场景收起，有要求的只打开提示词面板。
        if target == .card { finishCardEdit() }
        finishComposition()
        clearQuickStatus()
        aiExpanded = mark.expanded
        styleMenuOpen = mark.menuOpen
        target = styleMenuOpen ? .instruction : .host
        coach = Coach(steps: mark.steps)
        watchCoach()
    }

    /// 点了按钮：是这一步要点的就往下走；快速模式点完唯一一步后变淡等结果；点的不是要点的按钮就结束。
    func coachTapped(_ target: CoachTarget) {
        guard let coach, !coach.finishing else { return }
        let step = coachStep(coach)
        guard coach.steps[step] == target else {
            endCoach()
            return
        }
        if step + 1 < coach.steps.count {
            self.coach?.index = step + 1
        } else if target == .sparkle || target == .run {
            self.coach?.finishing = true
        } else {
            endCoach()
            return
        }
        coachTouched = true
    }

    /// 小手 0.2 秒淡出，这一轮引导结束。
    func endCoach() {
        guard coach != nil else { return }
        #if DEBUG
        NSLog("EnclaveCoach end: %@", Thread.callStackSymbols.prefix(6).joined(separator: " | "))
        #endif
        coachTask?.cancel()
        coachTask = nil
        withAnimation(.easeOut(duration: 0.2)) { coach = nil }
    }

    /// 10 秒没动就结束；等 AI 生成的时候不算没动。
    private func watchCoach() {
        coachTask?.cancel()
        coachTask = Task { @MainActor [weak self] in
            var idleSince = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, self.coach != nil, !Task.isCancelled else { return }
                // 等 AI 生成、或者在看「润色前确认一下」之类的提示卡时，都不算没动。
                if self.isRunning || self.coachTouched || self.gate != nil {
                    idleSince = Date()
                    self.coachTouched = false
                }
                if Date().timeIntervalSince(idleSince) > 10 {
                    self.endCoach()
                    return
                }
            }
        }
    }
}
