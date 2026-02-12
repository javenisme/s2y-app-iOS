//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziOnboarding
import SpeziViews
import SwiftUI


struct Welcome: View {
    @Environment(ManagedNavigationStack.Path.self) private var managedNavigationPath


    var body: some View {
        OnboardingView(
            title: "S2Y Health Assistant",
            subtitle: "WELCOME_SUBTITLE",
            areas: [
                OnboardingInformationView.Area(
                    icon: {
                        Image(systemName: "apps.iphone")
                            .accessibilityHidden(true)
                    },
                    title: "S2Y Platform",
                    description: "WELCOME_AREA1_DESCRIPTION"
                ),
                OnboardingInformationView.Area(
                    icon: {
                        Image(systemName: "shippingbox.fill")
                            .accessibilityHidden(true)
                    },
                    title: "Swift Package Manager",
                    description: "WELCOME_AREA2_DESCRIPTION"
                ),
                OnboardingInformationView.Area(
                    icon: {
                        Image(systemName: "list.bullet.clipboard.fill")
                            .accessibilityHidden(true)
                    },
                    title: "Core Modules",
                    description: "WELCOME_AREA3_DESCRIPTION"
                )
            ],
            actionText: "Learn More",
            action: {
                managedNavigationPath.nextStep()
            }
        )
        .padding(.top, 24)
    }
}


#Preview {
    ManagedNavigationStack {
        Welcome()
    }
}
