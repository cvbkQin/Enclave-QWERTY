import SwiftUI

/// 场景实验室「一键应用」后键盘上的小手指引导（NH1–NH6）：只设好键盘、不自动执行，小手指一步步指给人点。
/// 没要求的场景 ✨ → 替换，有要求的场景 执行 → 替换，错字校对 ✨ → ▲▼。点了别处、开始打字或 10 秒没动就结束。
extension KeyboardModel {
    /// 小手指能指的按钮。
    enum CoachTarget: Hashable {
        case sparkle, run, replace, versions
    }

    struct Coach: Equatable {
        var steps: [CoachTarget]
        var index = 0
    }

    /// 小手现在指哪颗按钮：上一步点完、结果还没出来时停在上一颗按钮上变淡（dimmed）。
    var coachDisplay: (target: CoachTarget, dimmed: Bool)? {
        guard let coach, gate == nil else { return nil }
        let ready = coach.index == 0 || (!isRunning && hasResult)
        return ready ? (coach.steps[coach.index], false) : (coach.steps[coach.index - 1], true)
    }

    func startCoach(_ mark: LabCoachMark) {
        let steps: [CoachTarget]
        switch mark.flow {
        case .sparkle: steps = [.sparkle, .replace]
        case .run: steps = [.run, .replace]
        case .proofread: steps = [.sparkle, .versions]
        }
        // 键盘设成展开状态：结果卡片和替换 / 插入直接露出来；有要求的场景再打开提示词面板。
        if target == .card { finishCardEdit() }
        finishComposition()
        clearQuickStatus()
        aiExpanded = true
        styleMenuOpen = mark.flow == .run
        target = styleMenuOpen ? .instruction : .host
        coach = Coach(steps: steps)
        watchCoach()
    }

    /// 点了按钮：是这一步要点的就往下走，最后一步点完就结束；点的不是要点的按钮也结束。
    func coachTapped(_ target: CoachTarget) {
        guard let coach else { return }
        guard coach.steps[coach.index] == target, coach.index + 1 < coach.steps.count else {
            endCoach()
            return
        }
        self.coach?.index += 1
        coachTouched = true
    }

    /// 小手 0.2 秒淡出，这一轮引导结束。
    func endCoach() {
        guard coach != nil else { return }
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
