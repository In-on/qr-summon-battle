import Foundation
import WebKit
import UniformTypeIdentifiers

/// qrsummon://localhost/xxx を、アプリ内の www/xxx から返す。
/// file:// ではなく独自スキームにすることで、XHR / fetch / カメラ（安全なコンテキスト）が Web 版と同じように動く。
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL = Bundle.main.resourceURL!.appendingPathComponent("www", isDirectory: true)
    private var stopped = Set<ObjectIdentifier>()
    private let lock = NSLock()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path                         // クエリ（?v=1 など）は url.path に含まれない
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL

        // www の外は読ませない
        guard file.path.hasPrefix(root.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else {
            let res = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1",
                                      headerFields: ["Content-Type": "text/plain", "Content-Length": "0"])!
            send(task, response: res, data: Data())
            return
        }
        let mime = Self.mimeType(for: file)
        let res = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache",
        ])!
        // HEAD リクエストには本文を返さない
        send(task, response: res, data: task.request.httpMethod == "HEAD" ? Data() : data)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        lock.lock(); stopped.insert(ObjectIdentifier(task)); lock.unlock()
    }

    private func send(_ task: WKURLSchemeTask, response: URLResponse, data: Data) {
        lock.lock(); let isStopped = stopped.remove(ObjectIdentifier(task)) != nil; lock.unlock()
        if isStopped { return }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "glb": return "model/gltf-binary"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        default:
            return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
