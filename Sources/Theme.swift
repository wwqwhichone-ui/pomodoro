// 视觉语言（参考 Neverless App）：米白纸色平面底、墨色文字、压缩粗体大数字、
// 灰色小标题、细线描边圆形图标、黑 / 彩分段细环、纤细宋体注释。另有深色「墨夜」主题。
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

struct Theme {
    let isDark: Bool
    /// 纸色底
    let bg: Color
    /// 侧栏 / 卡片，比底色略深一档
    let panel: Color
    /// 墨色：正文、描边、剩余进度
    let ink: Color
    /// 灰色小标题、说明
    let gray: Color
    /// 更淡的辅助色
    let faint: Color
    /// 发丝分割线
    let line: Color
    /// 墨色按钮上的文字
    let onInk: Color

    static let paper = Theme(
        isDark: false,
        bg: Color(hex: 0xF7F2E7), panel: Color(hex: 0xEFE8DA),
        ink: Color(hex: 0x1A1A1A), gray: Color(hex: 0x8C8983), faint: Color(hex: 0xBDB7AC),
        line: Color(hex: 0x1A1A1A, alpha: 0.12), onInk: Color(hex: 0xF7F2E7))

    /// 暖调深咖纸：不用纯黑，墨色压低亮度，减少刺眼的反差
    static let night = Theme(
        isDark: true,
        bg: Color(hex: 0x1F1C18), panel: Color(hex: 0x272420),
        ink: Color(hex: 0xE4DCCB), gray: Color(hex: 0x97907F), faint: Color(hex: 0x5F594F),
        line: Color(hex: 0xE4DCCB, alpha: 0.11), onInk: Color(hex: 0x1F1C18))

    /// 各阶段的点缀色（用量克制：只用于已过进度、状态行、少量标记）
    func accent(_ p: Phase) -> Color {
        switch p {
        case .focus: return isDark ? Color(hex: 0xE8703D) : Color(hex: 0xE8541C)
        case .shortBreak: return isDark ? Color(hex: 0x5FAE7E) : Color(hex: 0x2F9B5E)
        case .longBreak: return isDark ? Color(hex: 0x7F9CC8) : Color(hex: 0x3A64A8)
        }
    }
    var positive: Color { accent(.shortBreak) }
    var warning: Color { isDark ? Color(hex: 0xF2B33D) : Color(hex: 0xC98A12) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.paper
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Phase {
    var symbol: String {
        switch self {
        case .focus: return "scope"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "leaf"
        }
    }
}

enum Typo {
    /// 压缩粗体：大数字、计时器（对应 Neverless 的海报体数字）
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.compressed)
    }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// 纤细宋体：环中心的注释、休息建议
    static func serif(_ size: CGFloat) -> Font {
        .custom("STSongti-SC-Light", size: size)
    }
}

/// 按下缩小、悬停轻微变化的按钮样式
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    private struct PressBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hover = false
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(hover ? 0.78 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0 }
        }
    }
}
