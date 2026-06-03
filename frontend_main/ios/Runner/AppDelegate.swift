import Flutter
import UIKit
import GoogleMaps
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    GMSServices.provideAPIKey("AIzaSyAPQ52x6PflP4_2wdFppmQCu6U5tQ6_0Pg")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
