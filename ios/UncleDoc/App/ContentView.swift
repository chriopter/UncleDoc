import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var coordinator = AppCoordinator.shared
    @State private var serverURLText = AppCoordinator.shared.serverURL?.absoluteString ?? ""

    var body: some View {
        Group {
            if coordinator.serverURL == nil {
                onboardingView
            } else {
                AppShellContainerView(coordinator: coordinator)
                    .ignoresSafeArea()
                    .id(coordinator.serverURL?.absoluteString ?? "app-shell")
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.92), value: coordinator.serverURL?.absoluteString)
        .onReceive(coordinator.$serverURL) { url in
            if let url {
                serverURLText = url.absoluteString
            }
        }
    }

    private var onboardingView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.96, blue: 0.90),
                    Color(red: 0.96, green: 0.92, blue: 0.98),
                    Color(red: 0.93, green: 0.97, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("UncleDoc")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Connect your self-hosted server and keep the full UncleDoc experience inside the native app.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Server URL")
                            .font(.headline)

                        TextField("http://192.168.1.20:3000", text: $serverURLText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )

                        if let validationMessage = coordinator.validationMessage {
                            Text(validationMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        } else {
                            Text("Examples: `http://192.168.1.20:3000` on your LAN or `https://uncledoc.example.com`.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 12) {
                        Button {
                            coordinator.saveServerURL(from: serverURLText)
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)

                        Button {
                            if let pasted = UIPasteboard.general.string {
                                serverURLText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Text("Paste from clipboard")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("What happens next", systemImage: "sparkles")
                            .font(.headline)

                        Text("The app stores your server URL locally, opens UncleDoc through Hotwire Native, and securely provisions an app token for HealthKit sync after you sign in.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .padding(24)
                .frame(maxWidth: 560)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct AppShellContainerView: UIViewControllerRepresentable {
    @ObservedObject var coordinator: AppCoordinator

    func makeUIViewController(context: Context) -> UIViewController {
        coordinator.makeShellViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        coordinator.refreshShellViewController(uiViewController)
    }
}

#Preview {
    ContentView()
}
