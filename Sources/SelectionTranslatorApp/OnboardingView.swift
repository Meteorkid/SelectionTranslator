import SwiftUI

struct OnboardingView: View {
    let appearance: AppAppearance
    let onComplete: () -> Void
    let onOpenPrivacy: () -> Void

    @State private var accessibilityTrusted = false
    @State private var screenRecordingTrusted = false

    private struct Point: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let tint: Color
    }

    private let points: [Point] = [
        Point(
            icon: "cursorarrow.click.2",
            title: "不会误取",
            detail: "只在你主动划词、且鼠标落点与焦点窗口对得上时读取选区；密码框和安全输入直接跳过。",
            tint: .blue
        ),
        Point(
            icon: "text.quote",
            title: "不会丢上下文",
            detail: "把选区连同前后文、整篇文章一起交给翻译；取不到上下文时自动回退到选区本身。",
            tint: .teal
        ),
        Point(
            icon: "viewfinder",
            title: "不会打断截图",
            detail: "检测到截图工具浮层时不做剪贴板合成；每次取词后恢复原剪贴板，不覆盖你正在复制的内容。",
            tint: .orange
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)

            VStack(alignment: .leading, spacing: 12) {
                Text("先把三件事说清楚")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(points) { point in
                    pointCard(point)
                }

                setupCard
                privacyNote
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 18)

            Spacer(minLength: 0)

            footer
        }
        .frame(width: 620, height: 640)
        .background(STWindowBackdrop(appearance: appearance))
        .stAppearance(appearance)
        .onAppear(perform: refreshPermissions)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            STBrandMark(size: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text("欢迎使用划词翻译")
                    .font(.system(size: 20, weight: .semibold))
                Text("一个尽量不打扰你阅读的系统级取词层。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(AppVersion.short)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(STHeaderSurface())
    }

    private var setupCard: some View {
        STPanelSurface {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("建议先完成两项系统授权")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("可稍后")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                permissionRow(
                    icon: "accessibility",
                    title: "辅助功能",
                    detail: "划词取词与快捷键",
                    trusted: accessibilityTrusted,
                    actionTitle: accessibilityTrusted ? "已授权" : "打开设置"
                ) {
                    Permissions.openAccessibilitySettings()
                }

                permissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "屏幕录制",
                    detail: "截图 OCR",
                    trusted: screenRecordingTrusted,
                    actionTitle: screenRecordingTrusted ? "已授权" : "请求授权"
                ) {
                    _ = Permissions.requestScreenRecordingPermission()
                    refreshPermissions()
                }

                HStack(spacing: 8) {
                    Button("刷新状态") {
                        refreshPermissions()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))

                    Text("不授权也能用剪贴板翻译、输入翻译和浏览器扩展。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(13)
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        detail: String,
        trusted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(trusted ? Color.green : Color.orange)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 11.5, weight: .medium))
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            Spacer()

            STStatusBadge(
                text: trusted ? "已授权" : "未授权",
                tone: trusted ? .success : .warning
            )

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(trusted)
        }
    }

    private func refreshPermissions() {
        accessibilityTrusted = Permissions.isAccessibilityTrusted(prompt: false)
        screenRecordingTrusted = Permissions.hasScreenRecordingPermission()
    }

    private func pointCard(_ point: Point) -> some View {
        STPanelSurface {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: point.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(point.tint)
                    .frame(width: 30, height: 30)
                    .background(point.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(point.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(point.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Text("历史、生词本和 API Key 默认只在本机。只有你主动翻译时，文字才会发送到你配置的模型服务。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("查看完整隐私说明") {
                onOpenPrivacy()
            }
            .buttonStyle(.link)
            .font(.system(size: 11))

            Spacer()

            Button("开始使用") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(STHeaderSurface())
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }
}
