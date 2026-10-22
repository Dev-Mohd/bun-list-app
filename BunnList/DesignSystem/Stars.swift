import SwiftUI

/// Read-only star display for a 1–5 value.
struct StarsDisplay: View {
    let value: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= value ? "star.fill" : "star")
                    .foregroundStyle(Brand.gold)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) من ٥")
    }
}

/// Editable 1–5 star control. Tapping the current value again clears to 0 (no rating).
struct StarRatingControl: View {
    let value: Int
    var label = "تقييمك"
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    onChange(i == value ? 0 : i)
                } label: {
                    Image(systemName: i <= value ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(Brand.gold)
                        .frame(minWidth: 36, minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label): \(i)")
                .accessibilityAddTraits(i == value ? [.isSelected] : [])
                .accessibilityIdentifier("star-\(i)")
            }
        }
    }
}
