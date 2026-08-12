import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            TodoListView()
                .tabItem { Label("待办", systemImage: "checklist") }

            CalendarView()
                .tabItem { Label("日历", systemImage: "calendar") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
