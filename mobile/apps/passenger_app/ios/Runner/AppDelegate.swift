import Flutter
import SafariServices
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let settingsChannelName = "io.alanteh.passenger/settings"
  private let rideUpdatesKey = "ride_updates"
  private let soundAlertsKey = "sound_alerts"
  private let legalUrls: Set<String> = [
    "https://alanteh.io/privacy",
    "https://alanteh.io/terms",
  ]
  private var settingsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: settingsChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    settingsChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "settings_unavailable",
            message: "Passenger settings are unavailable.",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "readPreference":
        guard
          let arguments = call.arguments as? [String: Any],
          let key = arguments["key"] as? String,
          key == self.rideUpdatesKey || key == self.soundAlertsKey
        else {
          result(
            FlutterError(
              code: "invalid_preference",
              message: "Preference key is required.",
              details: nil
            )
          )
          return
        }

        if UserDefaults.standard.object(forKey: key) == nil {
          result(true)
        } else {
          result(UserDefaults.standard.bool(forKey: key))
        }

      case "writePreference":
        guard
          let arguments = call.arguments as? [String: Any],
          let key = arguments["key"] as? String,
          let value = arguments["value"] as? Bool,
          key == self.rideUpdatesKey || key == self.soundAlertsKey
        else {
          result(
            FlutterError(
              code: "invalid_preference",
              message: "Preference key and value are required.",
              details: nil
            )
          )
          return
        }

        UserDefaults.standard.set(value, forKey: key)
        result(nil)

      case "openInAppBrowser":
        guard
          let arguments = call.arguments as? [String: Any],
          let value = arguments["url"] as? String,
          self.legalUrls.contains(value),
          let url = URL(string: value)
        else {
          result(
            FlutterError(
              code: "invalid_url",
              message: "Unsupported legal URL.",
              details: nil
            )
          )
          return
        }

        DispatchQueue.main.async {
          guard let presenter = self.topViewController() else {
            result(
              FlutterError(
                code: "browser_unavailable",
                message: "Unable to open the legal page.",
                details: nil
              )
            )
            return
          }

          let controller = SFSafariViewController(url: url)
          presenter.present(controller, animated: true) {
            result(nil)
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController

    return topViewController(from: root)
  }

  private func topViewController(from controller: UIViewController?) -> UIViewController? {
    if let presented = controller?.presentedViewController {
      return topViewController(from: presented)
    }

    if let navigation = controller as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }

    if let tabs = controller as? UITabBarController {
      return topViewController(from: tabs.selectedViewController)
    }

    return controller
  }
}
