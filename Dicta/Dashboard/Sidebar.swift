import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case style = "Style"
    case notes = "Notes"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "text.book.closed"
        case .snippets: return "scissors"
        case .style: return "paintbrush"
        case .notes: return "note.text"
        case .settings: return "gearshape"
        }
    }
}

struct Sidebar: View {
    @Binding var selection: DashboardSection?

    var body: some View {
        List(DashboardSection.allCases, selection: $selection) { section in
            Label(section.rawValue, systemImage: section.systemImage)
                .tag(section)
        }
        .listStyle(.sidebar)
    }
}
