import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let url = connectionOptions.urlContexts.first?.url {
      (UIApplication.shared.delegate as? AppDelegate)?
        .captureMusicXML(url, notifyFlutter: false)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url,
       (UIApplication.shared.delegate as? AppDelegate)?
        .captureMusicXML(url, notifyFlutter: true) == true {
      return
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
