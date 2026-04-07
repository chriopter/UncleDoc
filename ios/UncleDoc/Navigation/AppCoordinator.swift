import Combine
import Foundation
@preconcurrency import HotwireNative
import SafariServices
import UIKit
import WebKit

extension Notification.Name {
    static let uncleDocWebViewDidStartLoading = Notification.Name("uncledoc.webview.didStartLoading")
    static let uncleDocWebViewDidFinishLoading = Notification.Name("uncledoc.webview.didFinishLoading")
}

final class LaunchAwareWebView: WKWebView {
    private var loadingObservation: NSKeyValueObservation?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        observeLoadingState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func observeLoadingState() {
        loadingObservation = observe(\.isLoading, options: [.new]) { _, change in
            guard let isLoading = change.newValue else {
                return
            }

            NotificationCenter.default.post(name: isLoading ? .uncleDocWebViewDidStartLoading : .uncleDocWebViewDidFinishLoading, object: nil)
        }
    }
}

@MainActor
final class AppCoordinator: NSObject, ObservableObject {
    static let shared = AppCoordinator()

    @Published private(set) var serverURL: URL?
    @Published private(set) var validationMessage: String?

    private var shellViewController: UncleDocShellViewController?
    private static var didConfigureHotwire = false

    override init() {
        serverURL = ServerURLStore.load()
        super.init()
        configureHotwireIfNeeded()
    }

    func saveServerURL(from rawValue: String) {
        guard let url = Self.normalizeServerURL(rawValue) else {
            validationMessage = "Enter a valid UncleDoc server URL."
            return
        }

        validationMessage = nil
        ServerURLStore.save(url)
        serverURL = url
        shellViewController = nil
    }

    func resetServerURL() {
        validationMessage = nil
        ServerURLStore.clear()
        serverURL = nil
        shellViewController = nil
    }

    func makeShellViewController() -> UIViewController {
        guard let serverURL else {
            return UIViewController()
        }

        if let shellViewController, shellViewController.baseURL == serverURL {
            return shellViewController
        }

        let shellViewController = UncleDocShellViewController(baseURL: serverURL, coordinator: self)
        self.shellViewController = shellViewController
        return shellViewController
    }

    func refreshShellViewController(_ viewController: UIViewController) {
        guard let shellViewController = viewController as? UncleDocShellViewController else {
            return
        }

        shellViewController.refreshChrome()
    }

    func route(to destination: AppDestination) {
        shellViewController?.route(to: destination)
    }

    func openCurrentPageInSafari() {
        shellViewController?.openCurrentPageInSafari()
    }

    func reloadCurrentPage() {
        shellViewController?.reloadCurrentPage()
    }

    func handleNativeMenuAction(named action: String) {
        switch action {
        case "health_sync":
            shellViewController?.presentHealthRecords()
        case "app_settings":
            shellViewController?.presentAppSettings()
        case "health_records":
            shellViewController?.presentHealthRecords()
        case "reload":
            reloadCurrentPage()
        case "open_in_safari":
            openCurrentPageInSafari()
        case "change_server":
            resetServerURL()
        default:
            break
        }
    }

    func handleFinishedRequest(at url: URL) {
        shellViewController?.syncSelection(with: url)
    }

    private func configureHotwireIfNeeded() {
        guard !Self.didConfigureHotwire else {
            return
        }

        Hotwire.config.applicationUserAgentPrefix = "UncleDoc iOS"
        Hotwire.config.showDoneButtonOnModals = true
        Hotwire.config.backButtonDisplayMode = .minimal
        Hotwire.config.makeCustomWebView = { configuration in
            NativeMenuScriptBridge.shared.attach(to: configuration.userContentController)
            let webView = LaunchAwareWebView(frame: .zero, configuration: configuration)
            webView.allowsBackForwardNavigationGestures = true
            webView.isOpaque = false
            webView.backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
            webView.scrollView.backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.scrollView.alwaysBounceHorizontal = false
            webView.scrollView.showsHorizontalScrollIndicator = false
            webView.scrollView.pinchGestureRecognizer?.isEnabled = false
            return webView
        }
        Hotwire.loadPathConfiguration(from: [.data(Self.pathConfigurationData)])

        Self.didConfigureHotwire = true
    }

    private static var pathConfigurationData: Data {
        let json = """
        {
          "settings": {},
          "rules": [
            {
              "patterns": [".*"],
              "properties": {
                "context": "default"
              }
            }
          ]
        }
        """

        return Data(json.utf8)
    }

    private static func normalizeServerURL(_ rawValue: String) -> URL? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if !value.contains("://") {
            value = defaultScheme(for: value) + value
        }

        guard var components = URLComponents(string: value) else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }

        components.scheme = scheme
        components.fragment = nil

        guard components.host != nil else {
            return nil
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmedPath.isEmpty ? "/" : "/\(trimmedPath)/"

        guard let url = components.url else {
            return nil
        }

        return url
    }

    private static func defaultScheme(for value: String) -> String {
        if value.contains("localhost") || value.contains(":") || value.hasSuffix(".local") || value.range(of: #"^\d{1,3}(\.\d{1,3}){3}(?::\d+)?$"#, options: .regularExpression) != nil {
            return "http://"
        }

        return "https://"
    }
}

enum ServerURLStore {
    private static let key = "uncledoc.server_url"

    static func load() -> URL? {
        guard let value = UserDefaults.standard.string(forKey: key) else {
            return nil
        }

        return URL(string: value)
    }

    static func save(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

enum TrustedCertificateStore {
    private static let key = "uncledoc.trusted_certificate_hosts"

    static func contains(_ protectionSpace: URLProtectionSpace) -> Bool {
        trustedHosts.contains(hostKey(for: protectionSpace))
    }

    static func trust(_ protectionSpace: URLProtectionSpace) {
        var hosts = trustedHosts
        hosts.insert(hostKey(for: protectionSpace))
        UserDefaults.standard.set(Array(hosts), forKey: key)
    }

    private static var trustedHosts: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private static func hostKey(for protectionSpace: URLProtectionSpace) -> String {
        let portSuffix = protectionSpace.port > 0 ? ":\(protectionSpace.port)" : ""
        return "\(protectionSpace.host.lowercased())\(portSuffix)"
    }
}

@MainActor
final class NativeMenuScriptBridge: NSObject, WKScriptMessageHandler {
    static let shared = NativeMenuScriptBridge()
    static let handlerName = "uncleDocNativeMenu"

    func attach(to userContentController: WKUserContentController) {
        userContentController.removeScriptMessageHandler(forName: Self.handlerName)
        userContentController.add(self, name: Self.handlerName)
        userContentController.addUserScript(
            WKUserScript(
                source: Self.scriptSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName,
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        AppCoordinator.shared.handleNativeMenuAction(named: action)
    }

    private static let scriptSource = #"""
    (() => {
      const handlerName = "uncleDocNativeMenu";
      const healthSyncComplete = __HEALTH_SYNC_COMPLETE__;
      const config = {
        mobile: [
          { action: "app_settings", label: "App Settings", icon: "M4.5 12a7.5 7.5 0 1 0 15 0 7.5 7.5 0 0 0-15 0Zm7.5-3v3l2.25 2.25" }
        ],
        desktop: [
          { action: "app_settings", label: "App Settings", icon: "M4.5 12a7.5 7.5 0 1 0 15 0 7.5 7.5 0 0 0-15 0Zm7.5-3v3l2.25 2.25" }
        ],
        "data-mobile": [
          { action: "health_sync", label: "Health Sync", icon: "M12 21c4.5-2.55 7.5-6.18 7.5-10.41A4.59 4.59 0 0 0 15 6c-1.35 0-2.58.57-3 1.5C11.58 6.57 10.35 6 9 6a4.59 4.59 0 0 0-4.5 4.59C4.5 14.82 7.5 18.45 12 21", complete: healthSyncComplete }
        ],
        "data-desktop": [
          { action: "health_sync", label: "Health Sync", icon: "M12 21c4.5-2.55 7.5-6.18 7.5-10.41A4.59 4.59 0 0 0 15 6c-1.35 0-2.58.57-3 1.5C11.58 6.57 10.35 6 9 6a4.59 4.59 0 0 0-4.5 4.59C4.5 14.82 7.5 18.45 12 21", complete: healthSyncComplete }
        ]
      };

      const buildButton = (item, variant) => {
        const button = document.createElement("button");
        button.type = "button";
        button.dataset.nativeMenuAction = item.action;
        button.className = variant === "mobile"
          ? "flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold text-slate-700 transition hover:bg-amber-50"
          : "flex w-full items-center gap-3 rounded-[1.15rem] px-3 py-3 text-sm font-semibold text-slate-700 transition hover:bg-white";

        const iconWrap = document.createElement("span");
        iconWrap.className = variant === "mobile"
          ? "flex h-4 w-4 items-center justify-center text-slate-500"
          : "flex h-8 w-8 items-center justify-center rounded-xl bg-amber-50 text-amber-700";

        const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
        svg.setAttribute("viewBox", "0 0 24 24");
        svg.setAttribute("fill", "none");
        svg.setAttribute("stroke", "currentColor");
        svg.setAttribute("stroke-width", variant === "mobile" ? "1.8" : "1.8");
        svg.setAttribute("class", variant === "mobile" ? "h-4 w-4" : "h-4 w-4");

        const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
        path.setAttribute("stroke-linecap", "round");
        path.setAttribute("stroke-linejoin", "round");
        path.setAttribute("d", item.icon);
        svg.appendChild(path);
        iconWrap.appendChild(svg);

        const label = document.createElement("span");
        label.textContent = item.label;

        button.appendChild(iconWrap);
        button.appendChild(label);

        if (item.complete) {
          const dot = document.createElement("span");
          dot.className = "ml-auto inline-block h-2.5 w-2.5 rounded-full bg-emerald-500";
          button.appendChild(dot);
        }

        button.addEventListener("click", () => {
          window.webkit?.messageHandlers?.[handlerName]?.postMessage({ action: item.action });
        });

        return button;
      };

      const renderSlot = (slot) => {
        const variant = slot.dataset.nativeMenuSlot;
        const items = config[variant] || [];
        if (!items.length) return;

        slot.innerHTML = "";
        slot.classList.remove("hidden");

        const wrapper = document.createElement("div");
        wrapper.className = variant === "mobile" ? "space-y-0.5" : "space-y-1";

        items.forEach((item) => wrapper.appendChild(buildButton(item, variant)));
        slot.appendChild(wrapper);
      };

      const boot = () => {
        document.querySelectorAll("[data-native-menu-slot]").forEach(renderSlot);
      };

      boot();
      document.addEventListener("turbo:load", boot);
      document.addEventListener("turbo:render", boot);
    })();
    """#.replacingOccurrences(of: "__HEALTH_SYNC_COMPLETE__", with: HealthKitSyncService.shared.configuration.lastSuccessfulSyncAt != nil ? "true" : "false")
}

final class AuthenticationChallengeResponder: @unchecked Sendable {
    private let completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

    init(_ completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        self.completionHandler = completionHandler
    }

    func complete(_ disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?) {
        completionHandler(disposition, credential)
    }
}

enum AppDestination: CaseIterable {
    case home
    case users
    case llm
    case database
    case settings

    var title: String {
        switch self {
        case .home: return "Home"
        case .users: return "People"
        case .llm: return "AI"
        case .database: return "Database"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "Dashboard and current family context"
        case .users: return "Manage people and family records"
        case .llm: return "Model, provider, and prompt settings"
        case .database: return "Raw data browser"
        case .settings: return "Language, date format, and preferences"
        }
    }

    var systemImageName: String {
        switch self {
        case .home: return "house"
        case .users: return "person.2"
        case .llm: return "sparkles"
        case .database: return "shippingbox"
        case .settings: return "gearshape"
        }
    }

    var relativePath: String {
        switch self {
        case .home: return ""
        case .users: return "settings/users"
        case .llm: return "settings/llm"
        case .database: return "settings/db"
        case .settings: return "settings"
        }
    }

    func matches(_ url: URL, baseURL: URL) -> Bool {
        let absoluteString = url.absoluteString
        let routeURL = resolvedURL(relativeTo: baseURL).absoluteString

        switch self {
        case .home:
            return absoluteString == routeURL || absoluteString == baseURL.absoluteString
        case .users, .llm, .database:
            return absoluteString.hasPrefix(routeURL)
        case .settings:
            return absoluteString.hasPrefix(routeURL)
        }
    }

    func resolvedURL(relativeTo baseURL: URL) -> URL {
        if relativePath.isEmpty {
            return baseURL
        }

        return URL(string: relativePath, relativeTo: baseURL)?.absoluteURL ?? baseURL
    }

    static func bestMatch(for url: URL, baseURL: URL) -> AppDestination {
        let ordered: [AppDestination] = [.users, .llm, .database, .settings, .home]
        return ordered.first(where: { $0.matches(url, baseURL: baseURL) }) ?? .home
    }
}

@MainActor
private final class UncleDocShellViewController: UIViewController {
    private enum LaunchState {
        case connecting
        case connected
        case failed(String)
    }

    let baseURL: URL

    private unowned let coordinator: AppCoordinator
    private lazy var navigator = Navigator(
        configuration: .init(name: "UncleDoc", startLocation: baseURL),
        delegate: self
    )
    private let sidebarViewController = SidebarViewController()
    private let contentContainerView = UIView()
    private let dimmingButton = UIButton(type: .system)
    private let launchOverlayView = UIView()
    private let launchSpinner = UIActivityIndicatorView(style: .large)
    private let launchTitleLabel = UILabel()
    private let launchMessageLabel = UILabel()
    private let launchActionsStackView = UIStackView()
    private let compactSidebarWidth: CGFloat = 304
    private let regularSidebarWidth: CGFloat = 286
    private var sidebarLeadingConstraint: NSLayoutConstraint?
    private var contentLeadingToViewConstraint: NSLayoutConstraint?
    private var contentLeadingToSidebarConstraint: NSLayoutConstraint?
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var didStartNavigator = false
    private var isSidebarPresented = false
    private var currentURL: URL?
    private var launchState: LaunchState = .connecting
    private var webViewLoadObservers: [NSObjectProtocol] = []
    private var hasStartedInitialPageLoad = false

    init(baseURL: URL, coordinator: AppCoordinator) {
        self.baseURL = baseURL
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1)
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _) in
            self.refreshChrome()
        }
        setupSidebar()
        setupContentContainer()
        setupLaunchOverlay()
        observeWebViewLoading()
        setupGestures()
        refreshChrome()

        sidebarViewController.configure(
            serverURL: baseURL,
            currentURL: currentURL,
            onDestinationSelected: { [weak self] destination in
                self?.route(to: destination)
            },
            onOpenInSafari: { [weak self] in
                self?.openCurrentPageInSafari()
            },
            onReload: { [weak self] in
                self?.reloadCurrentPage()
            },
            onChangeServer: { [weak self] in
                self?.presentServerActions()
            }
        )

        if !didStartNavigator {
            didStartNavigator = true
            navigator.start()
        }

        configureNavigationBarAppearance()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigator.rootViewController.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshChrome()
    }

    func route(to destination: AppDestination) {
        navigator.route(destination.resolvedURL(relativeTo: baseURL))
        if isCompactLayout {
            setSidebarVisible(false, animated: true)
        }
    }

    func reloadCurrentPage() {
        updateLaunchOverlay(for: .connecting)
        navigator.reload()
    }

    func openCurrentPageInSafari() {
        let url = currentURL ?? baseURL
        UIApplication.shared.open(url)
    }

    func presentHealthRecords() {
        let viewController = HealthSyncViewController(syncService: HealthKitSyncService.shared)
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet

        if let sheetPresentationController = navigationController.sheetPresentationController {
            sheetPresentationController.detents = [.medium(), .large()]
            sheetPresentationController.prefersGrabberVisible = true
        }

        present(navigationController, animated: true)
    }

    func presentAppSettings() {
        let viewController = AppSettingsViewController(
            onReload: { [weak self] in self?.reloadCurrentPage() },
            onOpenInSafari: { [weak self] in self?.openCurrentPageInSafari() },
            onChangeServer: { [weak self] in self?.presentServerActions() },
            onShowHealthRecords: { [weak self] in self?.presentHealthRecords() }
        )

        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .pageSheet

        if let sheetPresentationController = navigationController.sheetPresentationController {
            sheetPresentationController.detents = [.medium(), .large()]
            sheetPresentationController.prefersGrabberVisible = true
        }

        present(navigationController, animated: true)
    }

    func syncSelection(with url: URL) {
        currentURL = url
        sidebarViewController.updateSelection(for: AppDestination.bestMatch(for: url, baseURL: baseURL), currentURL: url)
        updateNavigationButtons()
    }

    func refreshChrome() {
        let sidebarWidth = isCompactLayout ? compactSidebarWidth : regularSidebarWidth
        sidebarWidthConstraint?.constant = sidebarWidth

        if isCompactLayout {
            sidebarViewController.view.isHidden = false
            contentLeadingToSidebarConstraint?.isActive = false
            contentLeadingToViewConstraint?.isActive = true
            sidebarLeadingConstraint?.constant = isSidebarPresented ? 0 : -(sidebarWidth + 24)
            dimmingButton.isHidden = !isSidebarPresented
            dimmingButton.alpha = isSidebarPresented ? 1 : 0
            contentContainerView.layer.cornerRadius = 0
            contentContainerView.layer.shadowOpacity = 0
        } else {
            isSidebarPresented = false
            sidebarViewController.view.isHidden = true
            contentLeadingToViewConstraint?.isActive = false
            contentLeadingToSidebarConstraint?.isActive = false
            contentLeadingToViewConstraint?.isActive = true
            sidebarLeadingConstraint?.constant = -(sidebarWidth + 24)
            dimmingButton.isHidden = true
            dimmingButton.alpha = 0
            contentContainerView.layer.cornerRadius = 28
            contentContainerView.layer.cornerCurve = .continuous
            contentContainerView.layer.shadowColor = UIColor.black.cgColor
            contentContainerView.layer.shadowOpacity = 0.08
            contentContainerView.layer.shadowRadius = 28
            contentContainerView.layer.shadowOffset = CGSize(width: 0, height: 10)
        }

        updateNavigationButtons()
        view.layoutIfNeeded()
    }

    private var isCompactLayout: Bool {
        traitCollection.horizontalSizeClass == .compact
    }

    private func setupSidebar() {
        addChild(sidebarViewController)
        let sidebarView = sidebarViewController.view!
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.layer.cornerRadius = 30
        sidebarView.layer.cornerCurve = .continuous
        sidebarView.layer.masksToBounds = true

        dimmingButton.translatesAutoresizingMaskIntoConstraints = false
        dimmingButton.backgroundColor = UIColor.black.withAlphaComponent(0.14)
        dimmingButton.alpha = 0
        dimmingButton.isHidden = true
        dimmingButton.addTarget(self, action: #selector(didTapDimmingView), for: .touchUpInside)

        view.addSubview(dimmingButton)
        view.addSubview(sidebarView)

        sidebarLeadingConstraint = sidebarView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 0)
        sidebarWidthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: regularSidebarWidth)

        NSLayoutConstraint.activate([
            dimmingButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingButton.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarLeadingConstraint!,
            sidebarWidthConstraint!,
            sidebarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            sidebarView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        sidebarViewController.didMove(toParent: self)
    }

    private func setupContentContainer() {
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
        contentContainerView.clipsToBounds = true

        view.addSubview(contentContainerView)

        contentLeadingToViewConstraint = contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        contentLeadingToSidebarConstraint = contentContainerView.leadingAnchor.constraint(equalTo: sidebarViewController.view.trailingAnchor, constant: 12)

        NSLayoutConstraint.activate([
            contentLeadingToViewConstraint!,
            contentContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        addChild(navigator.rootViewController)
        let navigatorView = navigator.rootViewController.view!
        navigatorView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(navigatorView)
        NSLayoutConstraint.activate([
            navigatorView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            navigatorView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            navigatorView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            navigatorView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ])
        navigator.rootViewController.didMove(toParent: self)
    }

    private func setupLaunchOverlay() {
        launchOverlayView.translatesAutoresizingMaskIntoConstraints = false
        launchOverlayView.backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 28
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true

        let panelView = UIView()
        panelView.translatesAutoresizingMaskIntoConstraints = false

        launchSpinner.translatesAutoresizingMaskIntoConstraints = false
        launchSpinner.hidesWhenStopped = true
        launchSpinner.color = .darkGray

        launchTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        launchTitleLabel.font = .systemFont(ofSize: 24, weight: .black)
        launchTitleLabel.textColor = .label
        launchTitleLabel.textAlignment = .center
        launchTitleLabel.numberOfLines = 0

        launchMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        launchMessageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        launchMessageLabel.textColor = .secondaryLabel
        launchMessageLabel.textAlignment = .center
        launchMessageLabel.numberOfLines = 0

        launchActionsStackView.translatesAutoresizingMaskIntoConstraints = false
        launchActionsStackView.axis = .vertical
        launchActionsStackView.spacing = 12

        contentContainerView.addSubview(launchOverlayView)
        launchOverlayView.addSubview(blurView)
        blurView.contentView.addSubview(panelView)
        panelView.addSubview(launchSpinner)
        panelView.addSubview(launchTitleLabel)
        panelView.addSubview(launchMessageLabel)
        panelView.addSubview(launchActionsStackView)

        NSLayoutConstraint.activate([
            launchOverlayView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            launchOverlayView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            launchOverlayView.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            launchOverlayView.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
            blurView.centerXAnchor.constraint(equalTo: launchOverlayView.centerXAnchor),
            blurView.centerYAnchor.constraint(equalTo: launchOverlayView.centerYAnchor),
            blurView.leadingAnchor.constraint(greaterThanOrEqualTo: launchOverlayView.leadingAnchor, constant: 24),
            blurView.trailingAnchor.constraint(lessThanOrEqualTo: launchOverlayView.trailingAnchor, constant: -24),
            blurView.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            panelView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 24),
            panelView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -24),
            panelView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 24),
            panelView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -24),
            launchSpinner.centerXAnchor.constraint(equalTo: panelView.centerXAnchor),
            launchSpinner.topAnchor.constraint(equalTo: panelView.topAnchor),
            launchTitleLabel.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            launchTitleLabel.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            launchTitleLabel.topAnchor.constraint(equalTo: launchSpinner.bottomAnchor, constant: 18),
            launchMessageLabel.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            launchMessageLabel.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            launchMessageLabel.topAnchor.constraint(equalTo: launchTitleLabel.bottomAnchor, constant: 10),
            launchActionsStackView.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            launchActionsStackView.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            launchActionsStackView.topAnchor.constraint(equalTo: launchMessageLabel.bottomAnchor, constant: 20),
            launchActionsStackView.bottomAnchor.constraint(equalTo: panelView.bottomAnchor)
        ])

        updateLaunchOverlay(for: .connecting)
    }

    private func setupGestures() {
        let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        edgePan.edges = .left
        view.addGestureRecognizer(edgePan)
    }

    private func observeWebViewLoading() {
        let center = NotificationCenter.default
        webViewLoadObservers = [
            center.addObserver(forName: .uncleDocWebViewDidStartLoading, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    self.hasStartedInitialPageLoad = true
                    self.updateLaunchOverlay(for: .connecting)
                }
            },
            center.addObserver(forName: .uncleDocWebViewDidFinishLoading, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.hasStartedInitialPageLoad else {
                        return
                    }

                    self.updateLaunchOverlay(for: .connected)
                }
            }
        ]
    }

    private func updateNavigationButtons() {
        navigator.rootViewController.setNavigationBarHidden(true, animated: false)
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.clear]

        let navigationBar = navigator.rootViewController.navigationBar
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.isTranslucent = false
        navigator.rootViewController.navigationBar.prefersLargeTitles = false
        navigator.rootViewController.setNavigationBarHidden(true, animated: false)
    }

    private func updateLaunchOverlay(for state: LaunchState) {
        launchState = state
        launchActionsStackView.arrangedSubviews.forEach { view in
            launchActionsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch state {
        case .connecting:
            launchOverlayView.isHidden = false
            launchOverlayView.alpha = 1
            launchSpinner.startAnimating()
            launchTitleLabel.text = "Connecting to UncleDoc"
            launchMessageLabel.text = baseURL.host.map { "Opening \($0) and waiting for the first page..." } ?? baseURL.absoluteString
            launchActionsStackView.addArrangedSubview(makeLaunchActionButton(title: "Change Server", systemImageName: "server.rack") { [weak self] in
                self?.coordinator.resetServerURL()
            })
        case .connected:
            launchSpinner.stopAnimating()
            UIView.animate(withDuration: 0.2, animations: {
                self.launchOverlayView.alpha = 0
            }, completion: { _ in
                self.launchOverlayView.isHidden = true
                self.launchOverlayView.alpha = 1
            })
        case .failed(let message):
            launchOverlayView.isHidden = false
            launchOverlayView.alpha = 1
            launchSpinner.stopAnimating()
            launchTitleLabel.text = "Connection Problem"
            launchMessageLabel.text = message
            launchActionsStackView.addArrangedSubview(makeLaunchActionButton(title: "Reload", systemImageName: "arrow.clockwise") { [weak self] in
                self?.updateLaunchOverlay(for: .connecting)
                self?.reloadCurrentPage()
            })
            launchActionsStackView.addArrangedSubview(makeLaunchActionButton(title: "Change Server", systemImageName: "server.rack") { [weak self] in
                self?.coordinator.resetServerURL()
            })
        }
    }

    private func makeLaunchActionButton(title: String, systemImageName: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImageName)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 10
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = .black
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        button.configuration = configuration
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func setSidebarVisible(_ visible: Bool, animated: Bool) {
        isSidebarPresented = visible
        refreshChrome()

        guard animated else {
            return
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
            self.dimmingButton.alpha = visible ? 1 : 0
        }
    }

    private func presentServerActions() {
        let alertController = UIAlertController(title: "UncleDoc Server", message: baseURL.absoluteString, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: "Change Server", style: .destructive) { [weak self] _ in
            self?.coordinator.resetServerURL()
        })
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alertController.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
        }

        present(alertController, animated: true)
    }

    @objc private func didTapSidebarButton() {
        setSidebarVisible(!isSidebarPresented, animated: true)
    }

    @objc private func didTapDimmingView() {
        setSidebarVisible(false, animated: true)
    }

    @objc private func handleEdgePan(_ gestureRecognizer: UIScreenEdgePanGestureRecognizer) {
        guard isCompactLayout else {
            return
        }

        if gestureRecognizer.state == .recognized {
            setSidebarVisible(true, animated: true)
        }
    }
}

@MainActor
private final class AppSettingsViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let onReload: () -> Void
    private let onOpenInSafari: () -> Void
    private let onChangeServer: () -> Void
    private let onShowHealthRecords: () -> Void

    init(
        onReload: @escaping () -> Void,
        onOpenInSafari: @escaping () -> Void,
        onChangeServer: @escaping () -> Void,
        onShowHealthRecords: @escaping () -> Void
    ) {
        self.onReload = onReload
        self.onOpenInSafari = onOpenInSafari
        self.onChangeServer = onChangeServer
        self.onShowHealthRecords = onShowHealthRecords
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "App Settings"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissSheet))

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 14

        let introLabel = UILabel()
        introLabel.translatesAutoresizingMaskIntoConstraints = false
        introLabel.numberOfLines = 0
        introLabel.font = .systemFont(ofSize: 16, weight: .medium)
        introLabel.textColor = .secondaryLabel
        introLabel.text = "Device-only actions for the UncleDoc iOS app."

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(introLabel)
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            introLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            introLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            introLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: introLabel.bottomAnchor, constant: 20),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])

        stackView.addArrangedSubview(makeActionButton(title: "Reload", subtitle: "Reload the current UncleDoc page.", systemImageName: "arrow.clockwise") { [weak self] in
            self?.dismiss(animated: true) {
                self?.onReload()
            }
        })
        stackView.addArrangedSubview(makeActionButton(title: "Open in Safari", subtitle: "Open the current page in Safari.", systemImageName: "safari") { [weak self] in
            self?.dismiss(animated: true) {
                self?.onOpenInSafari()
            }
        })
        stackView.addArrangedSubview(makeActionButton(title: "Change Server", subtitle: "Reconfigure the UncleDoc server URL.", systemImageName: "server.rack") { [weak self] in
            self?.dismiss(animated: true) {
                self?.onChangeServer()
            }
        })
    }

    private func makeActionButton(title: String, subtitle: String, systemImageName: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.subtitle = subtitle
        configuration.image = UIImage(systemName: systemImageName)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 14
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = .secondarySystemGroupedBackground
        configuration.background.cornerRadius = 20
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    @objc private func dismissSheet() {
        dismiss(animated: true)
    }
}

@MainActor
private final class HealthSyncViewController: UIViewController {
    private let syncService: HealthKitSyncService
    private var cancellables: Set<AnyCancellable> = []

    private let stackView = UIStackView()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let personLabel = UILabel()
    private let countLabel = UILabel()
    private let progressLabel = UILabel()
    private let sampleTypeLabel = UILabel()
    private let choosePersonButton = UIButton(type: .system)
    private let grantAccessButton = UIButton(type: .system)
    private let syncNowButton = UIButton(type: .system)
    private let resetSyncButton = UIButton(type: .system)
    private let debugButton = UIButton(type: .system)

    init(syncService: HealthKitSyncService) {
        self.syncService = syncService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Health Sync"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissSheet))

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 16

        [statusLabel, detailLabel, personLabel, countLabel, progressLabel, sampleTypeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.numberOfLines = 0
        }

        statusLabel.font = .systemFont(ofSize: 28, weight: .black)
        detailLabel.font = .systemFont(ofSize: 16, weight: .medium)
        detailLabel.textColor = .secondaryLabel
        personLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        progressLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        sampleTypeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        sampleTypeLabel.textColor = .secondaryLabel

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18)
        ])

        let introCard = makeCard()
        introCard.addArrangedSubview(statusLabel)
        introCard.addArrangedSubview(detailLabel)
        introCard.addArrangedSubview(personLabel)
        introCard.addArrangedSubview(countLabel)
        introCard.addArrangedSubview(progressLabel)
        introCard.addArrangedSubview(sampleTypeLabel)
        stackView.addArrangedSubview(introCard)

        stackView.addArrangedSubview(makeActionButton(button: choosePersonButton, title: "Choose Person", subtitle: "One device maps to one UncleDoc person.", systemImageName: "person.crop.circle.badge.checkmark", action: #selector(didTapChoosePerson)))
        stackView.addArrangedSubview(makeActionButton(button: grantAccessButton, title: "Grant Health Access", subtitle: "Authorize the stable HealthKit types UncleDoc can sync.", systemImageName: "heart") )
        grantAccessButton.addTarget(self, action: #selector(didTapGrantAccess), for: .touchUpInside)
        stackView.addArrangedSubview(makeActionButton(button: syncNowButton, title: "Sync Now", subtitle: "Run or resume the HealthKit sync immediately.", systemImageName: "arrow.triangle.2.circlepath") )
        syncNowButton.addTarget(self, action: #selector(didTapSyncNow), for: .touchUpInside)
        stackView.addArrangedSubview(makeActionButton(button: resetSyncButton, title: "Reset Sync", subtitle: "Clear local sync progress and force a full HealthKit resync.", systemImageName: "exclamationmark.arrow.triangle.2.circlepath") )
        resetSyncButton.addTarget(self, action: #selector(didTapResetSync), for: .touchUpInside)
        var debugConfiguration = UIButton.Configuration.plain()
        debugConfiguration.title = "Debug sync scope"
        debugConfiguration.image = UIImage(systemName: "ladybug")
        debugConfiguration.imagePlacement = .leading
        debugConfiguration.imagePadding = 8
        debugButton.configuration = debugConfiguration
        debugButton.contentHorizontalAlignment = .leading
        debugButton.addTarget(self, action: #selector(didTapDebug), for: .touchUpInside)
        stackView.addArrangedSubview(debugButton)

        bind()
        syncService.bootstrap()
    }

    private func bind() {
        syncService.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.render(snapshot: snapshot)
            }
            .store(in: &cancellables)
    }

    private func render(snapshot: HealthKitSyncSnapshot) {
        statusLabel.text = snapshot.statusText
        detailLabel.text = snapshot.detailText
        personLabel.text = snapshot.selectedPersonName.map { "Person: \($0)" } ?? "Person: not selected"
        countLabel.text = "Synced: \(snapshot.syncedCountText)"
        progressLabel.isHidden = true
        sampleTypeLabel.text = snapshot.currentSampleTypeIdentifier.map { "Current type: \($0)" } ?? ""
        syncNowButton.isEnabled = snapshot.selectedPersonUUID != nil

        applyState(to: choosePersonButton, title: "Choose Person", subtitle: snapshot.selectedPersonName.map { "Done: \($0)" } ?? "One device maps to one UncleDoc person.", systemImageName: snapshot.personSelected ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark", complete: snapshot.personSelected)
        applyState(to: grantAccessButton, title: "Grant Health Access", subtitle: snapshot.accessReady ? "Done: HealthKit access is ready." : "Authorize the stable HealthKit types UncleDoc can sync.", systemImageName: snapshot.accessReady ? "checkmark.circle.fill" : "heart", complete: snapshot.accessReady)
        applyState(to: syncNowButton, title: "Sync Now", subtitle: snapshot.syncCompleted ? "Done: synced at \((snapshot.lastSuccessfulSyncAt ?? Date()).formatted())" : "Run or resume the HealthKit sync immediately.", systemImageName: snapshot.syncCompleted ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath", complete: snapshot.syncCompleted)
    }

    private func makeCard() -> UIStackView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 12
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        return card
    }

    private func makeActionButton(button: UIButton, title: String, subtitle: String, systemImageName: String, action: Selector? = nil) -> UIButton {
        applyState(to: button, title: title, subtitle: subtitle, systemImageName: systemImageName, complete: false)
        button.contentHorizontalAlignment = .leading
        if let action {
            button.addTarget(self, action: action, for: .touchUpInside)
        }
        return button
    }

    private func applyState(to button: UIButton, title: String, subtitle: String, systemImageName: String, complete: Bool) {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.subtitle = subtitle
        configuration.image = UIImage(systemName: systemImageName)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 14
        configuration.baseForegroundColor = complete ? .systemGreen : .label
        configuration.background.backgroundColor = .secondarySystemGroupedBackground
        configuration.background.cornerRadius = 20
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        button.configuration = configuration
    }

    @objc private func didTapChoosePerson() {
        Task {
            await syncService.loadAvailablePeopleIfNeeded()

            guard !syncService.availablePeople.isEmpty else {
                let alertController = UIAlertController(
                    title: "No People Available",
                    message: syncService.lastPeopleLoadError ?? "UncleDoc could not load any people from the server yet. Check the server connection and make sure at least one person exists.",
                    preferredStyle: .alert
                )
                alertController.addAction(UIAlertAction(title: "OK", style: .default))
                present(alertController, animated: true)
                return
            }

            let alertController = UIAlertController(title: "Choose Person", message: nil, preferredStyle: .actionSheet)
            for person in syncService.availablePeople {
                alertController.addAction(UIAlertAction(title: person.name, style: .default) { _ in
                    Task { await self.syncService.selectPerson(person) }
                })
            }
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))

            if let popover = alertController.popoverPresentationController {
                popover.sourceView = choosePersonButton
                popover.sourceRect = choosePersonButton.bounds
            }

            present(alertController, animated: true)
        }
    }

    @objc private func didTapGrantAccess() {
        Task { await syncService.grantAccessAndStartIfPossible() }
    }

    @objc private func didTapSyncNow() {
        Task { await syncService.syncNow() }
    }

    @objc private func didTapResetSync() {
        let alertController = UIAlertController(
            title: "Reset Health Sync?",
            message: "This clears the app's local HealthKit sync progress and forces a fresh full sync on the next run.",
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alertController.addAction(UIAlertAction(title: "Reset", style: .destructive) { _ in
            Task { await self.syncService.resetSync() }
        })
        present(alertController, animated: true)
    }

    @objc private func didTapDebug() {
        let debugViewController = HealthSyncDebugViewController(syncService: syncService)
        navigationController?.pushViewController(debugViewController, animated: true)
    }

    @objc private func dismissSheet() {
        dismiss(animated: true)
    }
}

@MainActor
private final class HealthSyncDebugViewController: UIViewController {
    private let syncService: HealthKitSyncService
    private let textView = UITextView()
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(syncService: HealthKitSyncService) {
        self.syncService = syncService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sync Debug"
        view.backgroundColor = .systemBackground

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isEditable = false
        textView.text = "Loading sync scope..."

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        view.addSubview(textView)
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            spinner.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])

        Task {
            do {
                let counts = try await syncService.loadDebugTypeCounts()
                let body = counts.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
                textView.text = body
            } catch {
                textView.text = error.localizedDescription
            }
            spinner.stopAnimating()
        }
    }
}

@MainActor
private final class HealthRecordsViewController: UIViewController, UITableViewDataSource {
    private let healthKitManager = HealthKitManager.shared
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let actionButton = UIButton(type: .system)
    private var records: [HealthRecordPreview] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Health Records"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissSheet))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Export XML", style: .plain, target: self, action: #selector(didTapExport))
        navigationItem.leftBarButtonItem?.isEnabled = false

        setupViews()
        loadRecords()
    }

    private func setupViews() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HealthRecordCell")
        tableView.isHidden = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textColor = .secondaryLabel

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        applyActionButtonConfiguration(title: "Allow Health Access")
        actionButton.isHidden = true
        actionButton.addTarget(self, action: #selector(didTapActionButton), for: .touchUpInside)

        view.addSubview(tableView)
        view.addSubview(statusLabel)
        view.addSubview(spinner)
        view.addSubview(actionButton)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 18),
            actionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20)
        ])
    }

    private func loadRecords() {
        setLoadingState(message: "Requesting Health access and loading recent records...")

        Task {
            do {
                try await healthKitManager.requestAuthorization()
                let records = try await healthKitManager.loadRecentRecords(limit: 20, maxPerType: 3)
                await MainActor.run {
                    self.records = records
                    self.renderLoadedState()
                }
            } catch {
                await MainActor.run {
                    self.renderErrorState(message: error.localizedDescription)
                }
            }
        }
    }

    private func setLoadingState(message: String) {
        tableView.isHidden = true
        actionButton.isHidden = true
        spinner.startAnimating()
        statusLabel.text = message
    }

    private func renderLoadedState() {
        spinner.stopAnimating()

        if records.isEmpty {
            tableView.isHidden = true
            actionButton.isHidden = false
            applyActionButtonConfiguration(title: "Reload")
            statusLabel.text = "No recent Health records were returned."
            return
        }

        statusLabel.text = nil
        actionButton.isHidden = true
        tableView.isHidden = false
        navigationItem.leftBarButtonItem?.isEnabled = !records.isEmpty
        tableView.reloadData()
    }

    private func renderErrorState(message: String) {
        tableView.isHidden = true
        spinner.stopAnimating()
        actionButton.isHidden = false
        applyActionButtonConfiguration(title: "Try Again")
        statusLabel.text = message
        navigationItem.leftBarButtonItem?.isEnabled = false
    }

    private func applyActionButtonConfiguration(title: String) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        actionButton.configuration = configuration
    }

    @objc private func didTapActionButton() {
        loadRecords()
    }

    @objc private func dismissSheet() {
        dismiss(animated: true)
    }

    @objc private func didTapExport() {
        setLoadingState(message: "Preparing 1-year XML export...")
        navigationItem.leftBarButtonItem?.isEnabled = false

        Task {
            do {
                let startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
                let exportRecords = try await healthKitManager.loadExportRecords(totalLimit: 100, since: startDate)
                let xml = HealthRecordXMLExporter.exportXML(records: exportRecords, limit: 100)
                let formatter = ISO8601DateFormatter()
                let filename = "uncledoc-health-export-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")).xml"
                let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try xml.write(to: temporaryURL, atomically: true, encoding: .utf8)

                await MainActor.run {
                    self.records = exportRecords
                    self.renderLoadedState()

                    let activityViewController = UIActivityViewController(activityItems: [temporaryURL], applicationActivities: nil)
                    if let popover = activityViewController.popoverPresentationController {
                        popover.barButtonItem = self.navigationItem.leftBarButtonItem
                    }
                    self.present(activityViewController, animated: true)
                }
            } catch {
                await MainActor.run {
                    self.renderErrorState(message: error.localizedDescription)
                    let alertController = UIAlertController(title: "Export Failed", message: error.localizedDescription, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alertController, animated: true)
                }
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HealthRecordCell", for: indexPath)
        let record = records[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = record.title
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let when = formatter.localizedString(for: record.startDate, relativeTo: Date())
        content.secondaryText = "\(when)\n\n\(record.rawText)"
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }
}

extension UncleDocShellViewController: NavigatorDelegate {
    nonisolated func didReceiveAuthenticationChallenge(_ challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let responder = AuthenticationChallengeResponder(completionHandler)

        if TrustedCertificateStore.contains(challenge.protectionSpace) {
            responder.complete(.useCredential, credential: URLCredential(trust: serverTrust))
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                responder.complete(.cancelAuthenticationChallenge, credential: nil)
                return
            }

            let host = challenge.protectionSpace.host
            let message = "This UncleDoc server is using a certificate that iOS does not currently trust. If this is your own LAN or self-hosted server, you can trust it and continue."
            let alertController = UIAlertController(
                title: "Trust This Certificate?",
                message: "\(host)\n\n\(message)",
                preferredStyle: .alert
            )

            alertController.addAction(UIAlertAction(title: "Trust and Continue", style: .default) { _ in
                TrustedCertificateStore.trust(challenge.protectionSpace)
                responder.complete(.useCredential, credential: URLCredential(trust: serverTrust))
            })
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                responder.complete(.cancelAuthenticationChallenge, credential: nil)
            })

            self.present(alertController, animated: true)
        }
    }

    nonisolated func requestDidFinish(at url: URL) {
        Task { @MainActor [weak self] in
            self?.coordinator.handleFinishedRequest(at: url)
        }
    }

    nonisolated func visitableDidFailRequest(_ visitable: Visitable, error: any Error, retryHandler: RetryBlock?) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.updateLaunchOverlay(for: .failed(error.localizedDescription))

            if self.isCompactLayout {
                self.setSidebarVisible(true, animated: true)
            }

            let alertController = UIAlertController(
                title: "Connection Problem",
                message: error.localizedDescription,
                preferredStyle: .alert
            )

            alertController.addAction(UIAlertAction(title: "Reload", style: .default) { [weak self] _ in
                self?.reloadCurrentPage()
            })

            alertController.addAction(UIAlertAction(title: "Change Server", style: .destructive) { [weak self] _ in
                self?.coordinator.resetServerURL()
            })
            alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            self.present(alertController, animated: true)
        }
    }
}

@MainActor
private final class SidebarViewController: UIViewController {
    private let stackView = UIStackView()
    private let footerStackView = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var routeButtons: [AppDestination: UIButton] = [:]
    private var onDestinationSelected: ((AppDestination) -> Void)?
    private var onOpenInSafari: (() -> Void)?
    private var onReload: (() -> Void)?
    private var onChangeServer: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .vertical
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        footerStackView.axis = .vertical
        footerStackView.spacing = 10
        footerStackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 30, weight: .black)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2

        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.numberOfLines = 0

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(stackView)
        contentView.addSubview(footerStackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            footerStackView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            footerStackView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            footerStackView.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 24),
            footerStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])

        AppDestination.allCases.forEach { destination in
            let button = makeRouteButton(for: destination)
            routeButtons[destination] = button
            stackView.addArrangedSubview(button)
        }

        footerStackView.addArrangedSubview(makeSecondaryButton(title: "Reload", systemImageName: "arrow.clockwise") { [weak self] in
            self?.onReload?()
        })
        footerStackView.addArrangedSubview(makeSecondaryButton(title: "Open in Safari", systemImageName: "safari") { [weak self] in
            self?.onOpenInSafari?()
        })
        footerStackView.addArrangedSubview(makeSecondaryButton(title: "Change Server", systemImageName: "server.rack") { [weak self] in
            self?.onChangeServer?()
        })
    }

    func configure(
        serverURL: URL,
        currentURL: URL?,
        onDestinationSelected: @escaping (AppDestination) -> Void,
        onOpenInSafari: @escaping () -> Void,
        onReload: @escaping () -> Void,
        onChangeServer: @escaping () -> Void
    ) {
        self.onDestinationSelected = onDestinationSelected
        self.onOpenInSafari = onOpenInSafari
        self.onReload = onReload
        self.onChangeServer = onChangeServer

        titleLabel.text = "UncleDoc"
        subtitleLabel.text = serverURL.host.map { "Connected to \($0)" } ?? serverURL.absoluteString

        updateSelection(for: currentURL.map { AppDestination.bestMatch(for: $0, baseURL: serverURL) } ?? .home, currentURL: currentURL)
    }

    func updateSelection(for destination: AppDestination, currentURL: URL?) {
        routeButtons.forEach { route, button in
            button.configuration = routeButtonConfiguration(for: route, selected: route == destination)
        }

        if let currentURL {
            subtitleLabel.text = currentURL.absoluteString
        }
    }

    private func makeRouteButton(for destination: AppDestination) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = routeButtonConfiguration(for: destination, selected: destination == .home)
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { [weak self] _ in
            self?.onDestinationSelected?(destination)
        }, for: .touchUpInside)
        return button
    }

    private func routeButtonConfiguration(for destination: AppDestination, selected: Bool) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.title = destination.title
        configuration.subtitle = destination.subtitle
        configuration.image = UIImage(systemName: destination.systemImageName)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 12
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        configuration.baseForegroundColor = selected ? .white : UIColor.white.withAlphaComponent(0.86)
        configuration.background.backgroundColor = selected ? UIColor.white.withAlphaComponent(0.14) : UIColor.white.withAlphaComponent(0.04)
        configuration.background.cornerRadius = 20
        return configuration
    }

    private func makeSecondaryButton(title: String, systemImageName: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImageName)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        configuration.baseForegroundColor = .white
        configuration.background.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        configuration.background.cornerRadius = 18
        button.configuration = configuration
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}
