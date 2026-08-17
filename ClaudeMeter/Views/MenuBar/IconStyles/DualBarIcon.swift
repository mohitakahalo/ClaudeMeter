//
//  DualBarIcon.swift
//  ClaudeMeter
//
//  Created by Edd on 2025-12-28.
//

import SwiftUI

/// Dual bar menu bar icon showing session (top) and weekly (bottom) usage.
///
/// Falls back to a single session bar when the account has no weekly limit:
/// a full-width empty bar is indistinguishable from an untouched weekly quota,
/// which reads as reassuring rather than as "not applicable".
struct DualBarIcon: View {
    let percentage: Double         // Session percentage
    let weeklyPercentage: Double?  // Weekly percentage, nil when the account has no weekly limit
    let status: UsageStatus
    let isLoading: Bool
    let isStale: Bool
    var overrideText: String?  // Replaces the percentage text (pace-first display)
    var overrideColor: Color?  // Color for the override text

    private let barWidth: CGFloat = 32
    private let barHeight: CGFloat = 5
    private let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: 4) {
            if isLoading {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
            } else {
                // Two stacked progress bars
                VStack(spacing: barSpacing) {
                    // Session bar (top) - blue/cyan
                    ProgressBar(
                        percentage: percentage,
                        color: sessionBarColor,
                        isStale: isStale
                    )
                    .frame(width: barWidth, height: barHeight)

                    // Weekly bar (bottom) - purple. Omitted entirely when there
                    // is no weekly limit, leaving a single centred session bar.
                    if let weeklyPercentage {
                        ProgressBar(
                            percentage: weeklyPercentage,
                            color: weeklyBarColor,
                            isStale: isStale
                        )
                        .frame(width: barWidth, height: barHeight)
                    }
                }

                // Show session percentage (or pace, primary metric)
                Text(overrideText ?? "\(Int(percentage))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(textColor)
            }

            if isStale && !isLoading {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.gray)
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 4)
        .accessibilityLabel(
            weeklyPercentage.map { "Session: \(Int(percentage)) percent, Weekly: \(Int($0)) percent" }
                ?? "Session: \(Int(percentage)) percent, no weekly limit"
        )
        .accessibilityValue(status.accessibilityDescription)
    }

    private var statusColor: Color {
        isStale ? .gray : status.color
    }

    private var textColor: Color {
        IconPalette.textColor(isStale: isStale, override: overrideColor, status: status)
    }

    private var sessionBarColor: Color {
        if isStale { return .gray }
        // Use status color for session bar
        return status.color
    }

    private var weeklyBarColor: Color {
        if isStale { return .gray }
        // Purple/violet for weekly to distinguish from session
        return .purple
    }
}

/// Individual progress bar component
private struct ProgressBar: View {
    let percentage: Double
    let color: Color
    let isStale: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.gray.opacity(0.3))

                // Fill
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: geo.size.width * min(percentage / 100, 1.0))
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            DualBarIcon(percentage: 35, weeklyPercentage: 20, status: .safe, isLoading: false, isStale: false)
            DualBarIcon(percentage: 65, weeklyPercentage: 45, status: .warning, isLoading: false, isStale: false)
            DualBarIcon(percentage: 92, weeklyPercentage: 78, status: .critical, isLoading: false, isStale: false)
        }
        HStack(spacing: 20) {
            DualBarIcon(percentage: 45, weeklyPercentage: 30, status: .safe, isLoading: true, isStale: false)
            DualBarIcon(percentage: 45, weeklyPercentage: 30, status: .safe, isLoading: false, isStale: true)
        }
    }
    .padding()
}
