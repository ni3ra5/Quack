#ifndef CDDC_H
#define CDDC_H

#include <stdint.h>

/// DDC/CI external-display brightness over I2C (Apple Silicon).
///
/// Wraps Apple's private `IOAVService` API the same way the open-source
/// `m1ddc` / `MonitorControl` projects do. External displays are addressed by
/// index in IORegistry order (macOS exposes no direct CGDirectDisplayID link on
/// Apple Silicon), matching how callers enumerate external `NSScreen`s.

/// Number of external (non-embedded) DDC-capable AV services found.
int cddc_external_display_count(void);

/// Sets brightness (0...100) on the external display at `index`.
/// Returns 1 on success, 0 on failure.
int cddc_set_brightness(int index, int percent);

/// Reads current brightness (0...100) from the external display at `index`.
/// Returns the value on success, or -1 if the display does not respond to DDC.
int cddc_get_brightness(int index);

#endif /* CDDC_H */
