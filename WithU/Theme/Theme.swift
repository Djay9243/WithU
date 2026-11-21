//
//  Theme.swift
//  WithU
//
//  Colours, backgrounds and reusable controls that match the WithU design:
//  a soft mauve-to-cream gradient, lavender cards and a purple primary button.
//

import SwiftUI
import UIKit

// MARK: - Appearance

/// Light, dark or follow the system.
nonisolated enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private func dynamic(_ light: (Double, Double, Double), _ dark: (Double, Double, Double), alpha: Double = 1) -> Color {
    Color(uiColor: UIColor { traits in
        let c = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: alpha)
    })
}

enum Theme {
    // Brand
    static let primary = dynamic((0.43, 0.39, 0.78), (0.62, 0.57, 0.95))
    static let primaryDark = dynamic((0.34, 0.31, 0.62), (0.50, 0.46, 0.80))
    static let mauve = dynamic((0.82, 0.74, 0.83), (0.22, 0.18, 0.28))
    static let lavender = dynamic((0.91, 0.89, 0.97), (0.18, 0.17, 0.24))
    static let lavenderDeep = dynamic((0.86, 0.83, 0.95), (0.24, 0.22, 0.32))

    // Neutrals
    static let cream = dynamic((0.96, 0.94, 0.91), (0.09, 0.09, 0.11))
    /// Solid surface for fields, chips, rows and floating buttons.
    static let surface = dynamic((1, 1, 1), (0.17, 0.16, 0.20))
    static let cardWhite = dynamic((1, 1, 1), (0.15, 0.14, 0.18), alpha: 0.8)
    static let ink = dynamic((0.11, 0.10, 0.13), (0.95, 0.94, 0.97))
    static let inkSecondary = dynamic((0.42, 0.40, 0.47), (0.68, 0.66, 0.74))
    static let peach = dynamic((0.92, 0.70, 0.60), (0.36, 0.18, 0.15))
    /// Dark text used on the light, colourful travel-mode tints in both modes.
    static let onTint = Color(red: 0.12, green: 0.10, blue: 0.14)

    // Status
    static let safeGreen = dynamic((0.29, 0.60, 0.36), (0.38, 0.72, 0.46))
    static let deepGreen = dynamic((0.18, 0.42, 0.31), (0.26, 0.56, 0.42))
    static let alertRed = dynamic((0.78, 0.31, 0.31), (0.93, 0.45, 0.45))
    static let amber = dynamic((0.93, 0.62, 0.25), (0.97, 0.72, 0.36))

    /// Avatar colours for contacts, chosen by `colorIndex`.
    static let avatarPalette: [Color] = [
        Color(red: 0.43, green: 0.39, blue: 0.78),
        Color(red: 0.86, green: 0.42, blue: 0.47),
        Color(red: 0.86, green: 0.72, blue: 0.33),
        Color(red: 0.30, green: 0.62, blue: 0.56),
        Color(red: 0.86, green: 0.55, blue: 0.36),
        Color(red: 0.49, green: 0.45, blue: 0.55)
    ]

    static func avatarColor(_ index: Int) -> Color {
        avatarPalette[abs(index) % avatarPalette.count]
    }
}

extension TravelMode {
    /// Each way of travelling has its own colour: chips, routes and the trip screen.
    var tint: Color {
        switch self {
        case .walk: dynamic((0.97, 0.66, 0.77), (0.98, 0.70, 0.81))
        case .drive: dynamic((0.47, 0.67, 0.97), (0.53, 0.72, 0.99))
        case .cycle: dynamic((0.50, 0.82, 0.62), (0.55, 0.86, 0.66))
        case .transit: dynamic((0.98, 0.76, 0.42), (0.99, 0.79, 0.47))
        }
    }

    /// The route line on the map: one colour for every way of travelling.
    var routeColor: Color {
        dynamic((0.22, 0.48, 0.90), (0.47, 0.67, 0.99))
    }
}

// MARK: - Background

/// Full-screen gradient. `.calm` is the everyday mauve; `.alert` is the peach used
/// for check-ins and active alerts.
struct ScreenBackground: View {
    enum Tone { case calm, alert }

    var tone: Tone = .calm

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: tone == .calm ? Theme.mauve : Theme.peach, location: 0),
                .init(color: Theme.cream, location: 0.45),
                .init(color: Theme.cream, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Keyboard

extension View {
    /// Adds a "Done" button above the keyboard and lets a drag dismiss it.
    func keyboardDismissible() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.primary
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, color: color, foreground: foreground)
    }
}

/// Separate view so the style can read the colour scheme. In Dark Mode the
/// accent colours brighten, so the fill is deepened to keep white text
/// readable (at least 3:1 for this bold, large label).
private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    let foreground: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let fill = colorScheme == .dark ? color.mix(with: .black, by: 0.3) : color
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .contentShape(Capsule())
            .glassEffect(.regular.tint(fill).interactive(), in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primary(_ color: Color) -> PrimaryButtonStyle { PrimaryButtonStyle(color: color) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func secondary(_ tint: Color) -> SecondaryButtonStyle { SecondaryButtonStyle(tint: tint) }
}

// MARK: - Cards

struct CardModifier: ViewModifier {
    var fill: Color = Theme.cardWhite
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        // Liquid Glass, lightly tinted with the card colour.
        content
            .padding(padding)
            .glassEffect(.regular.tint(fill.opacity(0.35)), in: .rect(cornerRadius: 22))
    }
}

extension View {
    func card(fill: Color = Theme.cardWhite, padding: CGFloat = 16) -> some View {
        modifier(CardModifier(fill: fill, padding: padding))
    }
}

// MARK: - Small components

struct AvatarView: View {
    var name: String
    var colorIndex: Int
    var size: CGFloat = 36

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(Theme.avatarColor(colorIndex))
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(name)
    }
}

/// Small uppercase label used above groups ("FROM CONTACTS", "HOW ARE YOU GOING?").
struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.inkSecondary)
    }
}

/// Rounded pill, e.g. "ALERT ACTIVE" or "Smart check-in · critical alert".
struct StatusPill: View {
    var text: String
    var tint: Color
    var showsDot = true

    var body: some View {
        HStack(spacing: 6) {
            if showsDot {
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(tint.opacity(0.2)), in: .capsule)
    }
}

/// A tinted circle with an SF Symbol, used on the onboarding pages.
struct SymbolBadge: View {
    var systemImage: String
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            Circle().fill(.clear).glassEffect(.regular.tint(Theme.lavenderDeep.opacity(0.6)), in: .circle)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Theme.primary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ToggleRow: View {
    var title: String
    var subtitle: String?
    var systemImage: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(Theme.primary)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .tint(Theme.safeGreen)
    }
}

// MARK: - Formatting helpers

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    static func distance(_ meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }

    /// "2:00", "0:45": a countdown in minutes and seconds.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.up)), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "2 minutes", "1 minute", "30 seconds".
    static func responseTime(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) seconds" }
        let minutes = seconds / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
