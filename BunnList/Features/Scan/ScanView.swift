import SwiftUI

/// The scan tab: the AI bag scan, with search-by-name and suggesting a coffee for
/// when the bag isn't at hand.
struct ScanView: View {
    var body: some View {
        AIBagScanView(embedded: true)
    }
}
