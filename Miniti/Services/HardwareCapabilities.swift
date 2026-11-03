import Foundation

/// Coarse installation capabilities only. Raw sysctl strings never leave this helper.
enum HardwareCapabilities {
    static func fields(model: String, chip: String, memoryBytes: UInt64, supported: Bool,
                       preparation: String, thermal: String, preparationMS: Int? = nil) -> [String: String] {
        let families = [("MacBookAir", "macbook_air"), ("MacBookPro", "macbook_pro"), ("Macmini", "mac_mini"),
                        ("MacStudio", "mac_studio"), ("iMac", "imac"), ("MacPro", "mac_pro")]
        let family = families.first { model.range(of: "^\($0.0)[0-9]{1,2},[0-9]{1,2}$", options: .regularExpression) != nil }?.1 ?? "unknown"
        // Newer generic MacN,N identifiers are deliberately unknown without a validated map.
        var chipFamily = "unknown"
        if chip.range(of: "^Apple M[1-5]( (Pro|Max|Ultra))?$", options: .regularExpression) != nil,
           let digit = chip.dropFirst(7).first { chipFamily = "apple_m\(digit)" }
        else if chip.hasPrefix("Intel") { chipFamily = "intel" }
        let gb = Double(memoryBytes) / 1_073_741_824
        let ram = memoryBytes == 0 ? "unknown" : gb <= 8 ? "up_to_8_gb" : gb <= 16 ? "9_to_16_gb" : gb <= 32 ? "17_to_32_gb" : gb <= 64 ? "33_to_64_gb" : "over_64_gb"
        var result = ["schema_version": "1", "model_family": family, "chip_family": chipFamily, "ram_band": ram,
                      "hardware_support": supported ? "supported" : "unsupported",
                      "preparation_state": RecordingReportingContract.valid("preparation_state", preparation) ? preparation : "unknown",
                      "thermal_state": RecordingReportingContract.valid("thermal_state", thermal) ? thermal : "unknown"]
        if let preparationMS { result["preparation_ms"] = String(min(3_600_000, max(0, preparationMS))) }
        return result
    }

    static func eligible(isMac: Bool, managed: Bool, sharing: Bool, enrolled: Bool, recording: Bool, finalizing: Bool) -> Bool {
        isMac && managed && sharing && enrolled && !recording && !finalizing
    }

    #if os(macOS)
    static func current(preparation: String, preparationMS: Int?) -> [String: String] {
        func sysctlString(_ key: String) -> String {
            var size = 0
            guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0, size <= 256 else { return "" }
            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return "" }
            return String(cString: bytes)
        }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        return fields(model: sysctlString("hw.model"), chip: sysctlString("machdep.cpu.brand_string"),
                      memoryBytes: ProcessInfo.processInfo.physicalMemory, supported: OnDeviceDiarizationService.isHardwareSupported,
                      preparation: preparation, thermal: thermal, preparationMS: preparationMS)
    }
    #endif
}

/// Transition-based sampling, never per audio packet or download progress update.
struct HardwareSnapshotAdmission {
    private var previous: [String: String]?
    private var admitted: [Date] = []
    mutating func shouldEmit(_ fields: [String: String], now: Date = Date()) -> Bool {
        admitted.removeAll { now.timeIntervalSince($0) >= 3600 || $0 > now }
        guard admitted.count < 6 else { return false }
        guard fields != previous || admitted.isEmpty else { return false }
        previous = fields
        admitted.append(now)
        return true
    }
}
