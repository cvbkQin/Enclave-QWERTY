import CoreText
import SwiftUI
import UIKit

/// 键盘尺寸，按 iOS 26 自带简体拼音键盘在 402pt 宽的 iPhone 上量出来的。键盘高度也从这里算。
enum KeyboardMetrics {
    /// 一个按键格子的高度（含上下间隙）：行距 54，按键本身 43。
    static let slotHeight: CGFloat = 54
    static let keyInsetX: CGFloat = 3.1
    static let keyInsetY: CGFloat = 5.5
    static let keysHeight: CGFloat = slotHeight * 4
    /// 全键盘底行「中/英」键宽 42pt，字 14pt；九宫格的「中/英」16pt。
    static let toggleKeyWidth: CGFloat = 42
    static let toggleFontSize: CGFloat = 14
    static let nineToggleFontSize: CGFloat = 16
    /// 全键盘 Shift、删除键画出来的宽度（触摸范围仍是 1.5 格）。
    static let shiftKeyWidth: CGFloat = 45
    /// 九宫格对齐原生：键高 46、行距 7（每行 53），列距 6、两边各 7，五列等宽。
    /// 四行 212pt，比按键区少 4pt，上下各留 2pt，键盘总高不变。
    static let nineKeyHeight: CGFloat = 46
    static let nineRowGap: CGFloat = 7
    static let nineColumnGap: CGFloat = 6
    static let nineSideMargin: CGFloat = 7
    static let nineRowPitch: CGFloat = nineKeyHeight + nineRowGap
    static let nineTopOffset: CGFloat = (keysHeight - nineRowPitch * 4) / 2
    static let nineKeyInsetX: CGFloat = nineColumnGap / 2
    static let nineKeyInsetY: CGFloat = nineRowGap / 2
    /// 打拼音时左列音节栏每格 38pt，四格正好是三个键加两条缝。
    static let pinyinCellHeight: CGFloat = 38

    /// AI 栏：展开键、✨ 润色、风格菜单、撤销重做，收起和展开都是这一行，紧贴按键上方。
    static let topRow: CGFloat = 44
    /// AI 栏里按钮的高度；✨ 润色按钮 84×34。
    static let chipHeight: CGFloat = 34
    static let polishButtonWidth: CGFloat = 58
    /// 结果卡片：默认两行，展开到五行，再多就在卡片里滚动。
    static let cardHeight: CGFloat = 60
    static let expandedCardHeight: CGFloat = 120
    /// 「AI 生成」标签（CP8）占的高度。
    static let aiLabelHeight: CGFloat = 22

    static func cardHeight(tall: Bool, aiLabel: Bool) -> CGFloat {
        (tall ? expandedCardHeight : cardHeight) + (aiLabel ? aiLabelHeight : 0)
    }
    static let actionRow: CGFloat = 34
    /// 「正式▾」浮层：风格行 + 要求行，底下一个小尖角指向按钮。
    static let menuHeight: CGFloat = 94
    /// 要求框（NQ1–NQ3）：14pt，行高 19，写长了自动换行，最多 3 行；一行时还是 32 高。
    static let requestLineHeight: CGFloat = 19
    static func requestFieldHeight(lines: Int) -> CGFloat {
        lines <= 1 ? 32 : 16 + requestLineHeight * CGFloat(min(lines, 3))
    }
    /// 要求框变高时面板跟着加高。
    static func menuHeight(requestLines: Int) -> CGFloat {
        menuHeight + requestFieldHeight(lines: requestLines) - requestFieldHeight(lines: 1)
    }
    /// 试用最后 3 天的提示条（K3）。
    static let trialReminderHeight: CGFloat = 34
    static let panelSpacing: CGFloat = 5
    static let panelTop: CGFloat = 6
    static let sidePadding: CGFloat = 3.7

    /// 点「润色」时 AI 栏上方的提示卡：没开完全访问（P02）、首次发送前确认（P03），换了地址时多一行旧地址（P04）。
    static func gateHeight(_ gate: KeyboardModel.AIGate) -> CGFloat {
        switch gate {
        case .fullAccess: return 188
        case .privacy: return 76
        case .noKey: return 76
        case .consent(_, let previous): return previous == nil ? 178 : 196
        case .quotaUsed: return 196
        }
    }

    /// 键盘总高度：AI 栏 + 按键，展开时上面加结果卡片和动作行，打开风格菜单时再加一块。
    /// 提示卡出现时只留它一块，不和结果卡片、风格菜单叠在一起。
    static func height(expanded: Bool, cardExpanded: Bool, menuOpen: Bool, gate: KeyboardModel.AIGate? = nil,
                       reminder: Bool = false, requestLines: Int = 1, aiLabel: Bool = false) -> CGFloat {
        var height = topRow + keysHeight
        if let gate { return height + panelTop + gateHeight(gate) }
        if reminder { height += panelTop + trialReminderHeight }
        if expanded {
            height += panelTop + cardHeight(tall: cardExpanded, aiLabel: aiLabel) + panelSpacing + actionRow
        }
        if menuOpen {
            height += menuHeight(requestLines: requestLines) + panelSpacing + (expanded ? 0 : panelTop)
        }
        return height
    }
}

/// 按键颜色，取自 iOS 26 键盘：字符键和功能键同色，没有阴影；按下的功能键变灰。
enum KeyStyle {
    static let charKey = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 71 / 255, green: 71 / 255, blue: 73 / 255, alpha: 1) : .white })
    static let functionKey = charKey
    static let pressedKey = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.43, alpha: 1) : UIColor(red: 0.70, green: 0.72, blue: 0.76, alpha: 1) })
    static let cornerRadius: CGFloat = 8.5

    static let letterFont = Font.system(size: 24)
    static let symbolFont = Font.system(size: 22)
    /// 九宫格的字母键、标点键、123、#@¥、^^：16pt，字距 1pt。
    static let nineKeyFont = Font.system(size: 16)
    static let functionFont = Font.system(size: 17)
    static let iconFont = Font.system(size: 19, weight: .regular)

    /// 数字和符号层里的（）？！键帽画成半角字形（上屏的仍是全角字符），全角居中后反而显大。
    /// ，。、：；改用 CenteredGlyph 画全角字形，和英文页的半角标点一眼能分开。
    private static let halfWidthCaps: [String: String] = [
        "（": "(", "）": ")", "？": "?", "！": "!",
    ]

    /// 键帽上画成居中全角字形的中文标点（，。、用 ChinesePunctMark 的矢量图）。
    static let centeredGlyphCaps: Set<String> = ["：", "；"]

    static func capText(_ symbol: String) -> String { halfWidthCaps[symbol] ?? symbol }

    /// 《》用字体的 halt 特性收窄成半宽，其余照常。
    static func capFont(for symbol: String) -> Font {
        guard symbol == "《" || symbol == "》" else { return symbolFont }
        let base = UIFont.systemFont(ofSize: 22)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kTextSpacingType,
                                UIFontDescriptor.FeatureKey.selector: kAltHalfWidthTextSelector]],
        ])
        return Font(UIFont(descriptor: descriptor, size: 22))
    }
}

/// 品牌色：紫色主色、渐变、菜单和要求框的淡紫底。
enum Brand {
    static let purple = Color(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255)
    /// 紫色用作文字、图标、线条时：深色模式下 #5B4BE8 看不清，换成 #B4A9FF。实心按钮底色仍用 purple。
    static let purpleText = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xB4 / 255, green: 0xA9 / 255, blue: 0xFF / 255, alpha: 1)
        : UIColor(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255, alpha: 1) })
    /// 深色模式下「选中」用浅灰底黑字（选中的风格、打开的「自动 ^」）：#F2F2F7 / #1C1C1E。
    private static let darkSelectedFill = UIColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1)
    private static let darkSelectedText = UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
    /// 流光边框和新结果细边用的渐变：#4F46E5 → #7C3AED → #FDE68A → #A78BFA。
    static let gradient: [Color] = [
        Color(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255),
        Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255),
        Color(red: 0xFD / 255, green: 0xE6 / 255, blue: 0x8A / 255),
        Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255),
    ]
    static let violet = gradient[1]
    static let gold = gradient[2]
    /// 「再润」的文字色 #4A3BD6。
    static let deepPurple = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xC4 / 255, green: 0xB5 / 255, blue: 0xFD / 255, alpha: 1)
        : UIColor(red: 0x4A / 255, green: 0x3B / 255, blue: 0xD6 / 255, alpha: 1) })
    /// 「正式▾」按钮打开时的底色 #F4F2FF，深色 #F2F2F7。
    static let menuFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? darkSelectedFill
        : UIColor(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xFF / 255, alpha: 1) })
    /// 「正式▾」打开时的字和箭头：浅色紫，深色 #1C1C1E。描边只在浅色模式画。
    static let menuText = Color(UIColor { $0.userInterfaceStyle == .dark
        ? darkSelectedText : UIColor(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255, alpha: 1) })
    static let menuStroke = Color(UIColor { $0.userInterfaceStyle == .dark
        ? .clear : UIColor(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255, alpha: 1) })
    /// AI 栏展开键（方案 B）展开时：浅紫底 #ECEAFD + #8B7CF6 内描边、紫色图标；深色沿用选择器打开时的配色。
    static let toggleOpenFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? darkSelectedFill : UIColor(red: 0xEC / 255, green: 0xEA / 255, blue: 0xFD / 255, alpha: 1) })
    static let toggleOpenStroke = Color(UIColor { $0.userInterfaceStyle == .dark
        ? .clear : UIColor(red: 0x8B / 255, green: 0x7C / 255, blue: 0xF6 / 255, alpha: 1) })
    static let toggleOpenIcon = Color(UIColor { $0.userInterfaceStyle == .dark
        ? darkSelectedText : UIColor(red: 0x4A / 255, green: 0x3B / 255, blue: 0xD6 / 255, alpha: 1) })
    /// 收起时有没看过的新结果：右上角的紫点 #7C3AED，外圈描一圈键盘底色。
    static let newResultDot = Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
    /// 键盘底色，对齐系统键盘面板（顶上那条系统留的边、地球键那一行）：浅色 #E3E4E9，深色 #222223。
    /// 浅色原来是 #E0E1E8，真机 iOS 27 截图里比面板暗 2–3 级，键盘顶上那条系统边看着像多出来的一层。
    static let keyboardBackUI = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x22 / 255, green: 0x22 / 255, blue: 0x23 / 255, alpha: 1)
        : UIColor(red: 0xE3 / 255, green: 0xE4 / 255, blue: 0xE9 / 255, alpha: 1) }
    static let keyboardBack = Color(keyboardBackUI)
    /// 选择器名字和 ▾ 之间的竖线：平时 #D1D1D6（深色 #6E6E73），打开或「按要求」时 #B4A9FF（深色是浅灰底，用 #C7C7CC）。
    static let chipDivider = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x6E / 255, green: 0x6E / 255, blue: 0x73 / 255, alpha: 1)
        : UIColor(red: 0xD1 / 255, green: 0xD1 / 255, blue: 0xD6 / 255, alpha: 1) })
    static let chipDividerOn = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255, alpha: 1)
        : UIColor(red: 0xB4 / 255, green: 0xA9 / 255, blue: 0xFF / 255, alpha: 1) })
    /// 「AI 生成」标签（CP8）：底 #F2F2F7 / 深色 #3A3A3C，字 #6B6B73 / 深色 #AEAEB2。
    static let aiTagFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
        : UIColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1) })
    static let aiTagText = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xAE / 255, green: 0xAE / 255, blue: 0xB2 / 255, alpha: 1)
        : UIColor(red: 0x6B / 255, green: 0x6B / 255, blue: 0x73 / 255, alpha: 1) })
    /// 快速模式替换后的「AI 生成 · 已替换」胶囊（CP9）：底 #ECEAFD、字 #4A3BD6；深色用紫 28% 底、#B4A9FF 字。
    static let replacedPillFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x7C / 255, green: 0x6C / 255, blue: 0xF6 / 255, alpha: 0.28)
        : UIColor(red: 0xEC / 255, green: 0xEA / 255, blue: 0xFD / 255, alpha: 1) })
    static let replacedPillText = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xB4 / 255, green: 0xA9 / 255, blue: 0xFF / 255, alpha: 1)
        : UIColor(red: 0x4A / 255, green: 0x3B / 255, blue: 0xD6 / 255, alpha: 1) })
    /// 收起、有新结果时展开键的图标：#4A3BD6，深色键上看不清，深色用 #B4A9FF。
    static let newResultIcon = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xB4 / 255, green: 0xA9 / 255, blue: 0xFF / 255, alpha: 1)
        : UIColor(red: 0x4A / 255, green: 0x3B / 255, blue: 0xD6 / 255, alpha: 1) })
    /// 「正式▾」浮层（清爽紫）：纯白底，深色模式用系统深灰。
    static let panelFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1) : .white })
    /// 浮层里「风格」「要求」两个字 #3A3A3C。
    static let panelLabel = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.78, alpha: 1) : UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1) })
    /// 结果卡片「插入」：135° #0891B2 → #6366F1。
    static let insertGradient = LinearGradient(
        colors: [Color(red: 0x08 / 255, green: 0x91 / 255, blue: 0xB2 / 255),
                 Color(red: 0x63 / 255, green: 0x66 / 255, blue: 0xF1 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    /// 不能点的「替换」「插入」：#E5E5EA 底、#8E8E93 字。
    static let disabledFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.24, alpha: 1) : UIColor(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xEA / 255, alpha: 1) })
    static let disabledText = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
    /// 候选来自常用词的小圆点 #8B7CF6。
    static let commonWordDot = Color(red: 0x8B / 255, green: 0x7C / 255, blue: 0xF6 / 255)
    /// 设置路径里的「>」#AEAEB2。
    static let pathSeparator = Color(red: 0xAE / 255, green: 0xAE / 255, blue: 0xB2 / 255)
    /// 提示卡正文 #3A3A3C、说明 #6B6B73。
    static let cardBody = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.85, alpha: 1) : UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1) })
    static let cardNote = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.62, alpha: 1) : UIColor(red: 0x6B / 255, green: 0x6B / 255, blue: 0x73 / 255, alpha: 1) })
    /// 润色按钮上的小锁：#8E8E93 圆，外圈 #DCDEE4。
    static let lockFill = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
    static let lockRing = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.25, alpha: 1) : UIColor(red: 0xDC / 255, green: 0xDE / 255, blue: 0xE4 / 255, alpha: 1) })
    /// 确认卡标题里的星星、隐私政策链接 #5B4BE8。
    static let tagSelectedText = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xB4 / 255, green: 0xA9 / 255, blue: 0xFF / 255, alpha: 1)
        : UIColor(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255, alpha: 1) })
    /// 没选中的风格标签、没激活的要求框 #F2F2F7。
    static let tagFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)
        : UIColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1) })
    /// 选中的风格标签：#ECEAFD 底、#4A3BD6 字，1pt #D6D1FA 内描边；深色 #F2F2F7 底、#1C1C1E 字，无描边。
    static let tagSelectedFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? darkSelectedFill : UIColor(red: 0xEC / 255, green: 0xEA / 255, blue: 0xFD / 255, alpha: 1) })
    static let tagSelectedLabel = Color(UIColor { $0.userInterfaceStyle == .dark
        ? darkSelectedText : UIColor(red: 0x4A / 255, green: 0x3B / 255, blue: 0xD6 / 255, alpha: 1) })
    static let tagSelectedStroke = Color(UIColor { $0.userInterfaceStyle == .dark
        ? .clear : UIColor(red: 0xD6 / 255, green: 0xD1 / 255, blue: 0xFA / 255, alpha: 1) })
    /// 没选中的风格标签文字：深色 #EBEBF5。
    static let tagLabel = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xEB / 255, green: 0xEB / 255, blue: 0xF5 / 255, alpha: 1) : .label })
    /// 要求框激活：浅色白底紫边紫光标，深色 #1C1C1E 底、#F2F2F7 边和光标。
    static let fieldActiveFill = Color(UIColor { $0.userInterfaceStyle == .dark ? darkSelectedText : .white })
    static let fieldActiveLine = Color(UIColor { $0.userInterfaceStyle == .dark
        ? darkSelectedFill : UIColor(red: 0x5B / 255, green: 0x4B / 255, blue: 0xE8 / 255, alpha: 1) })
    /// 要求框里写了的字 #3A3A3C；占位字和没激活的铅笔 #8E8E93。
    static let fieldText = Color(UIColor { $0.userInterfaceStyle == .dark
        ? darkSelectedFill : UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1) })
    static let fieldPlaceholder = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
    /// 要求框的清空按钮：#C7C7CC 圆、白叉。
    static let fieldClear = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.45, alpha: 1) : UIColor(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255, alpha: 1) })
    /// 「再润」：135° 紫到粉 #A855F7 → #EC4899。
    static let rerunGradient = LinearGradient(
        colors: [Color(red: 0xA8 / 255, green: 0x55 / 255, blue: 0xF7 / 255),
                 Color(red: 0xEC / 255, green: 0x48 / 255, blue: 0x99 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let softFill = purple.opacity(0.14)
    /// 换行、确认和空输入框时的发送键：浅紫底 #ECEAFD，字和图标用 deepPurple #4A3BD6。
    static let returnSoftFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.24, green: 0.21, blue: 0.40, alpha: 1)
        : UIColor(red: 0xEC / 255, green: 0xEA / 255, blue: 0xFD / 255, alpha: 1) })
    /// 「中/英」键：当前语言那个字 #1C1C1E，另一个 #AEAEB2，斜杠 #C7C7CC。
    static let toggleActive = Color(UIColor { $0.userInterfaceStyle == .dark
        ? .white : UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1) })
    static let toggleInactive = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.55, alpha: 1) : UIColor(red: 0xAE / 255, green: 0xAE / 255, blue: 0xB2 / 255, alpha: 1) })
    static let toggleSlash = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.45, alpha: 1) : UIColor(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255, alpha: 1) })
    /// 九宫格长按十字弹层中间那格 #E6E5EB。
    static let crossCenterFill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.36, alpha: 1)
        : UIColor(red: 0xE6 / 255, green: 0xE5 / 255, blue: 0xEB / 255, alpha: 1) })
}

/// 四角星，logo 星星组的一颗。
struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width / 2, h = rect.height / 2, k: CGFloat = 0.22
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - h))
        path.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: CGPoint(x: c.x + w * k, y: c.y - h * k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h), control: CGPoint(x: c.x + w * k, y: c.y + h * k))
        path.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), control: CGPoint(x: c.x - w * k, y: c.y + h * k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h), control: CGPoint(x: c.x - w * k, y: c.y - h * k))
        path.closeSubpath()
        return path
    }
}

/// logo 那组星星：一颗大星、五颗小星。animating 时小星错开闪烁，大星轻轻放大带金色微光，周期 1.6 秒，不旋转。
struct SparkleMark: View {
    var size: CGFloat
    var color: Color
    var animating = false

    /// 每颗星：中心位置、直径（都按图标边长的比例）、闪烁的起始相位。
    private static let stars: [(x: CGFloat, y: CGFloat, d: CGFloat, phase: Double)] = [
        (0.40, 0.58, 0.66, 0),
        (0.80, 0.18, 0.28, 0.0),
        (0.90, 0.60, 0.16, 0.35),
        (0.16, 0.14, 0.16, 0.6),
        (0.70, 0.92, 0.14, 0.2),
        (0.08, 0.88, 0.12, 0.8),
    ]

    var body: some View {
        if animating {
            TimelineView(.animation) { context in
                cluster(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            cluster(time: nil)
        }
    }

    private func cluster(time: TimeInterval?) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.stars.enumerated()), id: \.offset) { index, star in
                let wave = time.map { (1 - cos(2 * .pi * ($0 / 1.6 + star.phase))) / 2 } ?? 0
                let scale = index == 0 ? 1 + 0.08 * wave : 1 - 0.4 * wave
                FourPointStar()
                    .fill(color)
                    .frame(width: size * star.d, height: size * star.d)
                    .scaleEffect(scale)
                    .opacity(index == 0 ? 1 : 1 - 0.7 * wave)
                    .shadow(color: index == 0 && time != nil ? Brand.gold.opacity(0.8 * wave) : .clear, radius: 2)
                    .position(x: size * star.x, y: size * star.y)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 按键外观：圆角、底色、底部细阴影。外面留出间隙，间隙也能点到这个键，和系统键盘一样没有死区。
struct KeyCap<Content: View>: View {
    var fill: Color
    var insetX = KeyboardMetrics.keyInsetX
    var insetY = KeyboardMetrics.keyInsetY
    var content: Content

    init(fill: Color, insetX: CGFloat = KeyboardMetrics.keyInsetX, insetY: CGFloat = KeyboardMetrics.keyInsetY,
         @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.insetX = insetX
        self.insetY = insetY
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: KeyStyle.cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .padding(.horizontal, insetX)
            .padding(.vertical, insetY)
            .contentShape(Rectangle())
    }
}

/// 字符键：浅色底。
struct CharKey: View {
    var title: String
    var font: Font = KeyStyle.letterFont
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyCap(fill: KeyStyle.charKey) {
                Text(title).font(font).foregroundStyle(Color.primary)
            }
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// 功能键：深色底，可高亮成蓝色。
struct FunctionKey: View {
    var title: String?
    var systemImage: String?
    var highlighted = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyCap(fill: highlighted ? Brand.purple : KeyStyle.functionKey) {
                Group {
                    if let systemImage {
                        Image(systemName: systemImage).font(KeyStyle.iconFont)
                    } else {
                        Text(title ?? "").font(KeyStyle.functionFont)
                    }
                }
                .foregroundStyle(highlighted ? Color.white : Color.primary)
            }
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// 按住会连续触发的按键（删除键）。
struct RepeatingKey: View {
    var systemImage: String
    var insetX = KeyboardMetrics.keyInsetX
    var insetY = KeyboardMetrics.keyInsetY
    var action: () -> Void
    @State private var timer: Timer?
    @State private var pressed = false

    var body: some View {
        KeyCap(fill: pressed ? KeyStyle.pressedKey : KeyStyle.functionKey, insetX: insetX, insetY: insetY) {
            Image(systemName: systemImage).font(KeyStyle.iconFont).foregroundStyle(Color.primary)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard timer == nil else { return }
                    pressed = true
                    action()
                    timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                        Task { @MainActor in
                            // 手指已经抬起就不再开始连发。
                            guard timer != nil else { return }
                            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                                Task { @MainActor in action() }
                            }
                        }
                    }
                }
                .onEnded { _ in
                    pressed = false
                    timer?.invalidate()
                    timer = nil
                }
        )
    }
}

/// 按下时键帽变成另一种底色，接近系统键盘的反馈。
struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.12 : 0)
    }
}
