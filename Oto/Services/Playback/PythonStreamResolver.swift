#if DEBUG && OTO_STREAM_PROBE
import Foundation
import OSLog

/// Kết quả lấy URL audio. URL chỉ giữ trong bộ nhớ; `logLine` không bao giờ chứa URL.
struct YtdlpResolveResult: Sendable {
    let url: URL?
    let formatID: String?
    let averageBitrate: Double?
    let secondsUntilExpiry: Int?
    let hasNParameter: Bool
    let seconds: Double?
    let errorKind: String?

    var logLine: String {
        let abr = self.averageBitrate.map { String(Int($0.rounded())) } ?? "nil"
        let expiry = self.secondsUntilExpiry.map(String.init) ?? "nil"
        let took = self.seconds.map { String(format: "%.1f", $0) } ?? "nil"
        let outcome = self.url != nil ? "ok" : "error(\(self.errorKind ?? "unknown"))"
        return "YtdlpProbe outcome=\(outcome) format=\(self.formatID ?? "nil") abr=\(abr) "
            + "expiresIn=\(expiry) hasN=\(self.hasNParameter) seconds=\(took)"
    }

    static func failure(_ kind: String) -> YtdlpResolveResult {
        YtdlpResolveResult(
            url: nil, formatID: nil, averageBitrate: nil, secondsUntilExpiry: nil,
            hasNParameter: false, seconds: nil, errorKind: kind
        )
    }
}

/// Chạy yt-dlp nhúng trong app để lấy URL M4A. Python được nạp bằng `dlopen` chỉ khi có cờ khảo sát,
/// nên bản build bình thường không link Python. Mọi lệnh gọi Python chạy tuần tự trên một hàng đợi riêng.
enum PythonStreamResolver {
    private static let queue = DispatchQueue(label: "com.oto.music.stream-probe.python", qos: .userInitiated)
    private static let pyFileInput: Int32 = 257
    private static let pyEvalInput: Int32 = 258

    static func resolve(videoID: String) async -> YtdlpResolveResult {
        guard YTMusicClient.isValidVideoID(videoID) else { return .failure("invalidInput") }
        let result = await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: Self.runResolve(videoID: videoID))
            }
        }
        StreamProbeLog.write(result.logLine)
        return result
    }

    // MARK: - Python C API (chỉ chạy trên `queue`)

    private typealias VoidFn = @convention(c) () -> Void
    private typealias IntFn = @convention(c) () -> Int32
    private typealias PtrFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias ReleaseFn = @convention(c) (Int32) -> Void
    private typealias AddModuleFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
    private typealias GetDictFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    private typealias RunStringFn = @convention(c) (
        UnsafePointer<CChar>, Int32, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
    ) -> UnsafeMutableRawPointer?
    private typealias AsUTF8Fn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
    private typealias DecRefFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

    /// `dlsym` trả về con trỏ thô; ép sang kiểu hàm C là cách duy nhất để gọi từ Swift.
    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static func runResolve(videoID: String) -> YtdlpResolveResult {
        guard let frameworks = Bundle.main.privateFrameworksPath,
              let handle = dlopen(frameworks + "/Python.framework/Python", RTLD_NOW | RTLD_GLOBAL) else {
            return .failure("pythonMissing")
        }
        guard let isInitialized = symbol(handle, "Py_IsInitialized", as: IntFn.self),
              let initialize = symbol(handle, "Py_Initialize", as: VoidFn.self),
              let saveThread = symbol(handle, "PyEval_SaveThread", as: PtrFn.self),
              let gilEnsure = symbol(handle, "PyGILState_Ensure", as: IntFn.self),
              let gilRelease = symbol(handle, "PyGILState_Release", as: ReleaseFn.self),
              let addModule = symbol(handle, "PyImport_AddModule", as: AddModuleFn.self),
              let getDict = symbol(handle, "PyModule_GetDict", as: GetDictFn.self),
              let runString = symbol(handle, "PyRun_StringFlags", as: RunStringFn.self),
              let asUTF8 = symbol(handle, "PyUnicode_AsUTF8", as: AsUTF8Fn.self),
              let decRef = symbol(handle, "Py_DecRef", as: DecRefFn.self),
              let printError = symbol(handle, "PyErr_Print", as: VoidFn.self) else {
            return .failure("pythonSymbols")
        }
        if isInitialized() == 0 {
            Self.configureEnvironment()
            initialize()
            _ = saveThread()
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("yt-dlp", isDirectory: true).path ?? ""
        guard let cacheLiteral = Self.pythonStringLiteral(caches) else { return .failure("cachePath") }
        // videoID đã được kiểm tra chỉ gồm [A-Za-z0-9_-]; đường dẫn cache được mã hóa thành chuỗi JSON.
        let source = """
        import json as __oto_json, re as __oto_re
        try:
            from oto_resolve import resolve as __oto_resolve
            __oto_r = __oto_resolve('\(videoID)', cache_dir=\(cacheLiteral))
            __oto_r.pop('log', None)
            __oto_result = __oto_json.dumps({'ok': True, **__oto_r})
        except Exception as __oto_e:
            __oto_result = __oto_json.dumps({'ok': False, 'error': type(__oto_e).__name__})
        """
        let state = gilEnsure()
        defer { gilRelease(state) }
        guard let main = addModule("__main__"), let globals = getDict(main) else { return .failure("pythonMain") }
        guard let executed = runString(source, Self.pyFileInput, globals, globals, nil) else {
            printError()
            return .failure("pythonException")
        }
        decRef(executed)
        guard let value = runString("__oto_result", Self.pyEvalInput, globals, globals, nil) else {
            printError()
            return .failure("pythonResult")
        }
        defer { decRef(value) }
        guard let text = asUTF8(value) else { return .failure("pythonResult") }
        return Self.parse(String(cString: text))
    }

    private static func configureEnvironment() {
        let bundle = Bundle.main.bundlePath
        setenv("PYTHONHOME", bundle + "/python", 1)
        setenv("PYTHONPATH", bundle + "/app_packages", 1)
        setenv("PYTHONUTF8", "1", 1)
        setenv("PYTHONDONTWRITEBYTECODE", "1", 1)
        setenv("SSL_CERT_FILE", bundle + "/app_packages/certifi/cacert.pem", 1)
    }

    private static func pythonStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parse(_ json: String) -> YtdlpResolveResult {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return .failure("resultSchema")
        }
        guard object["ok"] as? Bool == true else {
            let allowed = ["DownloadError", "ExtractorError", "ValueError", "OSError", "ImportError"]
            let name = object["error"] as? String
            return .failure(name.flatMap { allowed.contains($0) ? $0 : "other" } ?? "unknown")
        }
        let url = (object["url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        let expire = object["expire"] as? Int
        let query = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return YtdlpResolveResult(
            url: url,
            formatID: (object["format_id"] as? String).map { String($0.prefix(8)) },
            averageBitrate: object["abr"] as? Double,
            secondsUntilExpiry: expire.map { $0 - Int(Date().timeIntervalSince1970) },
            hasNParameter: query.contains { $0.name == "n" },
            seconds: object["seconds"] as? Double,
            errorKind: url == nil ? "noURL" : nil
        )
    }
}

/// Ghi log khảo sát vào unified log (Console.app) và stdout (đọc được qua `devicectl --console`).
enum StreamProbeLog {
    static func write(_ line: String) {
        Logger(subsystem: "com.oto.music", category: "StreamProbe").notice("\(line, privacy: .public)")
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

#endif
