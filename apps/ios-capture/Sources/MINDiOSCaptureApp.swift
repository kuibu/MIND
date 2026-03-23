import SwiftUI
import ReplayKit
import MINDAppSupport

@main
struct MINDiOSCaptureApp: App {
    @StateObject private var runtime = IOSCaptureRuntimeCoordinator()

    var body: some Scene {
        WindowGroup {
            IOSCaptureRootView(viewModel: runtime.viewModel, runtime: runtime)
        }
    }
}

private struct IOSCaptureRootView: View {
    @ObservedObject var viewModel: IOSCaptureViewModel
    @ObservedObject var runtime: IOSCaptureRuntimeCoordinator

    var body: some View {
        NavigationView {
            ZStack {
                atmosphere

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        statusHero
                        pairingCard
                        if let activeSession = viewModel.activeSession {
                            sessionCard(activeSession)
                        }
                        eventTimeline
                    }
                    .padding(20)
                }
            }
            .navigationTitle("MIND Capture")
        }
        .navigationViewStyle(.stack)
        .onAppear {
            runtime.onAppear()
        }
        .onChange(of: viewModel.selectedPreset) { _ in
            runtime.syncSharedSettings()
        }
    }

    private var atmosphere: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.95, blue: 0.88),
                    Color(red: 0.86, green: 0.93, blue: 0.95),
                    Color(red: 0.88, green: 0.90, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.95, green: 0.74, blue: 0.36).opacity(0.32))
                .frame(width: 240, height: 240)
                .blur(radius: 10)
                .offset(x: -110, y: -260)

            Circle()
                .fill(Color(red: 0.24, green: 0.61, blue: 0.66).opacity(0.24))
                .frame(width: 260, height: 260)
                .blur(radius: 12)
                .offset(x: 130, y: -120)
        }
        .ignoresSafeArea()
    }

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MIND CAPTURE")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.black.opacity(0.56))
                Spacer()
                statusBadge
            }
            Text("iPhone 只负责采集，Mac 才是 system of record。")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.85))
            Text("当前状态：\(viewModel.status.title)")
                .font(.headline)
                .foregroundColor(.black.opacity(0.65))

            HStack(spacing: 8) {
                infoChip(title: "预设", value: viewModel.selectedPreset.title)
                infoChip(title: "模式", value: viewModel.keepAliveModeEnabled ? "长会话" : "快捷")
                if let node = viewModel.pairedNode {
                    infoChip(title: "Mac", value: node.name)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("采集预设")
                    .font(.subheadline.weight(.semibold))
                Picker("采集预设", selection: $viewModel.selectedPreset) {
                    ForEach(CaptureIntentPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                Text(viewModel.selectedPreset.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: $viewModel.keepAliveModeEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("可恢复长会话")
                        .font(.subheadline.weight(.semibold))
                    Text("打开后优先维持可续传链路，而不是一次性快捷采集。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Color.black.opacity(0.75)))

            VStack(alignment: .leading, spacing: 8) {
                Text("全局录屏入口")
                    .font(.subheadline.weight(.semibold))
                Text("需要采集系统级界面时，改用 Broadcast Upload Extension。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                BroadcastPickerTile(extensionBundleID: "com.kuibu.mind.ioscapture.broadcastupload")
                    .frame(height: 52)
            }

            HStack(spacing: 12) {
                Button {
                    runtime.startCapture()
                } label: {
                    Label("开始推流", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledActionButtonStyle(background: Color.black.opacity(0.82)))

                Button {
                    runtime.stopCapture()
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledActionButtonStyle(background: Color.white.opacity(0.65), foreground: .black))
            }
        }
        .cardStyle()
    }

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("可配对的 Mac 节点")
                .font(.headline)
            if viewModel.discoveredNodes.isEmpty {
                emptyStateCard(
                    title: "正在搜索局域网中的 Mac",
                    detail: "发现到节点后，这里会出现可信状态、延迟和连接入口。"
                )
            } else {
                ForEach(viewModel.discoveredNodes) { node in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(node.name)
                                    .font(.subheadline.weight(.semibold))
                                trustBadge(isTrusted: node.isTrusted)
                            }
                            Text(node.host)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("局域网延迟 \(node.latencyMillis) ms")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.black.opacity(0.56))
                        }
                        Spacer()
                        Button(node.isTrusted ? "连接" : "验证并连接") {
                            runtime.pair(with: node)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(node.isTrusted ? Color(red: 0.17, green: 0.47, blue: 0.78) : Color(red: 0.84, green: 0.52, blue: 0.14))
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .cardStyle()
    }

    private func sessionCard(_ session: CaptureSessionCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("活动会话")
                .font(.headline)
            Text(session.sessionID.rawValue)
                .font(.system(.body, design: .monospaced))
            Text("目的地：\(session.destinationName)")
                .font(.subheadline)
            Text("模式：\(session.modeLabel) · 本地缓冲块数：\(session.bufferedChunkCount)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("开始时间：\(session.startedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.72))
        }
        .cardStyle(background: Color(red: 0.09, green: 0.12, blue: 0.17).opacity(0.92), foreground: .white)
    }

    private var eventTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近事件")
                .font(.headline)
            if viewModel.recentEvents.isEmpty {
                emptyStateCard(
                    title: "还没有事件",
                    detail: "完成配对、开始推流或切换采集模式后，这里会出现一条按时间排序的操作时间线。"
                )
            } else {
                ForEach(viewModel.recentEvents) { event in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 0.19, green: 0.53, blue: 0.62))
                                .frame(width: 10, height: 10)
                            Rectangle()
                                .fill(Color.black.opacity(0.10))
                                .frame(width: 2)
                        }
                        .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.subheadline.weight(.semibold))
                            Text(event.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .cardStyle()
    }

    private var statusBadge: some View {
        Text(viewModel.status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.08), in: Capsule())
    }

    private func infoChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.black.opacity(0.45))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.black.opacity(0.78))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func trustBadge(isTrusted: Bool) -> some View {
        Text(isTrusted ? "Trusted" : "Verify")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isTrusted
                    ? Color(red: 0.85, green: 0.94, blue: 0.88)
                    : Color(red: 0.99, green: 0.91, blue: 0.78),
                in: Capsule()
            )
    }

    private func emptyStateCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.50), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BroadcastPickerTile: UIViewRepresentable {
    let extensionBundleID: String

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: .zero)
        view.preferredExtension = extensionBundleID
        view.showsMicrophoneButton = false
        return view
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = extensionBundleID
    }
}

private struct FilledActionButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    init(background: Color, foreground: Color = .white) {
        self.background = background
        self.foreground = foreground
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 14)
            .background(background.opacity(configuration.isPressed ? 0.75 : 1.0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundColor(foreground)
    }
}

private extension View {
    func cardStyle(background: Color = Color.white.opacity(0.74), foreground: Color = .black) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .foregroundColor(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 10)
    }
}
