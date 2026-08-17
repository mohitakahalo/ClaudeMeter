//
//  SpendCardView.swift
//  ClaudeMeter
//

import SwiftUI

/// Extra-usage credits card.
///
/// Deliberately not a `UsageCardView`: credits have no rolling window, so pace,
/// projection and reset time — everything that card is built around — have no
/// meaning here. What matters is how much is left.
struct SpendCardView: View {
    let spend: SpendUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "creditcard")
                    .font(.title3)
                    .foregroundColor(spend.status.color)

                Text("Extra Usage Credits")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if spend.isEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: spend.status.iconName)
                            .font(.caption)
                        Text(spend.status.rawValue.capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(spend.status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(spend.status.color.opacity(0.15))
                    .cornerRadius(8)
                } else {
                    Text("Off")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                }
            }

            HStack(alignment: .lastTextBaseline) {
                Text(spend.remainingDescription)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(spend.status.color)

                Text("left")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(spend.usedDescription) used")
                        .font(.caption)
                        .foregroundColor(spend.status.color)
                    Text("of \(spend.limitDescription)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(spend.status.color)
                        .frame(width: geometry.size.width * min(spend.percentage / 100, 1.0))
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text(spend.isEnabled
                     ? "\(Int(spend.percentage.rounded()))% of your credit cap used"
                     : "Extra usage is turned off for this account")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Extra usage credits. \(spend.usedDescription) used of \(spend.limitDescription), \(spend.remainingDescription) remaining."
        )
    }
}
