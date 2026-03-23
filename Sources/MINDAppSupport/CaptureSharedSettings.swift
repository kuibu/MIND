import Foundation

public struct CaptureRelayConfiguration: Codable, Equatable {
    public let serviceName: String
    public let serviceDomain: String
    public let displayName: String

    public init(serviceName: String, serviceDomain: String, displayName: String) {
        self.serviceName = serviceName
        self.serviceDomain = serviceDomain
        self.displayName = displayName
    }
}

public struct CaptureSharedSettings: Codable, Equatable {
    public let selectedPresetRawValue: String
    public let relay: CaptureRelayConfiguration?

    public init(selectedPresetRawValue: String, relay: CaptureRelayConfiguration?) {
        self.selectedPresetRawValue = selectedPresetRawValue
        self.relay = relay
    }

    public var selectedPreset: CaptureIntentPreset {
        CaptureIntentPreset(rawValue: selectedPresetRawValue) ?? .wechatAttachment
    }
}

public final class CaptureSharedSettingsStore {
    public static let appGroupID = "group.com.kuibu.mind.capture"
    private static let defaultsKey = "capture.shared.settings"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(appGroupID: String = CaptureSharedSettingsStore.appGroupID) {
        self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public func load() -> CaptureSharedSettings {
        guard
            let data = defaults.data(forKey: Self.defaultsKey),
            let settings = try? decoder.decode(CaptureSharedSettings.self, from: data)
        else {
            return CaptureSharedSettings(selectedPresetRawValue: CaptureIntentPreset.wechatAttachment.rawValue, relay: nil)
        }
        return settings
    }

    public func save(_ settings: CaptureSharedSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
