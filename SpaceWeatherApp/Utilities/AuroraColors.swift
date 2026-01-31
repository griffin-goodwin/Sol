import SwiftUI
import CoreGraphics

// Centralized aurora color helpers so renderer and UI share identical mapping

public func auroraGradientComponents(for probability: Double) -> (r: Double, g: Double, b: Double, a: Double) {
    // Create 11 control colors at 0,10,...,100 and interpolate between them
    let prob = min(max(probability, 0.0), 100.0)
    let p = prob / 100.0
    // Define color stops (r,g,b) for 0..100 every 10 — dark green → light green → purple → pink
    let stops: [(r: Double, g: Double, b: Double)] = [
        (0.06, 0.20, 0.08), // 0  - very dark green
        (0.12, 0.35, 0.12), //10  - dark green
        (0.18, 0.55, 0.20), //20  - mid green
        (0.25, 0.75, 0.35), //30  - lighter green
        (0.35, 0.80, 0.45), //40  - green/teal
        (0.40, 0.75, 0.60), //50  - teal
        (0.55, 0.60, 0.75), //60  - bluish violet
        (0.60, 0.45, 0.80), //70  - purple
        (0.75, 0.40, 0.82), //80  - pinky purple
        (0.85, 0.45, 0.85), //90  - pink
        (0.95, 0.55, 0.90)  //100 - light pink
    ]

    // Determine indices
    let totalStops = stops.count - 1
    let exact = p * Double(totalStops)
    let idx = Int(floor(exact))
    let frac = exact - Double(idx)

    let lower = stops[min(max(idx, 0), totalStops)]
    let upper = stops[min(max(idx + 1, 0), totalStops)]

    let r = lerp(lower.r, upper.r, frac)
    let g = lerp(lower.g, upper.g, frac)
    let b = lerp(lower.b, upper.b, frac)

    // Alpha uses previous formula for consistency
    let baseOpacity = 0.12 + (p * 0.18)
    return (r: r, g: g, b: b, a: baseOpacity)
}

public func auroraCGColor(for probability: Double) -> CGColor {
    let c = auroraGradientComponents(for: probability)
    return CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
}

public func auroraColor(for probability: Double, boostAlpha: Bool = true) -> Color {
    let c = auroraGradientComponents(for: probability)
    var alpha = c.a
    if boostAlpha && alpha < 0.25 {
        alpha = min(1.0, alpha * 4.0)
    }
    return Color(red: c.r, green: c.g, blue: c.b).opacity(alpha)
}

/// Returns aurora color at full opacity - for UI elements like compass, badges, text
public func auroraUIColor(for probability: Double) -> Color {
    let c = auroraGradientComponents(for: probability)
    // Brighten the colors for better UI visibility
    let brighten = 1.3
    let r = min(1.0, c.r * brighten)
    let g = min(1.0, c.g * brighten)
    let b = min(1.0, c.b * brighten)
    return Color(red: r, green: g, blue: b)
}

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    return a + (b - a) * t
}
