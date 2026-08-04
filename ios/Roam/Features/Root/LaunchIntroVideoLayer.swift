import AVFoundation
import SwiftUI

/// The opening beat of the launch intro: a pre-rendered globe-and-route clip,
/// one per theme, that hands off into `LaunchIntroView`'s native road-trace
/// and wordmark reveal. Rendered offline (see `tools/intro-render`) because
/// the faceted-globe camera move is cheaper to author once in three.js than
/// to hand-animate six times in SwiftUI.
struct LaunchIntroVideoLayer: View {
    let themeID: ThemeID
    let onFinished: () -> Void

    var body: some View {
        if let url = Self.videoURL(for: themeID) {
            PlayerLayerView(url: url, onFinished: onFinished)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    static func videoURL(for themeID: ThemeID) -> URL? {
        Bundle.main.url(forResource: "intro-\(themeID.rawValue)", withExtension: "mp4")
    }
}

/// Thin UIKit bridge: SwiftUI's `VideoPlayer` shows tap-to-reveal transport
/// controls, which a four-second brand moment should never expose.
private struct PlayerLayerView: UIViewRepresentable {
    let url: URL
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        context.coordinator.observe(item)
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.stopObserving()
        uiView.playerLayer.player?.pause()
    }

    final class Coordinator {
        private let onFinished: () -> Void
        private var observedItem: AVPlayerItem?

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        func observe(_ item: AVPlayerItem) {
            observedItem = item
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didFinish),
                name: AVPlayerItem.didPlayToEndTimeNotification,
                object: item
            )
        }

        func stopObserving() {
            guard let observedItem else { return }
            NotificationCenter.default.removeObserver(
                self,
                name: AVPlayerItem.didPlayToEndTimeNotification,
                object: observedItem
            )
        }

        @objc private func didFinish() {
            DispatchQueue.main.async { [onFinished] in onFinished() }
        }
    }
}

private final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }
}
