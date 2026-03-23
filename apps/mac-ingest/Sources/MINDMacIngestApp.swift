import SwiftUI
import MINDAppSupport

@main
struct MINDMacIngestApp: App {
    @StateObject private var runtime = MacIngestRuntimeCoordinator()

    var body: some Scene {
        WindowGroup {
            MacIngestRootView(viewModel: runtime.viewModel, runtime: runtime)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private struct MacIngestRootView: View {
    @ObservedObject var viewModel: MacIngestViewModel
    @ObservedObject var runtime: MacIngestRuntimeCoordinator
    @State private var selectedPanelID: String?
    @State private var reviewDrafts: [String: String] = [:]

    var body: some View {
        NavigationView {
            sidebar
            detail
        }
        .onAppear {
            runtime.onAppear()
            selectedPanelID = viewModel.pipelinePanels.first?.id
            seedReviewDrafts(from: viewModel.reviewQueue)
        }
        .onDisappear {
            runtime.onDisappear()
        }
        .onChange(of: viewModel.reviewQueue) { items in
            seedReviewDrafts(from: items)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedPanelID) {
            Section("任务视图") {
                ForEach(viewModel.pipelinePanels) { panel in
                    Label(panel.title, systemImage: icon(for: panel.id))
                        .tag(Optional(panel.id))
                }
            }

            Section("GUI Recipes") {
                ForEach(viewModel.recipeLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 240)
    }

    private var detail: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.18, green: 0.28, blue: 0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    runtimeHero
                    sessionGrid
                    observationGrid
                    reviewWorkbench
                    evaluationGrid
                    if let selected = viewModel.pipelinePanels.first(where: { $0.id == selectedPanelID }) ?? viewModel.pipelinePanels.first {
                        pipelinePanel(selected)
                    }
                }
                .padding(24)
            }
        }
    }

    private var runtimeHero: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mac Ingest Node")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("MiniCPM 作为共享感知内核，App target 只负责会话控制和可视化。")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.75))
                Text(runtime.listenerStatus)
                    .font(.subheadline.monospaced())
                    .foregroundColor(.white.opacity(0.88))
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.runtimeDescriptor.modelID)
                    .font(.system(.headline, design: .monospaced))
                Text(viewModel.runtimeDescriptor.notes)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
                Text(runtime.storagePath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(16)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .foregroundColor(.white)
        .panelStyle()
    }

    private var sessionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("活动会话")
                .font(.headline)
                .foregroundColor(.white)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(viewModel.sessions) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.sourceDeviceName)
                            .font(.headline)
                        Text(session.sessionID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(session.stateLabel)
                            .font(.subheadline)
                        Divider()
                        HStack {
                            metricPill(label: "关键帧", value: "\(session.keyframeCount)")
                            metricPill(label: "合并结果", value: "\(session.mergedObservationCount)")
                        }
                    }
                    .panelStyle(background: Color(red: 0.95, green: 0.95, blue: 0.92), foreground: .black)
                }
            }
        }
    }

    private var observationGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近抽取")
                .font(.headline)
                .foregroundColor(.white)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                ForEach(viewModel.observationPreviews) { preview in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(preview.badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                        Text(preview.title)
                            .font(.headline)
                        Text(preview.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .panelStyle(background: Color.white.opacity(0.88), foreground: .black)
                }
            }
        }
    }

    private var reviewWorkbench: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("人工纠错台")
                .font(.headline)
                .foregroundColor(.white)

            if viewModel.reviewQueue.isEmpty {
                Text("当前没有低置信度样本。低置信度关键帧会自动保留证据，并进入人工纠错台。")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.76))
                    .panelStyle()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(viewModel.reviewQueue) { item in
                        reviewCard(item)
                    }
                }
            }
        }
    }

    private var evaluationGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recipe Eval")
                .font(.headline)
                .foregroundColor(.white)

            if viewModel.evaluationReports.isEmpty {
                Text("还没有标注样本。保存人工纠错后，会在本地数据集上回放并生成字段级准确率。")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.76))
                    .panelStyle()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(viewModel.evaluationReports) { report in
                        evaluationCard(report)
                    }
                }
            }
        }
    }

    private func pipelinePanel(_ panel: PipelinePanelItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(panel.title)
                .font(.title2.weight(.bold))
            Text(panel.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(panel.lines, id: \.self) { line in
                Text(line)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .panelStyle(background: Color(red: 0.98, green: 0.96, blue: 0.91), foreground: .black)
    }

    private func metricPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(10)
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func icon(for id: String) -> String {
        switch id {
        case "expense":
            return "creditcard"
        case "attachment":
            return "paperclip"
        case "saved-video":
            return "bookmark"
        default:
            return "circle.grid.2x2"
        }
    }

    private func reviewCard(_ item: ReviewQueueCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.headline)
            Text(item.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            if item.evidenceLocators.isEmpty == false {
                Text(item.evidenceLocators.joined(separator: "\n"))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            TextEditor(text: reviewDraftBinding(for: item))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 130)
                .padding(8)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Button("保存标注") {
                    runtime.submitReview(reviewID: item.id, fieldText: reviewDrafts[item.id] ?? item.predictedFields.joined(separator: "\n"))
                }
                .buttonStyle(.borderedProminent)

                Button("还原预测") {
                    reviewDrafts[item.id] = item.predictedFields.joined(separator: "\n")
                }
                .buttonStyle(.bordered)
            }
        }
        .panelStyle(background: Color.white.opacity(0.9), foreground: .black)
    }

    private func evaluationCard(_ report: EvaluationReportCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.title)
                .font(.headline)
            Text(report.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(report.lines, id: \.self) { line in
                Text(line)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .panelStyle(background: Color(red: 0.97, green: 0.99, blue: 0.90), foreground: .black)
    }

    private func seedReviewDrafts(from items: [ReviewQueueCard]) {
        for item in items where reviewDrafts[item.id] == nil {
            reviewDrafts[item.id] = item.predictedFields.joined(separator: "\n")
        }
        let activeIDs = Set(items.map(\.id))
        reviewDrafts = reviewDrafts.filter { activeIDs.contains($0.key) }
    }

    private func reviewDraftBinding(for item: ReviewQueueCard) -> Binding<String> {
        Binding(
            get: {
                reviewDrafts[item.id] ?? item.predictedFields.joined(separator: "\n")
            },
            set: { newValue in
                reviewDrafts[item.id] = newValue
            }
        )
    }
}

private extension View {
    func panelStyle(background: Color = Color.white.opacity(0.12), foreground: Color = .white) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .foregroundColor(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
