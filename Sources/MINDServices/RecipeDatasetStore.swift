import Foundation
import MINDProtocol

public final class RecipeDatasetStore {
    public static let defaultRootURL: URL = {
        let baseDirectory: URL
#if os(macOS)
        baseDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
#else
        baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
#endif
        return baseDirectory.appendingPathComponent("MIND/runtime/recipe-replays", isDirectory: true)
    }()

    public let rootURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL = RecipeDatasetStore.defaultRootURL) {
        self.rootURL = rootURL

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func save(sample: RecipeReplaySample) throws {
        let directory = sampleDirectory(for: sample)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(sample.id + ".json", isDirectory: false)
        let data = try encoder.encode(sample)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadSamples() throws -> [RecipeReplaySample] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return []
        }

        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var samples: [RecipeReplaySample] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "json" && fileURL.lastPathComponent != "reports.json" {
            let data = try Data(contentsOf: fileURL)
            samples.append(try decoder.decode(RecipeReplaySample.self, from: data))
        }
        return samples.sorted { $0.id < $1.id }
    }

    public func saveReports(_ reports: [RecipeEvaluationReport]) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let fileURL = rootURL.appendingPathComponent("reports.json", isDirectory: false)
        let data = try encoder.encode(reports)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadReports() throws -> [RecipeEvaluationReport] {
        let fileURL = rootURL.appendingPathComponent("reports.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([RecipeEvaluationReport].self, from: data)
    }

    public func evaluate(using harness: RecipeEvaluationHarness) throws -> [RecipeEvaluationReport] {
        let reports = try harness.evaluate(samples: loadSamples())
        try saveReports(reports)
        return reports
    }

    private func sampleDirectory(for sample: RecipeReplaySample) -> URL {
        rootURL
            .appendingPathComponent(sample.recipeID.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
            .appendingPathComponent("v\(sample.recipeVersion)", isDirectory: true)
    }
}
