import DevsAppSDK
import SwiftUI

/// Where an async load has got to. Views switch over it exhaustively rather
/// than juggling `isLoading` / `value` / `error` triples that can contradict
/// each other.
public enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(DevsAppError)

    public var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// How the list opens an app's detail.
public enum DetailPresentation: Sendable {
    /// Slides up as a bottom sheet over the list. Independent of navigation,
    /// so nothing can pop or replace it while it is open.
    case sheet

    /// Pushes onto the surrounding `NavigationStack`.
    case push
}

/// The system's page background.
///
/// These views must paint their own ground rather than inheriting the host's.
/// Label colours follow the colour scheme, so a view drawn over a mismatched
/// background renders white text on white — which reads as a blank screen.
@available(iOS 15, macOS 12, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
var platformBackground: Color {
    #if canImport(UIKit)
    return Color(uiColor: .systemBackground)
    #elseif canImport(AppKit)
    return Color(nsColor: .textBackgroundColor)
    #else
    return Color.clear
    #endif
}

/// Normalizes anything thrown by the SDK into a ``DevsAppError``.
func asDevsAppError(_ error: any Error) -> DevsAppError {
    (error as? DevsAppError) ?? .network(underlying: error)
}

/// Shown when a load fails, with the one action that can help.
@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct ErrorStateView: View {
    let error: DevsAppError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(error.errorDescription ?? "Something went wrong.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        switch error {
        case .unauthorized: return "lock.trianglebadge.exclamationmark"
        case .network: return "wifi.slash"
        case .notFound: return "questionmark.app.dashed"
        case .api: return "exclamationmark.icloud"
        case .decoding: return "doc.badge.gearshape"
        }
    }
}

/// Remote image with a placeholder that holds its space, so rows don't jump.
@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct RemoteImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 12
    var label: String?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder.overlay(
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                )
            default:
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            // `.separator` is iOS 17+; `.quaternary` reads the same and is iOS 15+.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .accessibilityLabel(label ?? "")
        .accessibilityHidden(label == nil)
    }

    private var placeholder: some View {
        Rectangle().fill(.quaternary)
    }
}

/// Shown inline above a list whose refresh failed, when there is still content
/// worth keeping on screen.
@available(iOS 16, macOS 13, visionOS 1, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
struct RefreshErrorBanner: View {
    let error: DevsAppError
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: error.requiresAuthentication
                  ? "lock.trianglebadge.exclamationmark"
                  : "arrow.clockwise.circle")
                .foregroundStyle(.secondary)
            Text(error.errorDescription ?? "Couldn’t refresh.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Retry", action: retry)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
        )
    }
}
