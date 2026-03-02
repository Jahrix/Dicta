import SwiftUI

enum PillHUDMode: Equatable {
    case idle
    case listening
    case transcribing
    case error
}

struct PillHUDRenderState: Equatable {
    var mode: PillHUDMode
    var waveformLevel: Double
    var theme: Theme
}

@MainActor
final class PillHUDViewModel: ObservableObject {
    @Published var state = PillHUDRenderState(mode: .idle, waveformLevel: 0, theme: RoyalThemes.defaultTheme)
}

struct PillHUDView: View {
    @ObservedObject var viewModel: PillHUDViewModel

    var body: some View {
        let theme = viewModel.state.theme
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ThemeManager.swiftUIColor(from: theme.iconHex))
                .frame(width: 16)

            WaveformView(level: viewModel.state.waveformLevel,
                         mode: viewModel.state.mode,
                         color: ThemeManager.swiftUIColor(from: theme.waveformHex))
        }
        .padding(.horizontal, 14)
        .frame(width: 170, height: 44)
        .background(
            Capsule(style: .continuous)
                .fill(ThemeManager.swiftUIColor(from: theme.backgroundHex).opacity(0.94))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(ThemeManager.swiftUIColor(from: theme.primaryHex).opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        )
    }

    private var iconName: String {
        switch viewModel.state.mode {
        case .idle:
            return "circle.fill"
        case .listening:
            return "mic.fill"
        case .transcribing:
            return "waveform"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}
