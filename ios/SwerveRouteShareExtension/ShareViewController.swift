import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = ShareRouteImportViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let controller = UIHostingController(
            rootView: RouteShareImportView(
                model: model,
                finish: { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            )
        )
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)

        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        Task { [model] in
            let sharedItem = await SharedRouteShareItemReader.read(from: attachments)
            model.importRoute(from: sharedItem)
        }
    }
}

@MainActor
private final class ShareRouteImportViewModel: ObservableObject {
    enum State {
        case loading
        case saved(SharedRouteDraft?)
        case savedGoogleShortLink
        case unsupported(String)
    }

    @Published private(set) var state: State = .loading
    private let inbox = SharedRouteInbox()

    func importRoute(from sharedItem: SharedRouteShareItem?) {
        guard let sharedItem else {
            state = .unsupported("Share a route link from Apple Maps or Google Maps to add it to Swerve.")
            return
        }

        switch SharedRouteImportParser.parse(url: sharedItem.url, text: sharedItem.text) {
        case let .ready(candidate):
            let route = SharedRouteDraft(
                id: UUID(),
                provider: candidate.provider,
                origin: candidate.origin,
                destination: candidate.destination,
                importedAt: Date(),
                waypointCount: candidate.waypointCount
            )
            guard inbox.enqueue(route: route) else {
                state = .unsupported("Swerve could not save this route. Make sure the app's shared storage capability is enabled.")
                return
            }
            state = .saved(route)

        case let .needsGoogleShortLinkResolution(url):
            guard inbox.enqueueGoogleShortLink(url) else {
                state = .unsupported("Swerve could not save this Google Maps link.")
                return
            }
            state = .savedGoogleShortLink

        case let .unsupportedTravelMode(mode):
            state = .unsupported("This link is for \(mode.displayName). Swerve can only analyze driving routes.")

        case let .unsupported(message):
            state = .unsupported(message)
        }
    }
}

private struct RouteShareImportView: View {
    @ObservedObject var model: ShareRouteImportViewModel
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .loading:
                    loadingContent
                case let .saved(route):
                    savedContent(route: route)
                case .savedGoogleShortLink:
                    savedGoogleShortLinkContent
                case let .unsupported(message):
                    unsupportedContent(message: message)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: finish)
                }
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.35, dampingFraction: 1), value: stateIdentity)
    }

    private var stateIdentity: String {
        switch model.state {
        case .loading: "loading"
        case .saved: "saved"
        case .savedGoogleShortLink: "short-link"
        case .unsupported: "unsupported"
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.accentColor)
            Text("Reading your map route")
                .font(.headline)
            Text("Swerve is preparing the route for you to review.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading your map route")
    }

    private func savedContent(route: SharedRouteDraft?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            statusHeader(
                title: "Route saved for Swerve",
                detail: "Open Swerve to review the route, choose a departure time, and analyze it.",
                symbol: "checkmark.circle.fill",
                color: .green
            )

            if let route {
                VStack(alignment: .leading, spacing: 12) {
                    routeRow(title: "From", value: route.origin ?? "Current location")
                    Divider()
                    routeRow(title: "To", value: route.destination)
                    if route.waypointCount > 0 {
                        Divider()
                        Text("Swerve will ask you to review the start and final destination. This route has \(route.waypointCount) additional stop\(route.waypointCount == 1 ? "" : "s").")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button(action: finish) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Closes this share sheet. Open Swerve to review the imported route.")
        }
    }

    private var savedGoogleShortLinkContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusHeader(
                title: "Google Maps link saved",
                detail: "Open Swerve to finish preparing the route, then review and analyze it.",
                symbol: "link.circle.fill",
                color: .accentColor
            )

            Text("Swerve only follows the shared Google Maps link after you return to the app. It will not start a route analysis by itself.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button(action: finish) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func unsupportedContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            statusHeader(
                title: "Route not added",
                detail: message,
                symbol: "exclamationmark.triangle.fill",
                color: .orange
            )

            Text("Share a driving route from Apple Maps or Google Maps. Swerve will fill in the route for you to review before analysis.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button(action: finish) {
                Text("Close")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
        }
    }

    private func statusHeader(
        title: String,
        detail: String,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 46, height: 46)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func routeRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SharedRouteShareItem {
    let url: URL?
    let text: String?
}

private enum SharedRouteShareItemReader {
    static func read(from attachments: [NSItemProvider]) async -> SharedRouteShareItem? {
        for provider in attachments {
            if let url = await loadURL(from: provider) {
                return SharedRouteShareItem(url: url, text: nil)
            }
        }

        for provider in attachments {
            if let text = await loadText(from: provider) {
                return SharedRouteShareItem(url: nil, text: text)
            }
        }

        return nil
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                } else if let string = item as? String {
                    continuation.resume(returning: URL(string: string))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let string = item as? NSString {
                    continuation.resume(returning: string as String)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private extension SharedRouteTravelMode {
    var displayName: String {
        switch self {
        case .driving:
            "driving"
        case .walking:
            "walking"
        case .transit:
            "transit"
        case .bicycling:
            "bicycling"
        case .unknown:
            "an unsupported mode"
        }
    }
}
