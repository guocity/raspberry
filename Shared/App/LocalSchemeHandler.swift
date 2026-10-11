import Foundation
import WebKit

public class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    private let localWebRoot: URL?
    
    public override init() {
        // Priority 1: Check bundle resources
        if let bundleWeb = Bundle.main.url(forResource: "web", withExtension: nil) {
            self.localWebRoot = bundleWeb
        } else if let bundleSub = Bundle.main.resourceURL?.appendingPathComponent("web"),
                  FileManager.default.fileExists(atPath: bundleSub.path) {
            self.localWebRoot = bundleSub
        } else {
            // Priority 2: Fallback to developer workspace path
            let devPath = URL(fileURLWithPath: "/Users/m4air/Documents/github/raspberry/web")
            if FileManager.default.fileExists(atPath: devPath.path) {
                self.localWebRoot = devPath
            } else {
                self.localWebRoot = nil
            }
        }
        super.init()
    }
    
    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        
        var requestPath = url.path
        if requestPath.isEmpty || requestPath == "/" {
            requestPath = "/index.html"
        }
        
        guard let root = localWebRoot else {
            let error = NSError(domain: "LocalSchemeHandler", code: 404, userInfo: [NSLocalizedDescriptionKey: "Web root not found"])
            urlSchemeTask.didFailWithError(error)
            return
        }
        
        // Strip leading slash for relative appending
        let relativePath = requestPath.hasPrefix("/") ? String(requestPath.dropFirst()) : requestPath
        let fileUrl = root.appendingPathComponent(relativePath)
        
        guard let data = try? Data(contentsOf: fileUrl) else {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Access-Control-Allow-Origin": "*"]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
            return
        }
        
        let ext = fileUrl.pathExtension.lowercased()
        let mimeType: String
        switch ext {
        case "html": mimeType = "text/html"
        case "js": mimeType = "application/javascript"
        case "wasm": mimeType = "application/wasm"
        case "json": mimeType = "application/json"
        case "glb": mimeType = "model/gltf-binary"
        case "bin": mimeType = "application/octet-stream"
        case "ktx2": mimeType = "image/ktx2"
        case "hdr": mimeType = "image/vnd.radiance"
        case "png": mimeType = "image/png"
        case "jpg", "jpeg": mimeType = "image/jpeg"
        case "css": mimeType = "text/css"
        default: mimeType = "application/octet-stream"
        }
        
        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "public, max-age=31536000"
        ]
        
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else { return }
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
