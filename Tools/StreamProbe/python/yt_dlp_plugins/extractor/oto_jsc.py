"""Provider giải thử thách JS của yt-dlp bằng JavaScriptCore (C API, gọi qua ctypes).

JavaScriptCore chạy ngay trong tiến trình app, không cần WKWebView hay tiến trình WebContent,
nên vẫn chạy được khi app ở nền. Có sẵn trên macOS và iOS dưới dạng framework công khai.
Không tự giải mã chữ ký: chỉ chạy đoạn script mà yt-dlp (yt-dlp-ejs) đã dựng.
"""
from __future__ import annotations

import ctypes
import ctypes.util
import threading

from yt_dlp.extractor.youtube.jsc._builtin.ejs import EJSBaseJCP
from yt_dlp.extractor.youtube.jsc.provider import (
    JsChallengeProvider,
    JsChallengeProviderError,
    JsChallengeRequest,
    register_preference,
    register_provider,
)

_LOCK = threading.Lock()
_JSC = None

# Bọc console.log để gom output vào một mảng; không cần callback từ JS sang Python.
_PRELUDE = (
    'var __otoOut = [];'
    'var console = { log: function() { __otoOut.push(Array.prototype.map.call(arguments, String).join(" ")); },'
    ' error: function() {}, warn: function() {}, info: function() {}, debug: function() {} };'
)


def _load():
    global _JSC
    if _JSC is not None:
        return _JSC
    path = ctypes.util.find_library('JavaScriptCore') or (
        '/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore')
    lib = ctypes.CDLL(path)
    vp = ctypes.c_void_p
    lib.JSGlobalContextCreate.restype = vp
    lib.JSGlobalContextCreate.argtypes = [vp]
    lib.JSGlobalContextRelease.argtypes = [vp]
    lib.JSStringCreateWithUTF8CString.restype = vp
    lib.JSStringCreateWithUTF8CString.argtypes = [ctypes.c_char_p]
    lib.JSStringRelease.argtypes = [vp]
    lib.JSEvaluateScript.restype = vp
    lib.JSEvaluateScript.argtypes = [vp, vp, vp, vp, ctypes.c_int, ctypes.POINTER(vp)]
    lib.JSValueToStringCopy.restype = vp
    lib.JSValueToStringCopy.argtypes = [vp, vp, ctypes.POINTER(vp)]
    lib.JSStringGetMaximumUTF8CStringSize.restype = ctypes.c_size_t
    lib.JSStringGetMaximumUTF8CStringSize.argtypes = [vp]
    lib.JSStringGetUTF8CString.restype = ctypes.c_size_t
    lib.JSStringGetUTF8CString.argtypes = [vp, ctypes.c_char_p, ctypes.c_size_t]
    _JSC = lib
    return lib


def _to_text(lib, ctx, value):
    exc = ctypes.c_void_p()
    js_string = lib.JSValueToStringCopy(ctx, value, ctypes.byref(exc))
    if not js_string:
        return ''
    try:
        size = lib.JSStringGetMaximumUTF8CStringSize(js_string)
        buffer = ctypes.create_string_buffer(size)
        lib.JSStringGetUTF8CString(js_string, buffer, size)
        return buffer.value.decode('utf-8', 'replace')
    finally:
        lib.JSStringRelease(js_string)


def _evaluate(lib, ctx, source):
    script = lib.JSStringCreateWithUTF8CString(source.encode('utf-8'))
    exc = ctypes.c_void_p()
    try:
        value = lib.JSEvaluateScript(ctx, script, None, None, 1, ctypes.byref(exc))
    finally:
        lib.JSStringRelease(script)
    if exc.value:
        raise JsChallengeProviderError('JavaScriptCore: ' + _to_text(lib, ctx, exc)[:300])
    return value


def run_script(source: str) -> str:
    """Chạy script trong một context mới và trả về toàn bộ output của console.log."""
    lib = _load()
    with _LOCK:
        ctx = lib.JSGlobalContextCreate(None)
        try:
            _evaluate(lib, ctx, _PRELUDE)
            _evaluate(lib, ctx, source)
            return _to_text(lib, ctx, _evaluate(lib, ctx, '__otoOut.join("\\n")'))
        finally:
            lib.JSGlobalContextRelease(ctx)


@register_provider
class OtoJavaScriptCoreJCP(EJSBaseJCP):
    PROVIDER_NAME = 'oto-jsc'
    JS_RUNTIME_NAME = 'oto-jsc'
    PROVIDER_VERSION = '0.1.0'
    BUG_REPORT_LOCATION = 'Oto spike'

    def is_available(self, /) -> bool:
        try:
            _load()
            return True
        except OSError:
            return False

    def _run_js_runtime(self, stdin: str, /) -> str:
        return run_script(stdin)


@register_preference(OtoJavaScriptCoreJCP)
def oto_jsc_preference(provider: JsChallengeProvider, requests: list[JsChallengeRequest]) -> int:
    return 1000
