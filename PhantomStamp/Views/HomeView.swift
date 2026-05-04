//
//  HomeView.swift
//  PhantomStamp
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(viewModel.greeting)
                    .font(.title.bold())

                Text("Tapped: \(viewModel.tapCount)")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Button("Tap me") {
                    viewModel.incrementTaps()
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh greeting") {
                    viewModel.refreshGreeting()
                }
                .buttonStyle(.bordered)

                SectionCaption(text: "Greeting comes from GreetingServicing (Services).")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("MVVM Example")
        }
    }
}

#Preview {
    HomeView()
}
