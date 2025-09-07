//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport) import SpeziAccount
import SwiftUI


struct HomeView: View {
    enum Tabs: String {
        case healthAssistant
        case schedule
        case contact
        case showcase
    }
    
    
    @AppStorage(StorageKeys.homeTabSelection) private var selectedTab = Tabs.healthAssistant
    @AppStorage(StorageKeys.tabViewCustomization) private var tabViewCustomization = TabViewCustomization()
    
    @State private var presentingAccount = false
    
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Health Assistant", systemImage: "heart.text.square", value: .healthAssistant) {
                HealthAssistantView()
            }
                .customizationID("home.healthAssistant")
            Tab("Schedule", systemImage: "list.clipboard", value: .schedule) {
                ScheduleView(presentingAccount: $presentingAccount)
            }
                .customizationID("home.schedule")
            Tab("Account", systemImage: "person.crop.circle", value: .contact) {
                ProfileView()
            }
                .customizationID("home.contacts")
            Tab("Settings", systemImage: "gear", value: .showcase) {
                ShowcaseView()
            }
                .customizationID("home.showcase")
        }
            .tabViewStyle(.sidebarAdaptable)
            .tabViewCustomization($tabViewCustomization)
            .sheet(isPresented: $presentingAccount) {
                AccountSheet(dismissAfterSignIn: false) // presentation was user initiated, do not automatically dismiss
            }
            .accountRequired(!FeatureFlags.disableFirebase && !FeatureFlags.skipOnboarding) {
                AccountSheet()
            }
    }
}


#if DEBUG
#Preview {
    var details = AccountDetails()
    details.userId = "lelandstanford@stanford.edu"
    details.name = PersonNameComponents(givenName: "Leland", familyName: "Stanford")
    
    return HomeView()
        .previewWith(standard: S2YApplicationStandard()) {
            S2YApplicationScheduler()
            AccountConfiguration(service: InMemoryAccountService(), activeDetails: details)
        }
}
#endif
