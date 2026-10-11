import SwiftUI
import WebKit

#if os(macOS)
import AppKit

struct RaspberryWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        return makeConfiguredWebView()
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#elseif os(iOS)
import UIKit

struct RaspberryWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        return makeConfiguredWebView()
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

private func makeConfiguredWebView() -> WKWebView {
    let config = WKWebViewConfiguration()
    config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: "raspberry")
    
    #if os(macOS)
    config.preferences.setValue(true, forKey: "developerExtrasEnabled")
    #endif
    
    let webView = WKWebView(frame: .zero, configuration: config)
    
    #if os(iOS)
    webView.isOpaque = false
    webView.backgroundColor = .black
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.bounces = false
    #endif
    
    if let url = URL(string: "raspberry://app/index.html") {
        webView.load(URLRequest(url: url))
    }
    return webView
}

public struct ContentView: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RaspberryWebView()
                .ignoresSafeArea()
        }
    }
}
