import SwiftUI
import UIKit
import WebKit

struct ContentView: View {
    @StateObject private var coordinator = AppCoordinator.shared
    @State private var demoModeEnabled = false
    @State private var serverURLText = AppCoordinator.shared.serverURL?.absoluteString ?? ""
    private let autoOpenDemoMode = ProcessInfo.processInfo.arguments.contains("-open-demo-mode")

    var body: some View {
        Group {
            if coordinator.serverURL == nil {
                if demoModeEnabled {
                    DemoSiteContainerView(onConnectToServer: { demoModeEnabled = false })
                } else {
                    onboardingView
                }
            } else {
                AppShellContainerView(coordinator: coordinator)
                    .ignoresSafeArea()
                    .id(coordinator.serverURL?.absoluteString ?? "app-shell")
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.92), value: coordinator.serverURL?.absoluteString)
        .animation(.spring(response: 0.32, dampingFraction: 0.92), value: demoModeEnabled)
        .onReceive(coordinator.$serverURL) { url in
            if let url {
                serverURLText = url.absoluteString
            }
        }
        .onAppear {
            guard coordinator.serverURL == nil, autoOpenDemoMode else {
                return
            }

            demoModeEnabled = true
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
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("UncleDoc")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Sign in to your server or try the offline demo.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Server URL")
                            .font(.headline)

                        TextField("https://uncledoc.example.com", text: $serverURLText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )

                        if let validationMessage = coordinator.validationMessage {
                            Text(validationMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        } else {
                            Text("Example: `https://uncledoc.example.com`")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            demoModeEnabled = false
                            coordinator.saveServerURL(from: serverURLText)
                        } label: {
                            Text("Continue to login")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)

                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.black.opacity(0.08))
                                .frame(height: 1)

                            Text("or")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Rectangle()
                                .fill(Color.black.opacity(0.08))
                                .frame(height: 1)
                        }

                        Button {
                            demoModeEnabled = true
                        } label: {
                            Text("Open demo mode")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        }
                        .buttonStyle(.bordered)
                        .tint(.black)

                        Text("Try UncleDoc with local sample data.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(22)
                    .background(.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct DemoSiteContainerView: View {
    let onConnectToServer: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DemoSiteWebView()

            Button {
                onConnectToServer()
            } label: {
                Label("Connect server", systemImage: "server.rack")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
    }
}

private struct DemoSiteWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: "uncledocDemo")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        guard let rootURL = DemoSiteLocator.rootURL,
              let indexURL = DemoSiteLocator.indexURL else {
            webView.loadHTMLString(
                "<html><body style='font-family:-apple-system;padding:24px'><h1>Demo site missing</h1><p>Run script/export_demo_site to regenerate the offline bundle.</p></body></html>",
                baseURL: nil
            )
            return webView
        }

        webView.loadFileURL(indexURL, allowingReadAccessTo: rootURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        private let autoOpenMenu = ProcessInfo.processInfo.arguments.contains("-open-demo-menu")
        private var didAutoOpenMenu = false

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "uncledocDemo",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            switch type {
            case "requestHealthAccess":
                Task {
                    await requestHealthAccess()
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard autoOpenMenu, !didAutoOpenMenu else {
                return
            }

            didAutoOpenMenu = true
            webView.evaluateJavaScript("document.querySelector('[data-dropdown-target=\"menu\"]')?.classList.remove('hidden')")
        }

        @MainActor
        private func requestHealthAccess() async {
            do {
                try await HealthKitManager.shared.requestAuthorization()
                let records = try await HealthKitManager.shared.loadRecentRecords(limit: 8, maxPerType: 1)
                let payload: [String: Any] = [
                    "type": "healthkitRecords",
                    "records": records.map { record in
                        [
                            "title": record.title,
                            "rawText": record.rawText,
                            "startDate": record.startDate.ISO8601Format()
                        ]
                    }
                ]
                send(payload)
            } catch {
                send([
                    "type": "healthkitError",
                    "message": error.localizedDescription
                ])
            }
        }

        @MainActor
        private func send(_ payload: [String: Any]) {
            guard let webView,
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }

            webView.evaluateJavaScript("window.UncleDocDemo && window.UncleDocDemo.receiveNativeMessage(\(json));")
        }
    }
}

private enum DemoSiteLocator {
    private static let processArguments = ProcessInfo.processInfo.arguments

    static var rootURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("DemoSite", isDirectory: true)
    }

    static var indexURL: URL? {
        guard let rootURL else {
            return nil
        }

        let relativePath = selectedRelativePath() ?? "Demo Nora/overview/index.html"
        return relativePath
            .split(separator: "/")
            .reduce(rootURL) { partialURL, component in
                partialURL.appendingPathComponent(String(component), isDirectory: component != "index.html")
            }
    }

    private static func selectedRelativePath() -> String? {
        guard let flagIndex = processArguments.firstIndex(of: "-demo-path"),
              processArguments.indices.contains(flagIndex + 1) else {
            return nil
        }

        return processArguments[flagIndex + 1]
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
