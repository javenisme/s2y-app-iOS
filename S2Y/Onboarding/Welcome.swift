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
                        Image(systemName: "heart.text.clipboard")
                            .accessibilityHidden(true)
                    },
                    title: "Apple Health",
                    description: "WELCOME_AREA1_DESCRIPTION"
                ),
                OnboardingInformationView.Area(
                    icon: {
                        Image(systemName: "brain.head.profile")
                            .accessibilityHidden(true)
                    },
                    title: "Choose your AI",
                    description: "WELCOME_AREA2_DESCRIPTION"
                ),
                OnboardingInformationView.Area(
                    icon: {
                        Image(systemName: "hand.raised.fill")
                            .accessibilityHidden(true)
                    },
                    title: "You stay in control",
                    description: "WELCOME_AREA3_DESCRIPTION"
                )
            ],
            actionText: "Continue",
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
