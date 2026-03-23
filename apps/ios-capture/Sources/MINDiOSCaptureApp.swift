import SwiftUI
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
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.95, blue: 0.89),
                        Color(red: 0.83, green: 0.91, blue: 0.95)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

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
    }

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iPhone 只负责采集，Mac 才是 system of record。")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.85))
            Text("当前状态：\(viewModel.status.title)")
                .font(.headline)
                .foregroundColor(.black.opacity(0.65))

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
            ForEach(viewModel.discoveredNodes) { node in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(node.host) · \(node.latencyMillis) ms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(node.isTrusted ? "连接" : "验证并连接") {
                        runtime.pair(with: node)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(node.isTrusted ? Color.blue.opacity(0.8) : Color.orange.opacity(0.9))
                }
                .padding(.vertical, 6)
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
        }
        .cardStyle(background: Color.black.opacity(0.85), foreground: .white)
    }

    private var eventTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近事件")
                .font(.headline)
            ForEach(viewModel.recentEvents) { event in
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .cardStyle()
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
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
    }
}
