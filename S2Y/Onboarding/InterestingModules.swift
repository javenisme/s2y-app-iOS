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


struct InterestingModules: View {
    @Environment(ManagedNavigationStack.Path.self) private var managedNavigationPath
    
    
    var body: some View {
        SequentialOnboardingView(
            title: "Before You Start",
            subtitle: "INTERESTING_MODULES_SUBTITLE",
            steps: [
                SequentialOnboardingView.Step(
                    title: "Health data",
                    description: "INTERESTING_MODULES_AREA1_DESCRIPTION"
                ),
                SequentialOnboardingView.Step(
                    title: "AI processing",
                    description: "INTERESTING_MODULES_AREA2_DESCRIPTION"
                ),
                SequentialOnboardingView.Step(
                    title: "Account and sync",
                    description: "INTERESTING_MODULES_AREA3_DESCRIPTION"
                ),
                SequentialOnboardingView.Step(
                    title: "Health management",
                    description: "INTERESTING_MODULES_AREA4_DESCRIPTION"
                )
            ],
            actionText: "Next",
            action: {
                managedNavigationPath.nextStep()
            }
        )
    }
}


#Preview {
    ManagedNavigationStack {
        InterestingModules()
    }
}
