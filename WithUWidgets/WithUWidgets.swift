//
//  WithUWidgets.swift
//  WithUWidgets
//
//  Trip countdown on the Lock Screen and in the Dynamic Island.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LockScreenTripView(context: context)
                .widgetURL(URL(string: "withu://trip"))
                .activityBackgroundTint(LiveActivityPalette.background(for: context.state.status))
                .activitySystemActionForegroundColor(LiveActivityPalette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.attributes.travelModeSymbol)
                        Text(context.attributes.destinationName)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    contactStack(context.attributes.contactInitials, size: 22)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(LiveActivityPalette.headline(for: context.state.status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        timer(context, font: .system(size: 30, weight: .bold, design: .rounded))
                        Spacer()
                        if let metres = context.state.remainingDistanceMeters, context.state.status != .arrived {
                            Text(LiveActivityPalette.distance(metres))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: LiveActivityPalette.symbol(for: context.state.status))
                    .foregroundStyle(LiveActivityPalette.accent(for: context.state.status))
            } compactTrailing: {
                timer(context, font: .caption.monospacedDigit())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: LiveActivityPalette.symbol(for: context.state.status))
                    .foregroundStyle(LiveActivityPalette.accent(for: context.state.status))
            }
            .widgetURL(URL(string: "withu://trip"))
        }
    }

    @ViewBuilder
    private func timer(_ context: ActivityViewContext<TripActivityAttributes>, font: Font) -> some View {
        switch context.state.status {
        case .arrived:
            Text("Arrived")
                .font(font)
        default:
            Text(timerInterval: context.attributes.startDate...max(context.state.endDate, context.attributes.startDate.addingTimeInterval(1)),
                 countsDown: true,
                 showsHours: context.state.endDate.timeIntervalSince(context.attributes.startDate) >= 3600)
                .font(font)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Lock Screen

struct LockScreenTripView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: context.attributes.travelModeSymbol)
                    Text("To \(context.attributes.destinationName)")
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiveActivityPalette.ink)
                Text(LiveActivityPalette.headline(for: context.state.status))
                    .font(.caption2)
                    .foregroundStyle(LiveActivityPalette.inkSecondary)
                    .lineLimit(2)
                contactStack(context.attributes.contactInitials, size: 20)
                    .padding(.top, 2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                switch context.state.status {
                case .arrived:
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title)
                        .foregroundStyle(LiveActivityPalette.green)
                default:
                    Text(timerInterval: context.attributes.startDate...max(context.state.endDate, context.attributes.startDate.addingTimeInterval(1)),
                         countsDown: true,
                         showsHours: context.state.endDate.timeIntervalSince(context.attributes.startDate) >= 3600)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(LiveActivityPalette.ink)
                    if let metres = context.state.remainingDistanceMeters {
                        Text(LiveActivityPalette.distance(metres) + " to go")
                            .font(.caption2)
                            .foregroundStyle(LiveActivityPalette.inkSecondary)
                    }
                }
            }
        }
        .padding(16)
        // Drawn in the view too, so the white text always sits on a dark
        // background, even where the system doesn't apply the activity tint.
        .background(LiveActivityPalette.background(for: context.state.status))
    }
}

// MARK: - Shared pieces

@ViewBuilder
func contactStack(_ initials: [String], size: CGFloat) -> some View {
    HStack(spacing: -6) {
        ForEach(Array(initials.prefix(3).enumerated()), id: \.offset) { index, text in
            ZStack {
                Circle().fill(LiveActivityPalette.avatar(index))
                Text(text)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
        }
    }
}

/// High-contrast colours: white text on a solid dark tint stays readable on
/// any wallpaper, in light and dark mode, and when the system renders the
/// Lock Screen translucently.
enum LiveActivityPalette {
    static let ink = Color.white
    static let inkSecondary = Color.white.opacity(0.75)
    static let purple = Color(red: 0.70, green: 0.66, blue: 1.0)
    static let green = Color(red: 0.45, green: 0.86, blue: 0.55)
    static let red = Color(red: 1.0, green: 0.50, blue: 0.48)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.36)

    static func background(for status: TripActivityAttributes.Status) -> Color {
        switch status {
        case .onTheWay: Color(red: 0.13, green: 0.11, blue: 0.22)
        case .checkIn: Color(red: 0.30, green: 0.19, blue: 0.06)
        case .alerting: Color(red: 0.40, green: 0.09, blue: 0.10)
        case .arrived: Color(red: 0.07, green: 0.24, blue: 0.13)
        }
    }

    static func accent(for status: TripActivityAttributes.Status) -> Color {
        switch status {
        case .onTheWay: purple
        case .checkIn: amber
        case .alerting: red
        case .arrived: green
        }
    }

    static func symbol(for status: TripActivityAttributes.Status) -> String {
        switch status {
        case .onTheWay: "location.fill"
        case .checkIn: "questionmark.circle.fill"
        case .alerting: "exclamationmark.triangle.fill"
        case .arrived: "checkmark.shield.fill"
        }
    }

    static func headline(for status: TripActivityAttributes.Status) -> String {
        switch status {
        case .onTheWay: "Sharing with your circle"
        case .checkIn: "Are You OK? Tap to reply."
        case .alerting: "Alerting your circle"
        case .arrived: "Arrived. Sharing stopped."
        }
    }

    static func avatar(_ index: Int) -> Color {
        [Color(red: 0.43, green: 0.39, blue: 0.78), Color(red: 0.80, green: 0.36, blue: 0.42), Color(red: 0.72, green: 0.56, blue: 0.18)][index % 3]
    }

    static func distance(_ metres: Double) -> String {
        let measurement = Measurement(value: metres, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }
}

#Preview("Lock Screen", as: .content, using: TripActivityAttributes(destinationName: "Via dei Tribunali", travelModeSymbol: "figure.walk", contactInitials: ["M", "S", "F"], startDate: .now)) {
    TripLiveActivity()
} contentStates: {
    TripActivityAttributes.ContentState(endDate: .now.addingTimeInterval(990), status: .onTheWay, remainingDistanceMeters: 1200)
    TripActivityAttributes.ContentState(endDate: .now.addingTimeInterval(400), status: .checkIn, remainingDistanceMeters: 600)
    TripActivityAttributes.ContentState(endDate: .now, status: .arrived, remainingDistanceMeters: 0)
}
