#if canImport(UIKit)
import SwiftUI
import UIKit

// §5.3: Air's leftover UIKit screens read the same tokens through scoped UIAppearance.

/// Every Air view controller is presented inside this, so appearance proxies don't leak into the game or system pickers.
public final class CofreAirHostController: UINavigationController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .cofre.page
        view.tintColor = .cofre.accent
    }
}

@MainActor
public enum CofreUIKitTheme {
    /// Call once at launch, before the first Air presentation (appearance only affects views created afterward).
    /// Calling again re-applies after an X07 accent or theme change.
    public static func apply(_ t: CofreTheme = .current) {
        CofreFonts.register()
        let scope = [CofreAirHostController.self]
        let c = UIColor.cofre

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = c.side
        bar.shadowColor = c.outline
        bar.titleTextAttributes = [.font: UIFont.cofre(.headerCompact), .foregroundColor: c.ink]
        bar.largeTitleTextAttributes = [.font: UIFont.cofre(.title), .foregroundColor: c.ink]
        let item = UIBarButtonItemAppearance()
        item.normal.titleTextAttributes = [.font: UIFont.cofre(.button), .foregroundColor: c.accent]
        bar.buttonAppearance = item; bar.doneButtonAppearance = item; bar.backButtonAppearance = item
        let nb = UINavigationBar.appearance(whenContainedInInstancesOf: scope)
        nb.standardAppearance = bar; nb.scrollEdgeAppearance = bar; nb.compactAppearance = bar; nb.compactScrollEdgeAppearance = bar
        nb.tintColor = c.accent

        let tb = UIToolbarAppearance(); tb.configureWithOpaqueBackground(); tb.backgroundColor = c.side; tb.shadowColor = c.outline
        let tbar = UIToolbar.appearance(whenContainedInInstancesOf: scope)
        tbar.standardAppearance = tb; tbar.compactAppearance = tb; tbar.scrollEdgeAppearance = tb; tbar.tintColor = c.accent

        UITableView.appearance(whenContainedInInstancesOf: scope).backgroundColor = c.page
        UITableView.appearance(whenContainedInInstancesOf: scope).separatorColor = c.outline
        UITableViewCell.appearance(whenContainedInInstancesOf: scope).backgroundColor = c.panel
        UICollectionView.appearance(whenContainedInInstancesOf: scope).backgroundColor = c.page
        UILabel.appearance(whenContainedInInstancesOf: scope).textColor = c.ink
        UISwitch.appearance(whenContainedInInstancesOf: scope).onTintColor = c.face
        UISwitch.appearance(whenContainedInInstancesOf: scope).thumbTintColor = c.inkSoft
        UISlider.appearance(whenContainedInInstancesOf: scope).minimumTrackTintColor = c.face
        UISlider.appearance(whenContainedInInstancesOf: scope).maximumTrackTintColor = c.well
        UIProgressView.appearance(whenContainedInInstancesOf: scope).progressTintColor = c.success
        UIProgressView.appearance(whenContainedInInstancesOf: scope).trackTintColor = c.well
        UITextField.appearance(whenContainedInInstancesOf: scope).tintColor = c.accent
        UITextField.appearance(whenContainedInInstancesOf: scope).backgroundColor = c.well

        let seg = UISegmentedControl.appearance(whenContainedInInstancesOf: scope)
        seg.selectedSegmentTintColor = c.face
        seg.backgroundColor = c.well
        seg.setTitleTextAttributes([.font: UIFont.cofre(.buttonS), .foregroundColor: c.muted], for: .normal)
        seg.setTitleTextAttributes([.font: UIFont.cofre(.buttonS), .foregroundColor: c.onFace], for: .selected)

        let button = UIButton.appearance(whenContainedInInstancesOf: scope)
        button.tintColor = c.accent
    }

    /// §5.3 #4: the window's style drives both stacks.
    public static func applyInterfaceStyle(_ t: CofreTheme, to window: UIWindow?) {
        window?.overrideUserInterfaceStyle = t.interfaceStyle
        window?.tintColor = .cofre.accent
    }
}

/// Hosts an Air view controller inside `CofreAirHostController` from SwiftUI.
struct AirScreenHost: UIViewControllerRepresentable {
    let make: () -> UIViewController
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> CofreAirHostController {
        let root = make()
        root.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in onClose() })
        return CofreAirHostController(rootViewController: root)
    }
    func updateUIViewController(_ vc: CofreAirHostController, context: Context) {}
}
#endif
