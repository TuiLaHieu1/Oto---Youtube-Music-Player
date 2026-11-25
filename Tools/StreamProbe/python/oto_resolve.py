"""Lấy URL audio M4A cho một video bằng yt-dlp, chỉ dùng provider JavaScriptCore của Oto.

Giữ một YoutubeDL dùng lại giữa các lần gọi để không phải dựng lại extractor, client và cache.
Trả về dict: url (chỉ dùng trong bộ nhớ), format_id, abr, expire, seconds. Không ghi log URL, không dùng cookie.
"""
from __future__ import annotations

import re
import threading
import time

# Nhóm YoutubeDL dùng lại: mỗi lần gọi mượn một cái đang rảnh, xong thì trả lại.
# YoutubeDL không an toàn khi hai luồng dùng cùng lúc; tạo mới cũng nạp plugin vào registry chung.
_POOL = []
_POOL_LOCK = threading.Lock()
_CREATE_LOCK = threading.Lock()
_LAST = threading.local()


class _QuietLogger:
    def __init__(self):
        self.lines = []

    def _keep(self, prefix, msg):
        self.lines.append(prefix + re.sub(r'https?://\S+', '<url>', msg)[:200])
        del self.lines[:-20]

    def debug(self, msg):
        if msg.startswith('[youtube]') or '[jsc' in msg:
            self._keep('', msg)

    info = debug

    def warning(self, msg):
        self._keep('WARN ', msg)

    def error(self, msg):
        self._keep('ERR ', msg)


def _borrow(cache_dir):
    with _POOL_LOCK:
        for index, (ydl, directory) in enumerate(_POOL):
            if directory == cache_dir:
                return _POOL.pop(index)[0]
    import yt_dlp
    options = {
        'format': 'bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]',
        'quiet': True,
        'skip_download': True,
        'noplaylist': True,
        'logger': _QuietLogger(),
        'js_runtimes': {},  # tắt node/deno/bun; chỉ còn provider oto-jsc
        'cachedir': cache_dir or False,
        # Mạng điện thoại có lúc chập chờn; giới hạn thời gian chờ để lỗi rõ ràng thay vì treo.
        'socket_timeout': 8,
        'retries': 1,
        'extractor_retries': 1,
    }
    with _CREATE_LOCK:
        return yt_dlp.YoutubeDL(options)


def _give_back(ydl, cache_dir):
    with _POOL_LOCK:
        if len(_POOL) < 3:
            _POOL.append((ydl, cache_dir))


_ERROR_LABELS = [
    ('not a bot', 'botCheck'), ('sign in', 'signIn'), ('po token', 'poToken'),
    ('requested format is not available', 'noFormat'), ('http error 403', 'http403'),
    ('http error 429', 'http429'), ('http error 4', 'http4xx'), ('http error 5', 'http5xx'),
    ('timed out', 'timeout'), ('unable to download api page', 'apiPage'),
    ('nodename nor servname', 'dns'), ('network is unreachable', 'offline'),
    ('certificate', 'tls'), ('ssl', 'tls'), ('challenge', 'jsChallenge'), ('javascriptcore', 'jsChallenge'),
    ('unavailable', 'videoUnavailable'), ('private video', 'videoUnavailable'),
]


def classify(message: str) -> str:
    """Đổi nội dung lỗi thành nhãn cố định; không trả về chuỗi gốc vì có thể chứa ID hay URL."""
    lowered = (message or '').lower()
    for needle, label in _ERROR_LABELS:
        if needle in lowered:
            return label
    return 'other'


def last_error_label() -> str:
    ydl = getattr(_LAST, 'ydl', None)
    lines = ydl.params['logger'].lines if ydl is not None else []
    for line in reversed(lines):
        if line.startswith('ERR ') or line.startswith('WARN '):
            return classify(line)
    return 'none'


def resolve(video_id: str, cache_dir: str | None = None) -> dict:
    if not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id):
        raise ValueError('video id không hợp lệ')
    started = time.monotonic()
    ydl = _borrow(cache_dir)
    _LAST.ydl = ydl
    try:
        info = ydl.extract_info('https://music.youtube.com/watch?v=' + video_id, download=False)
    finally:
        _give_back(ydl, cache_dir)
    url = info.get('url') or ''
    match = re.search(r'[?&/]expire[=/](\d+)', url)
    return {
        'url': url,
        'format_id': info.get('format_id'),
        'ext': info.get('ext'),
        'acodec': info.get('acodec'),
        'abr': info.get('abr'),
        'expire': int(match.group(1)) if match else None,
        'seconds': round(time.monotonic() - started, 2),
        'log': list(ydl.params['logger'].lines[-12:]),
    }


def netcheck(host: str = 'music.youtube.com') -> dict:
    """Đo mạng của Python trong app: DNS, TCP IPv4/IPv6 và một request HTTPS. Chỉ trả số đo và nhãn lỗi."""
    import socket
    import ssl
    import urllib.request
    result = {}
    started = time.monotonic()
    try:
        infos = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
        result['dns_s'] = round(time.monotonic() - started, 2)
        result['v4'] = sum(1 for i in infos if i[0] == socket.AF_INET)
        result['v6'] = sum(1 for i in infos if i[0] == socket.AF_INET6)
        result['first'] = 'v6' if infos and infos[0][0] == socket.AF_INET6 else 'v4'
    except Exception as error:
        result['dns_error'] = classify(str(error)) + ':' + type(error).__name__
        return result
    for family, label in ((socket.AF_INET, 'tcp4'), (socket.AF_INET6, 'tcp6')):
        address = next((i[4] for i in infos if i[0] == family), None)
        if address is None:
            continue
        started = time.monotonic()
        try:
            with socket.socket(family, socket.SOCK_STREAM) as sock:
                sock.settimeout(8)
                sock.connect(address)
            result[label + '_s'] = round(time.monotonic() - started, 2)
        except Exception as error:
            result[label + '_error'] = type(error).__name__
    started = time.monotonic()
    try:
        context = ssl.create_default_context()
        request = urllib.request.Request('https://' + host + '/', method='HEAD')
        with urllib.request.urlopen(request, timeout=10, context=context) as response:
            result['https_status'] = response.status
        result['https_s'] = round(time.monotonic() - started, 2)
    except Exception as error:
        result['https_error'] = classify(str(error)) + ':' + type(error).__name__
    return result
