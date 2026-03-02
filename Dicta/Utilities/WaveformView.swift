import SwiftUI

struct WaveformView: View {
    let level: Double
    let mode: PillHUDMode
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
            let heights = barHeights(at: timeline.date)
            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                    Capsule()
                        .fill(color)
                        .frame(width: 6, height: height)
                }
            }
            .frame(height: 22)
        }
    }

    private func barHeights(at date: Date) -> [CGFloat] {
        let clamped = min(max(level, 0), 1)
        let baseline: Double
        switch mode {
        case .listening:
            baseline = max(0.16, clamped)
        case .transcribing:
            let pulse = (sin(date.timeIntervalSinceReferenceDate * 4.0) + 1.0) / 2.0
            baseline = 0.22 + pulse * 0.18
        case .error:
            baseline = 0.12
        case .idle:
            baseline = 0.10
        }

        return (0..<5).map { index in
            let phase = date.timeIntervalSinceReferenceDate * 3.0 + Double(index) * 0.55
            let swing = (sin(phase) + 1.0) / 2.0
            let normalized = min(max(baseline * (0.65 + swing * 0.8), 0.12), 1.0)
            return CGFloat(6.0 + normalized * 16.0)
        }
    }
}
