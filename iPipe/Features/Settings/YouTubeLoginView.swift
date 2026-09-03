import SwiftUI
import WebKit

struct YouTubeLoginView: View {
    var onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoginWebView()
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Sign in to YouTube")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            saveCookies()
                        }
                    }
                }
        }
    }

    private func saveCookies() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let relevant = cookies.filter {
                $0.domain.contains("youtube.com") || $0.domain.contains("google.com")
            }
            let yt = relevant.map {
                YTCookie(
                    name: $0.name,
                    value: $0.value,
                    domain: $0.domain,
                    path: $0.path,
                    secure: $0.isSecure,
                    expires: $0.expiresDate
                )
            }
            CookieStore.shared.merge(yt)
            Task { @MainActor in
                onComplete()
                dismiss()
            }
        }
    }
}

struct LoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let delegate = LoginNavigationDelegate()
        delegate.onNavigate = { url in
            if let url { Log.url(url.absoluteString) }
        }
        webView.navigationDelegate = delegate
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1"
        if let url = URL(string: "https://www.youtube.com/account") {
            Log.url(url.absoluteString)
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

final class LoginNavigationDelegate: NSObject, WKNavigationDelegate {
    var onNavigate: (URL?) -> Void = { _ in }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onNavigate(webView.url)
    }
}
