import SwiftUI

struct DashboardView: View {
    @ObservedObject var settings: SettingsModel
    @State private var selection: DashboardSection? = .home

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
        } detail: {
            switch selection ?? .home {
            case .home:
                HomePage(onOpenSettings: { selection = .settings })
            case .dictionary:
                DictionaryPage()
            case .snippets:
                SnippetsPage()
            case .style:
                StylePage()
            case .notes:
                NotesPage()
            case .settings:
                SettingsPage(settings: settings)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
