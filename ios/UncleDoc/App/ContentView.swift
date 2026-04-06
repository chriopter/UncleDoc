import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.pink)

                Text("UncleDoc")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Family Health Tracker")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("UncleDoc")
        }
    }
}

#Preview {
    ContentView()
}
