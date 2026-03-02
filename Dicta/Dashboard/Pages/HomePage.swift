import SwiftUI

struct HomePage: View {
    var onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dicta Dashboard")
                    .font(.system(size: 28, weight: .semibold))

                HStack(spacing: 16) {
                    statusCard
                    statsCard
                }

                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)
            Text("Dictation: Idle")
                .font(.title3)
            Text("Status hooks can be wired in later.")
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Stats")
                .font(.headline)
            Text("Words: 0")
            Text("WPM: 0")
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
    }
}
