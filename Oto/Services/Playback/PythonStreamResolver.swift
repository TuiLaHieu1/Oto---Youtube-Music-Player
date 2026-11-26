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
    /// Nhãn lỗi cố định từ oto_resolve.classify (ví dụ videoUnavailable, timeout, apiPage).
    var errorLabel: String?
    var profile: String?
    /// Manifest HLS có hình cho chế độ Video; chỉ giữ trong bộ nhớ.
    var hlsURL: URL?
    var mediaDuration: Double?

    var logLine: String {
        let abr = self.averageBitrate.map { String(Int($0.rounded())) } ?? "nil"
        let expiry = self.secondsUntilExpiry.map(String.init) ?? "nil"
        let took = self.seconds.map { String(format: "%.1f", $0) } ?? "nil"
        let outcome = self.url != nil ? "ok" : "error(\(self.errorKind ?? "unknown"))"
        let duration = self.mediaDuration.map { String(format: "%.2f", $0) } ?? "nil"
        return "YtdlpProbe outcome=\(outcome) format=\(self.formatID ?? "nil") abr=\(abr) "
            + "expiresIn=\(expiry) hasN=\(self.hasNParameter) seconds=\(took) profile=\(self.profile ?? "nil") "
            + "hasHLS=\(self.hlsURL != nil) mediaDuration=\(duration)"
    }

    static func failure(_ kind: String, label: String? = nil) -> YtdlpResolveResult {
        var result = YtdlpResolveResult(
            url: nil, formatID: nil, averageBitrate: nil, secondsUntilExpiry: nil,
            hasNParameter: false, seconds: nil, errorKind: kind
        )
        result.errorLabel = label
        return result
    }

    /// Lỗi do chính bài (bị chặn, không có định dạng phát được) thì nên bỏ qua bài; lỗi mạng thì không.
    var isTrackUnavailable: Bool {
        ["videoUnavailable", "noFormat", "signIn", "botCheck", "http403"].contains(self.errorLabel ?? "")
    }
}

/// Chạy yt-dlp nhúng trong app để lấy URL M4A. Python được nạp bằng `dlopen` chỉ khi có cờ khảo sát,
/// nên bản build bình thường không link Python. Mọi lệnh gọi Python chạy tuần tự trên một hàng đợi riêng.
enum PythonStreamResolver {
    /// Hàng đợi song song: một lần lấy URL bị treo vì mạng không chặn các bài khác.
    /// Mỗi lần gọi giữ GIL riêng và dùng dict biến riêng; Python nhả GIL trong lúc chờ mạng.
    private static let queue = DispatchQueue(
        label: "com.oto.music.stream-probe.python", qos: .userInitiated, attributes: .concurrent
    )
    /// Khởi tạo Python đúng một lần dù nhiều luồng cùng gọi.
    private static let initLock = NSLock()
    private static let pyFileInput: Int32 = 257

    static func resolve(videoID: String, lowBandwidth: Bool = false) async -> YtdlpResolveResult {
        guard YTMusicClient.isValidVideoID(videoID) else { return .failure("invalidInput") }
        let result = await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: Self.runResolve(videoID: videoID, lowBandwidth: lowBandwidth))
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
    private typealias NewDictFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias SetItemFn = @convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>, UnsafeMutableRawPointer?
    ) -> Int32
    private typealias GetItemFn = @convention(c) (
        UnsafeMutableRawPointer?, UnsafePointer<CChar>
    ) -> UnsafeMutableRawPointer?

    /// `dlsym` trả về con trỏ thô; ép sang kiểu hàm C là cách duy nhất để gọi từ Swift.
    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// Nạp yt-dlp và tạo sẵn YoutubeDL lúc mở app, để bài đầu tiên không phải chờ phần này.
    static func warm() async {
        guard let cacheLiteral = Self.pythonStringLiteral(Self.cachePath) else { return }
        let source = """
        import json as __oto_json
        try:
            from oto_resolve import warm as __oto_warm
            __oto_result = __oto_json.dumps(__oto_warm(cache_dir=\(cacheLiteral)))
        except Exception as __oto_e:
            __oto_result = __oto_json.dumps({'error': type(__oto_e).__name__})
        """
        let text = await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume(returning: Self.runPython(source) ?? "{}") }
        }
        StreamProbeLog.write("YtdlpWarm " + text)
    }

    private static var cachePath: String {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("yt-dlp", isDirectory: true).path ?? ""
    }

    /// Đo mạng của Python trong app (DNS, TCP, HTTPS). Chỉ ghi số đo và nhãn lỗi.
    static func netcheck() async {
        let source = """
        import json as __oto_json
        try:
            from oto_resolve import netcheck as __oto_netcheck
            __oto_result = __oto_json.dumps(__oto_netcheck())
        except Exception as __oto_e:
            __oto_result = __oto_json.dumps({'error': type(__oto_e).__name__})
        """
        let text = await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume(returning: Self.runPython(source) ?? "{\"error\":\"python\"}") }
        }
        // Kết quả chỉ gồm khóa cố định, số và tên lớp lỗi; không có địa chỉ IP hay URL.
        StreamProbeLog.write("PythonNet " + text)
    }

    private static func runResolve(videoID: String, lowBandwidth: Bool) -> YtdlpResolveResult {
        guard let cacheLiteral = Self.pythonStringLiteral(Self.cachePath) else { return .failure("cachePath") }
        // videoID đã được kiểm tra chỉ gồm [A-Za-z0-9_-]; đường dẫn cache được mã hóa thành chuỗi JSON.
        let source = """
        import json as __oto_json, re as __oto_re
        try:
            from oto_resolve import resolve as __oto_resolve
            __oto_r = __oto_resolve('\(videoID)', cache_dir=\(cacheLiteral), low_bandwidth=\(lowBandwidth ? "True" : "False"))
            __oto_r.pop('log', None)
            __oto_result = __oto_json.dumps({'ok': True, **__oto_r})
        except Exception as __oto_e:
            from oto_resolve import classify as __oto_classify, last_error_label as __oto_last
            __oto_result = __oto_json.dumps({'ok': False, 'error': type(__oto_e).__name__,
                                             'label': __oto_classify(str(__oto_e)), 'lastLog': __oto_last()})
        """
        guard let text = Self.runPython(source) else { return .failure("python") }
        return Self.parse(text)
    }

    /// Chạy `source` trong `__main__` và trả về chuỗi trong biến `__oto_result`. Chỉ gọi trên `queue`.
    private static func runPython(_ source: String) -> String? {
        guard let frameworks = Bundle.main.privateFrameworksPath,
              let handle = dlopen(frameworks + "/Python.framework/Python", RTLD_NOW | RTLD_GLOBAL) else {
            return nil
        }
        guard let isInitialized = symbol(handle, "Py_IsInitialized", as: IntFn.self),
              let initialize = symbol(handle, "Py_Initialize", as: VoidFn.self),
              let saveThread = symbol(handle, "PyEval_SaveThread", as: PtrFn.self),
              let gilEnsure = symbol(handle, "PyGILState_Ensure", as: IntFn.self),
              let gilRelease = symbol(handle, "PyGILState_Release", as: ReleaseFn.self),
              let addModule = symbol(handle, "PyImport_AddModule", as: AddModuleFn.self),
              let getDict = symbol(handle, "PyModule_GetDict", as: GetDictFn.self),
              let newDict = symbol(handle, "PyDict_New", as: NewDictFn.self),
              let setItem = symbol(handle, "PyDict_SetItemString", as: SetItemFn.self),
              let getItem = symbol(handle, "PyDict_GetItemString", as: GetItemFn.self),
              let runString = symbol(handle, "PyRun_StringFlags", as: RunStringFn.self),
              let asUTF8 = symbol(handle, "PyUnicode_AsUTF8", as: AsUTF8Fn.self),
              let decRef = symbol(handle, "Py_DecRef", as: DecRefFn.self),
              let printError = symbol(handle, "PyErr_Print", as: VoidFn.self) else {
            return nil
        }
        Self.initLock.lock()
        if isInitialized() == 0 {
            Self.configureEnvironment()
            initialize()
            _ = saveThread()
        }
        Self.initLock.unlock()
        let state = gilEnsure()
        defer { gilRelease(state) }
        // Dict biến riêng cho mỗi lần gọi, có __builtins__ lấy từ __main__.
        guard let main = addModule("__main__"), let mainGlobals = getDict(main),
              let builtins = getItem(mainGlobals, "__builtins__"), let globals = newDict() else { return nil }
        defer { decRef(globals) }
        guard setItem(globals, "__builtins__", builtins) == 0 else { return nil }
        guard let executed = runString(source, Self.pyFileInput, globals, globals, nil) else {
            printError()
            return nil
        }
        decRef(executed)
        guard let value = getItem(globals, "__oto_result"), let text = asUTF8(value) else { return nil }
        return String(cString: text)
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
            let name = (object["error"] as? String).flatMap { allowed.contains($0) ? $0 : "other" } ?? "unknown"
            // Nhãn do oto_resolve.classify tạo từ danh sách cố định; lọc lại cho chắc chỉ là chữ thường/hoa.
            let safe = { (value: Any?) -> String in
                guard let text = value as? String, text.count <= 20, text.allSatisfy({ $0.isLetter || $0.isNumber })
                else { return "other" }
                return text
            }
            let label = safe(object["label"]) == "other" ? safe(object["lastLog"]) : safe(object["label"])
            return .failure("\(name):\(safe(object["label"]))/\(safe(object["lastLog"]))", label: label)
        }
        let url = (object["url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        let expire = object["expire"] as? Int
        let query = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        var result = YtdlpResolveResult(
            url: url,
            formatID: (object["format_id"] as? String).map { String($0.prefix(8)) },
            averageBitrate: object["abr"] as? Double,
            secondsUntilExpiry: expire.map { $0 - Int(Date().timeIntervalSince1970) },
            hasNParameter: query.contains { $0.name == "n" },
            seconds: object["seconds"] as? Double,
            errorKind: url == nil ? "noURL" : nil
        )
        let profile = object["profile"] as? String
        result.profile = ["fast", "default"].contains(profile ?? "") ? profile : nil
        result.hlsURL = (object["hls"] as? String).flatMap(URL.init(string:))
            .flatMap { $0.scheme == "https" ? $0 : nil }
        if let duration = object["duration"] as? Double, duration.isFinite, duration > 0 {
            result.mediaDuration = duration
        }
        return result
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
