import SwiftUI

@main
struct BorsaApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Palette.accent)
                .preferredColorScheme(store.preferredColorScheme)
                .environment(\.locale, Locale(identifier: "tr_TR"))
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: AppTab = .market
    private enum AppTab: Hashable { case market, watchlist, portfolio, orders }
    var body: some View {
        Group {
            if store.recoveryRequired {
                PreferencesView(recoveryMode: true)
            } else {
                TabView(selection: $selectedTab) {
                    MarketView(watchlistOnly: false)
                        .tabItem { Label("Piyasa", systemImage: "chart.xyaxis.line") }.tag(AppTab.market)
                    MarketView(watchlistOnly: true)
                        .tabItem { Label("Takip", systemImage: "star") }.tag(AppTab.watchlist)
                    PortfolioView()
                        .tabItem { Label("Portföy", systemImage: "square.stack.3d.up") }.tag(AppTab.portfolio)
                    OrdersView()
                        .tabItem { Label("Emirler", systemImage: "arrow.left.arrow.right") }.tag(AppTab.orders)
                }
            }
        }
        .alert("İşlem tamamlanamadı", isPresented: Binding(
            get: { store.storageMessage != nil && !store.recoveryRequired },
            set: { if !$0 { store.storageMessage = nil } }
        )) { Button("Tamam") { store.storageMessage = nil } }
        message: { Text(store.storageMessage ?? "") }
    }
}
