"""Lấy URL audio M4A cho một video bằng yt-dlp, chỉ dùng provider JavaScriptCore của Oto.

Trả về dict: url (chỉ dùng trong bộ nhớ), format_id, abr, client, expire, seconds.
Không ghi log URL, không dùng cookie.
"""
from __future__ import annotations

import re
import time


class _QuietLogger:
    def __init__(self):
        self.lines = []

    def debug(self, msg):
        if msg.startswith('[youtube]') or '[jsc' in msg:
            self.lines.append(re.sub(r'https?://\S+', '<url>', msg)[:200])

    info = debug

    def warning(self, msg):
        self.lines.append('WARN ' + re.sub(r'https?://\S+', '<url>', msg)[:200])

    def error(self, msg):
        self.lines.append('ERR ' + re.sub(r'https?://\S+', '<url>', msg)[:200])


def resolve(video_id: str, cache_dir: str | None = None) -> dict:
    import yt_dlp  # nhập muộn để đo được thời gian import riêng

    if not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id):
        raise ValueError('video id không hợp lệ')
    logger = _QuietLogger()
    started = time.monotonic()
    options = {
        'format': 'bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]',
        'quiet': True,
        'no_warnings': False,
        'skip_download': True,
        'noplaylist': True,
        'logger': logger,
        'js_runtimes': {},  # tắt node/deno/bun; chỉ còn provider oto-jsc
        'cachedir': cache_dir or False,
    }
    with yt_dlp.YoutubeDL(options) as ydl:
        info = ydl.extract_info('https://music.youtube.com/watch?v=' + video_id, download=False)
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
        'log': logger.lines[-12:],
    }
