import SwiftUI
import AppKit

enum STTheme {
    static let settingsWidth: CGFloat = 760
    static let settingsHeight: CGFloat = 800
    static let contentPadding: CGFloat = 18
    static let cardRadius: CGFloat = 12
    static let panelRadius: CGFloat = 20
}

extension AppAppearance {
    var displayName: String {
        switch self {
        case .native: return "原生"
        case .liquidGlass: return "液态玻璃"
        }
    }

    var note: String {
        switch self {
        case .native: return "跟随 macOS 的克制分组"
        case .liquidGlass: return "半透明材质与流动高光"
        }
    }

    var symbolName: String {
        switch self {
        case .native: return "rectangle.3.group"
        case .liquidGlass: return "circle.leewhite"
        }
    }
}

private struct STAppearanceKey: EnvironmentKey {
    static let defaultValue: AppAppearance = .native
}

extension EnvironmentValues {
    var stAppearance: AppAppearance {
        get { self[STAppearanceKey.self] }
        set { self[STAppearanceKey.self] = newValue }
    }
}

extension View {
    func stAppearance(_ appearance: AppAppearance) -> some View {
        environment(\.stAppearance, appearance)
    }
}

/// A quiet, in-window backdrop. Liquid Glass needs something with color
/// behind it; this supplies a restrained blue/teal ambient wash rather than
/// a photographic wallpaper.
struct STWindowBackdrop: View {
    let appearance: AppAppearance
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if appearance == .liquidGlass {
                let dark = colorScheme == .dark
                LinearGradient(
                    colors: [
                        Color(red: 0.27, green: 0.50, blue: 1.0).opacity(dark ? 0.24 : 0.12),
                        Color.clear,
                        Color(red: 0.18, green: 0.76, blue: 0.68).opacity(dark ? 0.14 : 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color(red: 0.32, green: 0.58, blue: 1.0).opacity(dark ? 0.20 : 0.10))
                    .frame(width: 520, height: 520)
                    .blur(radius: 105)
                    .offset(x: -260, y: -300)

                Circle()
                    .fill(Color(red: 0.14, green: 0.72, blue: 0.66).opacity(dark ? 0.12 : 0.07))
                    .frame(width: 460, height: 460)
                    .blur(radius: 115)
                    .offset(x: 300, y: 250)

                Circle()
                    .fill(Color(red: 0.62, green: 0.36, blue: 0.95).opacity(dark ? 0.08 : 0.05))
                    .frame(width: 390, height: 390)
                    .blur(radius: 100)
                    .offset(x: 300, y: -320)
            }
        }
        .ignoresSafeArea()
    }
}

/// Header strip shared by settings and library windows. In Liquid Glass mode
/// it gets a very subtle directional sheen in addition to the system material.
struct STHeaderSurface: View {
    @Environment(\.stAppearance) private var appearance

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)

            if appearance == .liquidGlass {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.075),
                        Color.clear,
                        Color.accentColor.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

struct STBrandMark: View {
    var size: CGFloat = 34
    @Environment(\.stAppearance) private var appearance

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.33, green: 0.62, blue: 1.0),
                            Color(red: 0.10, green: 0.36, blue: 0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if appearance == .liquidGlass {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                Color.white.opacity(0.02),
                                Color.white.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.plusLighter)
            }

            Text("译")
                .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: -0.5)
        }
        .frame(width: size, height: size)
        .overlay {
            shape
                .strokeBorder(
                    Color.white.opacity(appearance == .liquidGlass ? 0.26 : 0.08),
                    lineWidth: 0.7
                )
        }
        .shadow(
            color: appearance == .liquidGlass
                ? Color.accentColor.opacity(0.45)
                : Color.black.opacity(0.16),
            radius: appearance == .liquidGlass ? 9 : 3,
            y: appearance == .liquidGlass ? 4 : 1
        )
        .accessibilityLabel("划词翻译")
    }
}

struct STSectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

enum STStatusTone {
    case success
    case warning
    case danger
    case neutral
    case accent

    var color: Color {
        switch self {
        case .success: return .green
        case .warning: return .orange
        case .danger: return .red
        case .neutral: return .secondary
        case .accent: return .accentColor
        }
    }

    var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        case .neutral: return "circle.fill"
        case .accent: return "sparkles"
        }
    }
}

struct STStatusBadge: View {
    let text: String
    var tone: STStatusTone = .neutral
    var showsIcon: Bool = true
    @Environment(\.stAppearance) private var appearance

    var body: some View {
        HStack(spacing: 4) {
            if showsIcon {
                Image(systemName: tone.systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if appearance == .liquidGlass {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().fill(tone.color.opacity(0.10))
                    }
            } else {
                Capsule().fill(tone.color.opacity(0.11))
            }
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    tone.color.opacity(appearance == .liquidGlass ? 0.22 : 0.16),
                    lineWidth: 0.5
                )
        }
    }
}

struct STStatTile: View {
    let value: String
    let label: String
    @Environment(\.stAppearance) private var appearance

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if appearance == .liquidGlass {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.clear,
                                    Color.accentColor.opacity(0.035)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
            } else {
                shape.fill(Color.primary.opacity(0.035))
            }
        }
        .overlay {
            shape
                .strokeBorder(
                    appearance == .liquidGlass
                        ? Color.white.opacity(0.14)
                        : Color.primary.opacity(0.06),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: appearance == .liquidGlass ? Color.black.opacity(0.12) : .clear,
            radius: appearance == .liquidGlass ? 10 : 0,
            y: appearance == .liquidGlass ? 5 : 0
        )
    }
}

struct STPanelSurface<Content: View>: View {
    let content: Content
    @Environment(\.stAppearance) private var appearance

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: STTheme.panelRadius, style: .continuous)
    }

    @ViewBuilder
    var body: some View {
        if appearance == .liquidGlass {
            if #available(macOS 26.0, *) {
                content
                    .glassEffect(.regular, in: shape)
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.05),
                                    Color.white.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.7
                        )
                    }
                    .clipShape(shape)
                    .shadow(color: Color.black.opacity(0.22), radius: 26, y: 12)
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .background {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    Color.clear,
                                    Color.accentColor.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .overlay {
                        shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                    }
                    .clipShape(shape)
                    .shadow(color: Color.black.opacity(0.22), radius: 24, y: 10)
            }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
                }
                .clipShape(shape)
        }
    }
}

extension View {
    /// A single floating glass capsule. Used for the settings tab bar.
    func stGlassCapsule() -> some View {
        modifier(STGlassCapsuleModifier())
    }
}

private struct STGlassCapsuleModifier: ViewModifier {
    @Environment(\.stAppearance) private var appearance

    @ViewBuilder
    func body(content: Content) -> some View {
        if appearance == .liquidGlass {
            if #available(macOS 26.0, *) {
                content
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .glassEffect(.regular, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                    }
                    .shadow(color: Color.black.opacity(0.16), radius: 14, y: 7)
            } else {
                content
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                    }
                    .shadow(color: Color.black.opacity(0.16), radius: 14, y: 7)
            }
        } else {
            content
        }
    }
}

extension View {
    func stCardSurface(padding: CGFloat = 12, radius: CGFloat = 10) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.8)
            }
    }

    func stEditorSurface(focused: Bool = false, radius: CGFloat = 10) -> some View {
        modifier(STEditorSurfaceModifier(focused: focused, radius: radius))
    }

    /// Applies the grouped Form style but lets the ambient Liquid Glass
    /// backdrop show through in that appearance.
    func stFormSurface() -> some View {
        modifier(STFormSurfaceModifier())
    }
}

private struct STEditorSurfaceModifier: ViewModifier {
    let focused: Bool
    let radius: CGFloat
    @Environment(\.stAppearance) private var appearance

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                if appearance == .liquidGlass {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            shape.fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.13),
                                        Color.clear,
                                        Color.accentColor.opacity(0.025)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                } else {
                    shape.fill(Color.primary.opacity(0.035))
                }
            }
            .overlay {
                shape.strokeBorder(
                    focused
                        ? Color.accentColor.opacity(0.58)
                        : (appearance == .liquidGlass
                            ? Color.white.opacity(0.14)
                            : Color.primary.opacity(0.08)),
                    lineWidth: focused ? 1.5 : 1
                )
            }
            .clipShape(shape)
            .shadow(
                color: appearance == .liquidGlass ? Color.black.opacity(0.10) : .clear,
                radius: appearance == .liquidGlass ? 8 : 0,
                y: appearance == .liquidGlass ? 4 : 0
            )
    }
}

private struct STFormSurfaceModifier: ViewModifier {
    @Environment(\.stAppearance) private var appearance

    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .scrollContentBackground(appearance == .liquidGlass ? .hidden : .automatic)
    }
}
