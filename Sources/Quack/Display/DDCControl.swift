import Foundation
import CDDC

/// Swift wrapper over the `CDDC` C target, which performs DDC/CI brightness
/// control over I2C using Apple's private `IOAVService` API (Apple Silicon).
///
/// External displays are addressed by index in IORegistry order; this matches
/// the order in which the app enumerates external `NSScreen`s. There is no
/// public API for external-display brightness — DDC/CI is the mechanism. This
/// type cannot be unit-tested; it requires real hardware.
enum DDCControl {

    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// Number of external displays that responded to DDC discovery.
    static func externalDisplayCount() -> Int {
        Int(cddc_external_display_count())
    }

    /// Sets brightness (0...100) on the external display at `index`.
    @discardableResult
    static func setBrightness(_ percent: Int, atIndex index: Int) -> Bool {
        cddc_set_brightness(Int32(index), Int32(percent)) == 1
    }

    /// Reads brightness (0...100), or nil if the display does not support DDC.
    static func brightness(atIndex index: Int) -> Int? {
        let value = Int(cddc_get_brightness(Int32(index)))
        return value >= 0 ? value : nil
    }

    /// Capability probe for the display at `index`.
    static func supportsBrightness(atIndex index: Int) -> Bool {
        brightness(atIndex: index) != nil
    }
}
