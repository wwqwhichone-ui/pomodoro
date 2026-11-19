// 设置界面用的控件：与主界面同一套视觉语言（细描边胶囊、发丝分割线、压缩粗体数字、墨色胶囊）
import SwiftUI

/// 通用的胶囊分页：未选中灰字，选中套细描边胶囊（与阶段切换一致）
struct CapsuleTabs<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var fontSize: CGFloat = 12.5
    @Namespace private var ns
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: fontSize * 0.3) {
            ForEach(items.indices, id: \.self) { i in
                let value = items[i].0
                Button { selection = value } label: {
                    Text(items[i].1)
                        .font(Typo.text(fontSize, .medium))
                        .foregroundColor(value == selection ? t.ink : t.gray)
                        .padding(.horizontal, fontSize * 0.95)
                        .padding(.vertical, fontSize * 0.42)
                        .background {
                            if value == selection {
                                Capsule()
                                    .strokeBorder(t.ink, lineWidth: 1.2)
                                    .matchedGeometryEffect(id: "selected", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selection)
    }
}

/// 一行设置：左边名称 + 灰色说明，右边控件，底部发丝线
struct SettingRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var divider = true
    @ViewBuilder var trailing: Trailing
    @Environment(\.theme) private var t

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typo.text(13, .medium))
                        .foregroundColor(t.ink)
                    if let detail {
                        Text(detail)
                            .font(Typo.text(11))
                            .foregroundColor(t.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.vertical, 9)
            if divider { Rectangle().fill(t.line).frame(height: 1) }
        }
    }
}

/// 分组标题（灰色小字，上方留白）
struct SettingGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: title, s: 1)
                .padding(.bottom, 2)
            content
        }
        .padding(.top, 16)
    }
}

/// − 数字 + ：细线圆形按钮 + 压缩粗体数字
struct InkStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit: String = "分钟"
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 10) {
            circle("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - 1) }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(Typo.display(21))
                    .monospacedDigit()
                    .foregroundColor(t.ink)
                    .frame(minWidth: 24, alignment: .trailing)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: value)
                Text(unit)
                    .font(Typo.text(11, .medium))
                    .foregroundColor(t.gray)
                    .frame(minWidth: 24, alignment: .leading)
            }
            circle("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + 1) }
        }
    }

    private func circle(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(t.ink)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(t.ink.opacity(0.75), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

/// 墨色胶囊开关
struct InkSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.theme) private var t

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? t.ink : Color.clear)
                    .overlay(Capsule().strokeBorder(isOn ? t.ink : t.ink.opacity(0.3), lineWidth: 1))
                Circle()
                    .fill(isOn ? t.onInk : t.ink.opacity(0.4))
                    .padding(3.5)
            }
            .frame(width: 38, height: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 只有底部细线的输入框，上方灰色标签
struct InkField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var mono = false
    @FocusState private var focused: Bool
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typo.text(11.5, .medium))
                .foregroundColor(t.gray)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 12, design: .monospaced) : Typo.text(13))
            .foregroundColor(t.ink)
            .focused($focused)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused ? t.ink.opacity(0.6) : t.line).frame(height: 1)
            }
        }
        .padding(.vertical, 6)
    }
}

/// 墨色实心胶囊 / 细描边胶囊按钮
struct InkButton: View {
    let title: String
    var icon: String? = nil
    var filled = true
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @Environment(\.theme) private var t

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                }
                Text(title).font(Typo.text(12.5, .semibold))
            }
            .foregroundColor(filled ? t.onInk : t.ink)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(Capsule().fill(filled ? t.ink : Color.clear))
            .overlay(Capsule().strokeBorder(t.ink, lineWidth: filled ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .opacity(enabled ? 1 : 0.35)
    }
}

/// 键帽 / 代码小标签
struct KeyChip: View {
    let text: String
    var mono = false
    @Environment(\.theme) private var t

    var body: some View {
        Text(text)
            .font(mono ? .system(size: 11, weight: .medium, design: .monospaced) : Typo.text(11.5, .semibold))
            .foregroundColor(t.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.ink.opacity(0.35), lineWidth: 1))
    }
}

/// 圆点 + 状态文字
struct StatusDot: View {
    let text: String
    let color: Color
    var detail: String? = nil
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text).font(Typo.text(13, .semibold)).foregroundColor(t.ink)
            }
            if let detail {
                Text(detail)
                    .font(Typo.text(11.5, .medium))
                    .foregroundColor(t.gray)
                    .padding(.leading, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
