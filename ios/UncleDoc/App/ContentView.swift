import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello World")
            .font(.largeTitle)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.yellow)
    }
}

#Preview {
    ContentView()
}
