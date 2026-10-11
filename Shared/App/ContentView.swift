import SwiftUI

#if os(macOS)
import AppKit
import WebKit

struct RaspberryWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        return makeConfiguredWebView()
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private func makeConfiguredWebView() -> WKWebView {
    let config = WKWebViewConfiguration()
    config.setURLSchemeHandler(LocalSchemeHandler(), forURLScheme: "raspberry")
    
    config.preferences.setValue(true, forKey: "developerExtrasEnabled")
    
    let webView = WKWebView(frame: .zero, configuration: config)
    
    
    if let url = URL(string: "raspberry://app/index.html") {
        webView.load(URLRequest(url: url))
    }
    return webView
}

#endif

public struct ContentView: View {
    public init() {}
    
    public var body: some View {
        #if os(iOS)
        NativeBerryView()
        #else
        ZStack {
            Color.black.ignoresSafeArea()
            RaspberryWebView()
                .ignoresSafeArea()
        }
        #endif
    }
}
