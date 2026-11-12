import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let localNetwork = LocalNetworkPermission()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Canal « réseau local » : demande l'autorisation dès l'ouverture de l'app.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PegasusLocalNetwork") else { return }
    let channel = FlutterMethodChannel(name: "pegasus/local_network", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "request":
        guard let self = self else {
          result(true)
          return
        }
        self.localNetwork.request { granted in result(granted) }
      case "openSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Déclenche et lit l'autorisation « réseau local » (iOS 14+).
///
/// iOS n'offre pas d'API dédiée : on publie un service Bonjour et on le
/// cherche. S'il est trouvé, l'accès est accordé ; si la recherche est
/// bloquée (PolicyDenied), il est refusé. Tant que l'utilisateur n'a pas
/// répondu, la demande reste en attente.
final class LocalNetworkPermission {
  private static let serviceType = "_pegasus._tcp"
  private var browser: NWBrowser?
  private var listener: NWListener?
  private var callbacks: [(Bool) -> Void] = []

  func request(_ completion: @escaping (Bool) -> Void) {
    callbacks.append(completion)
    if browser != nil { return }

    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = true
    let serviceName = "pegasus-\(UUID().uuidString.prefix(8))"

    do {
      let listener = try NWListener(using: parameters)
      listener.service = NWListener.Service(name: serviceName, type: LocalNetworkPermission.serviceType)
      listener.newConnectionHandler = { connection in connection.cancel() }
      listener.stateUpdateHandler = { _ in }
      self.listener = listener
      listener.start(queue: .main)
    } catch {
      // Impossible de publier : on ne bloque pas l'utilisateur.
      finish(true)
      return
    }

    let browser = NWBrowser(
      for: .bonjour(type: LocalNetworkPermission.serviceType, domain: nil),
      using: parameters
    )
    browser.stateUpdateHandler = { [weak self] state in
      switch state {
      case .waiting(let error):
        if case .dns(let code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
          self?.finish(false)
        }
      case .failed:
        self?.finish(true)
      default:
        break
      }
    }
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      let found = results.contains { result in
        if case .service(let name, _, _, _) = result.endpoint {
          return name == serviceName
        }
        return false
      }
      if found { self?.finish(true) }
    }
    self.browser = browser
    browser.start(queue: .main)
  }

  private func finish(_ granted: Bool) {
    browser?.cancel()
    browser = nil
    listener?.cancel()
    listener = nil
    let pending = callbacks
    callbacks = []
    pending.forEach { $0(granted) }
  }
}
