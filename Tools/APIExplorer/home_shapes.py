#!/usr/bin/env python3
"""Khảo sát shape Home công khai; không đọc cookie hay ghi payload thô."""
from collections import Counter
import argparse
import json
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen


def collect(value, counts):
    if isinstance(value, dict):
        for key in ("musicVisualHeaderRenderer", "musicImmersiveHeaderRenderer",
                    "musicHeaderRenderer", "musicResponsiveListItemRenderer",
                    "musicTwoRowItemRenderer", "musicCarouselShelfRenderer",
                    "musicShelfRenderer", "musicSpeedDialShelfRenderer",
                    "continuationItemRenderer", "continuationCommand",
                    "nextContinuationData", "sectionListRenderer",
                    "sectionListContinuation", "musicShelfContinuation",
                    "appendContinuationItemsAction", "continuationContents"):
            if key in value:
                counts[key] = counts.get(key, 0) + 1
        for key, item in value.items():
            if key.lower() in ("isrc", "internationalstandardrecordingcode") and isinstance(item, str):
                counts["recording_code_fields"] = counts.get("recording_code_fields", 0) + 1
        if "timedLyricsModel" in value:
            counts["timed_lyrics_model"] = counts.get("timed_lyrics_model", 0) + 1
        if "musicDescriptionShelfRenderer" in value:
            counts["plain_lyrics_shelf"] = counts.get("plain_lyrics_shelf", 0) + 1
        browse = value.get("browseEndpoint")
        if isinstance(browse, dict) and str(browse.get("browseId", "")).startswith("MPLYt"):
            counts["lyrics_browse_endpoint"] = counts.get("lyrics_browse_endpoint", 0) + 1
        endpoint = value.get("watchEndpoint")
        if isinstance(endpoint, dict) and endpoint.get("videoId"):
            key = "watch_video_with_playlist" if endpoint.get("playlistId") else "watch_video_only"
            counts[key] = counts.get(key, 0) + 1
        for child in value.values():
            collect(child, counts)
    elif isinstance(value, list):
        for child in value:
            collect(child, counts)


def find_lyrics_browse_id(value):
    if isinstance(value, dict):
        endpoint = value.get("browseEndpoint")
        if isinstance(endpoint, dict):
            browse_id = endpoint.get("browseId")
            if isinstance(browse_id, str) and browse_id.startswith("MPLYt"):
                return browse_id
        for child in value.values():
            found = find_lyrics_browse_id(child)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = find_lyrics_browse_id(child)
            if found:
                return found
    return None


def find_catalog_browse_id(value, prefix):
    if isinstance(value, dict):
        endpoint = value.get("browseEndpoint")
        if isinstance(endpoint, dict):
            browse_id = endpoint.get("browseId")
            if isinstance(browse_id, str) and browse_id.startswith(prefix):
                return browse_id
        for child in value.values():
            found = find_catalog_browse_id(child, prefix)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = find_catalog_browse_id(child, prefix)
            if found:
                return found
    return None


def find_continuation(value):
    if isinstance(value, dict):
        continuation = value.get("nextContinuationData")
        if isinstance(continuation, dict) and isinstance(continuation.get("continuation"), str):
            return continuation["continuation"]
        command = value.get("continuationCommand")
        if isinstance(command, dict) and isinstance(command.get("token"), str):
            return command["token"]
        for child in value.values():
            found = find_continuation(child)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = find_continuation(child)
            if found:
                return found
    return None


def count_linked_artist_runs(value, stats):
    """Đếm run nghệ sĩ có browseEndpoint UC trong từng item, không in tên/ID."""
    if isinstance(value, dict):
        renderer = value.get("musicResponsiveListItemRenderer")
        if isinstance(renderer, dict):
            stats["responsive_items"] = stats.get("responsive_items", 0) + 1
            columns = renderer.get("flexColumns")
            runs = []
            if isinstance(columns, list) and len(columns) > 1:
                column = columns[1].get("musicResponsiveListItemFlexColumnRenderer")
                text = column.get("text") if isinstance(column, dict) else None
                if isinstance(text, dict) and isinstance(text.get("runs"), list):
                    runs = text["runs"]
            linked = 0
            for run in runs:
                endpoint = run.get("navigationEndpoint") if isinstance(run, dict) else None
                browse = endpoint.get("browseEndpoint") if isinstance(endpoint, dict) else None
                browse_id = browse.get("browseId") if isinstance(browse, dict) else None
                if isinstance(browse_id, str) and browse_id.startswith("UC"):
                    linked += 1
            if linked:
                stats["items_with_linked_artist"] = stats.get("items_with_linked_artist", 0) + 1
                stats["max_linked_artists_in_item"] = max(
                    stats.get("max_linked_artists_in_item", 0), linked
                )
            if linked >= 2:
                stats["items_with_multiple_linked_artists"] = (
                    stats.get("items_with_multiple_linked_artists", 0) + 1
                )
        for child in value.values():
            count_linked_artist_runs(child, stats)
    elif isinstance(value, list):
        for child in value:
            count_linked_artist_runs(child, stats)


def first_renderer_path(value, key, path=()):
    if isinstance(value, dict):
        if key in value:
            return path + (key,)
        for name, child in value.items():
            found = first_renderer_path(child, key, path + (name,))
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = first_renderer_path(child, key, path + ("[]",))
            if found:
                return found
    return None


def artist_song_shelf_endpoints(value):
    """Tìm endpoint mở rộng từ các kệ có bài hát, không xuất ID."""
    if isinstance(value, dict):
        shelf = value.get("musicShelfRenderer")
        if isinstance(shelf, dict):
            rows = shelf.get("contents", [])
            has_songs = any(
                isinstance(row, dict) and find_renderer(row, "watchEndpoint")
                for row in rows
            )
            endpoint = shelf.get("bottomEndpoint", {}).get("browseEndpoint", {})
            if has_songs and isinstance(endpoint.get("browseId"), str):
                yield endpoint
        for child in value.values():
            yield from artist_song_shelf_endpoints(child)
    elif isinstance(value, list):
        for child in value:
            yield from artist_song_shelf_endpoints(child)


def find_renderer(value, key):
    if isinstance(value, dict):
        return key in value or any(find_renderer(child, key) for child in value.values())
    if isinstance(value, list):
        return any(find_renderer(child, key) for child in value)
    return False


def artist_shelf_continuation(value):
    if isinstance(value, dict):
        command = value.get("continuationCommand")
        if isinstance(command, dict) and isinstance(command.get("token"), str):
            return command["token"]
        children = value.values()
    elif isinstance(value, list):
        children = value
    else:
        return None
    return next((token for child in children if (token := artist_shelf_continuation(child))), None)


def search_result_types(value):
    counts = {}
    def walk(node):
        if isinstance(node, dict):
            card = node.get("musicCardShelfRenderer")
            if isinstance(card, dict):
                for field in ("title", "subtitle", "onTap", "buttons", "thumbnail", "contents", "header"):
                    if field in card:
                        key = "top_card_" + field
                        counts[key] = counts.get(key, 0) + 1
                tap = card.get("onTap")
                if isinstance(tap, dict):
                    for endpoint in ("watchEndpoint", "browseEndpoint"):
                        if isinstance(tap.get(endpoint), dict):
                            counts["top_card_direct_" + endpoint] = 1
                for field in ("onTap", "title"):
                    value = card.get(field)
                    if find_renderer(value, "watchEndpoint"):
                        counts["top_card_" + field + "_watch"] = 1
                    if find_renderer(value, "browseEndpoint"):
                        counts["top_card_" + field + "_browse"] = 1
            row = node.get("musicResponsiveListItemRenderer")
            if isinstance(row, dict):
                endpoint = row.get("navigationEndpoint", {})
                browse_id = endpoint.get("browseEndpoint", {}).get("browseId", "")
                kind = next((label for prefix, label in (
                    ("MPRE", "album"), ("UC", "artist"), ("VL", "playlist")
                ) if browse_id.startswith(prefix)), "other")
                if kind == "other" and find_renderer(row, "watchEndpoint"):
                    kind = "track"
                counts[kind] = counts.get(kind, 0) + 1
            for child in node.values():
                walk(child)
        elif isinstance(node, list):
            for child in node:
                walk(child)
    walk(value)
    return counts


def library_result_shape(document):
    counts = {}
    collect(document, counts)
    rows = {}
    for renderer in ("musicTwoRowItemRenderer", "musicResponsiveListItemRenderer"):
        path = first_renderer_path(document, renderer)
        if path:
            rows[renderer] = "/".join(path)
    return {
        "counts": counts,
        "row_paths": rows,
        "has_continuation": find_continuation(document) is not None,
    }


def public_release_track(value):
    """Lấy ID video công khai duy nhất từ một playlist phát hành."""
    ids = set()
    def walk(node):
        if isinstance(node, dict):
            item = node.get("musicResponsiveListItemRenderer")
            if isinstance(item, dict):
                info = item.get("playlistItemData", {})
                video_id = info.get("videoId") if isinstance(info, dict) else None
                if isinstance(video_id, str) and len(video_id) == 11:
                    ids.add(video_id)
            for child in node.values():
                walk(child)
        elif isinstance(node, list):
            for child in node:
                walk(child)
    walk(value)
    return next(iter(ids)) if len(ids) == 1 else None


def video_endpoint_types(document, video_id):
    """Đếm loại media, giới hạn theo video ID khi có chỉ định."""
    types = Counter()
    allowed = {
        "MUSIC_VIDEO_TYPE_ATV", "MUSIC_VIDEO_TYPE_OMV",
        "MUSIC_VIDEO_TYPE_UGC", "MUSIC_VIDEO_TYPE_OFFICIAL_SOURCE_MUSIC",
    }

    def walk(node):
        if isinstance(node, dict):
            endpoint = node.get("watchEndpoint")
            if isinstance(endpoint, dict) and (video_id is None or endpoint.get("videoId") == video_id):
                config = endpoint.get("watchEndpointMusicSupportedConfigs", {})
                if isinstance(config, dict):
                    config = config.get("watchEndpointMusicConfig", {})
                    if isinstance(config, dict):
                        kind = config.get("musicVideoType")
                        types[kind if isinstance(kind, str) and kind in allowed else "unknown"] += 1
            for child in node.values():
                walk(child)
        elif isinstance(node, list):
            for child in node:
                walk(child)

    walk(document)
    return dict(types)


def playability_summary(document, requested_id):
    """Tóm tắt khả năng phát công khai của một video; không lưu tiêu đề, URL luồng hay dữ liệu cá nhân."""
    status = document.get("playabilityStatus") if isinstance(document.get("playabilityStatus"), dict) else {}
    details = document.get("videoDetails") if isinstance(document.get("videoDetails"), dict) else {}
    micro = (document.get("microformat") or {}).get("microformatDataRenderer") or {}
    renderer = (document.get("microformat") or {}).get("playerMicroformatRenderer") or {}
    return {
        "status": status.get("status"),
        "reason": status.get("reason"),
        "playable_in_embed": renderer.get("embed") is not None or micro.get("embed") is not None,
        "has_streaming_data": isinstance(document.get("streamingData"), dict),
        "music_video_type": details.get("musicVideoType"),
        "response_video_id_matches_request": details.get("videoId") == requested_id,
        "available_countries": len(renderer.get("availableCountries") or []),
        "error_screen_keys": sorted((status.get("errorScreen") or {}).keys()),
        **stream_shape(document),
    }


def stream_shape(document):
    """Chỉ đếm hình dạng streamingData; không in URL, chữ ký hay thời điểm hết hạn tuyệt đối."""
    streaming = document.get("streamingData")
    if not isinstance(streaming, dict):
        return {"has_hls": False, "format_count": 0, "adaptive_format_count": 0, "has_sabr": False}
    formats = streaming.get("formats")
    adaptive = streaming.get("adaptiveFormats")
    return {
        "has_hls": isinstance(streaming.get("hlsManifestUrl"), str),
        "format_count": len(formats) if isinstance(formats, list) else -1,
        "adaptive_format_count": len(adaptive) if isinstance(adaptive, list) else -1,
        "has_sabr": isinstance(streaming.get("serverAbrStreamingUrl"), str),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-version")
    parser.add_argument("--library-shape-input", type=Path)
    parser.add_argument("--operation", choices=["home", "home-continuation", "search", "artist", "artist-runs", "library-albums", "library-artists", "lyrics-next", "lyrics-browse", "recording-code-player", "recording-code-release", "playability"], default="home")
    parser.add_argument("--video-types", action="store_true")
    parser.add_argument("--album-artist-shape", action="store_true")
    parser.add_argument("--artist-radio", action="store_true")
    parser.add_argument("--search-next", action="store_true")
    parser.add_argument("--search-filter", choices=["all", "songs", "videos", "albums", "artists", "playlists"], default="all")
    parser.add_argument("--query")
    parser.add_argument("--release-playlist-id")
    parser.add_argument("--video-id", default="")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.video_types and args.operation != "lyrics-next":
        parser.error("--video-types chỉ dùng với lyrics-next")
    if args.library_shape_input:
        if args.operation not in ("library-albums", "library-artists"):
            parser.error("--library-shape-input chỉ dùng với library-albums hoặc library-artists")
        if args.library_shape_input.resolve() == args.output.resolve():
            parser.error("Tệp kết quả phải khác tệp đầu vào")
        with args.library_shape_input.open() as capture:
            document = json.load(capture)
        result = {"operation": args.operation, "source": "offline", **library_result_shape(document)}
        args.output.write_text(json.dumps(result, indent=2))
        print(json.dumps(result))
        return
    if not args.client_version:
        parser.error("Probe công khai cần --client-version")
    payload = {"context": {"client": {
        "clientName": "WEB_REMIX", "clientVersion": args.client_version, "hl": "en", "gl": "US"
    }}, "browseId": "FEmusic_home"}
    operation = "browse"
    if args.operation in ("search", "artist", "artist-runs"):
        operation = "search"
        payload.pop("browseId")
        payload["query"] = args.query or ("The Weeknd" if args.operation == "artist" else "Die With A Smile")
    elif args.operation == "recording-code-release":
        import re
        playlist = args.release_playlist_id or ""
        if not re.fullmatch(r"OLAK5uy_[A-Za-z0-9_-]+", playlist):
            parser.error("--release-playlist-id cần mã playlist phát hành công khai")
        payload["browseId"] = "VL" + playlist
    elif args.operation in ("recording-code-player", "playability"):
        if not args.video_id or len(args.video_id) != 11 or not args.video_id.replace("-", "").replace("_", "").isalnum():
            parser.error("--video-id phải là YouTube video ID hợp lệ")
        operation = "player"
        payload.pop("browseId")
        payload["videoId"] = args.video_id
    elif args.operation in ("lyrics-next", "lyrics-browse"):
        if not args.video_id or not args.video_id.replace("-", "").replace("_", "").isalnum():
            parser.error("--video-id phải là YouTube video ID hợp lệ")
        operation = "next"
        payload.pop("browseId")
        payload.update({"videoId": args.video_id, "isAudioOnly": True,
                        "enablePersistentPlaylistPanel": True})
    if args.operation in ("library-albums", "library-artists"):
        payload["browseId"] = {
            "library-albums": "FEmusic_liked_albums",
            "library-artists": "FEmusic_library_corpus_artists",
        }[args.operation]
    if args.operation == "search" and args.search_filter != "all":
        filter_codes = {"songs": "II", "videos": "IQ", "albums": "IY", "artists": "Ig", "playlists": "Io"}
        payload["params"] = f"EgWKAQ{filter_codes[args.search_filter]}AWoMEA4QChADEAQQCRAF"
    request = Request(
        f"https://music.youtube.com/youtubei/v1/{operation}?prettyPrint=false",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com"},
    )
    with urlopen(request, timeout=15) as response:
        document = json.load(response)
    counts = {}
    if args.operation == "playability":
        counts = playability_summary(document, args.video_id)
    elif args.operation == "recording-code-player":
        collect(document.get("microformat"), counts)
        collect(document.get("videoDetails"), counts)
        counts["has_video_details"] = isinstance(document.get("videoDetails"), dict)
        counts["has_microformat"] = isinstance(document.get("microformat"), dict)
        counts["has_playability_status"] = isinstance(document.get("playabilityStatus"), dict)
    else:
        collect(document, counts)
    if args.video_types:
        counts["requested_video_endpoint_types"] = video_endpoint_types(document, args.video_id)
    if args.operation == "recording-code-release":
        counts["release_row_types"] = search_result_types(document)
        counts["single_public_release_video_id"] = public_release_track(document)
    if args.operation == "search":
        counts["search_result_types"] = search_result_types(document)
        if args.search_filter == "videos":
            counts["search_video_endpoint_types"] = video_endpoint_types(document, None)
        for renderer in ("musicCardShelfRenderer", "musicShelfRenderer"):
            path = first_renderer_path(document, renderer)
            if path:
                counts["search_path_" + renderer] = "/".join(path)

    if args.operation == "search" and args.search_next:
        token = find_continuation(document)
        if token:
            encoded = quote(token, safe="")
            request = Request(
                "https://music.youtube.com/youtubei/v1/search?prettyPrint=false"
                f"&ctoken={encoded}&continuation={encoded}",
                data=json.dumps({"context": payload["context"]}).encode(),
                headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com"},
            )
            with urlopen(request, timeout=15) as response:
                next_page = json.load(response)
            next_counts = {}
            collect(next_page, next_counts)
            counts["search_next"] = next_counts
            counts["search_next_types"] = search_result_types(next_page)
            path = first_renderer_path(next_page, "musicResponsiveListItemRenderer")
            if path:
                counts["search_next_row_path"] = "/".join(path)
    if args.operation == "search" and args.album_artist_shape:
        album_id = find_catalog_browse_id(document, "MPRE")
        if album_id:
            album_request = Request(
                "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                data=json.dumps({"context": payload["context"], "browseId": album_id}).encode(),
                headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com"},
            )
            with urlopen(album_request, timeout=15) as response:
                album_document = json.load(response)
            for field in ("subtitle", "straplineTextOne"):
                for renderer in ("musicResponsiveHeaderRenderer", "musicDetailHeaderRenderer", "musicHeaderRenderer"):
                    path = first_renderer_path(album_document, renderer)
                    if path:
                        counts["album_header_path"] = "/".join(path)
                        break
                def count_header_credits(value):
                    if isinstance(value, dict):
                        for name, child in value.items():
                            if name in ("musicResponsiveHeaderRenderer", "musicDetailHeaderRenderer", "musicHeaderRenderer"):
                                runs = child.get(field, {}).get("runs", []) if isinstance(child, dict) else []
                                return sum(
                                    run.get("navigationEndpoint", {}).get("browseEndpoint", {}).get("browseId", "")
                                    .startswith("UC") for run in runs if isinstance(run, dict)
                                )
                        return sum(count_header_credits(child) for child in value.values())
                    if isinstance(value, list):
                        return sum(count_header_credits(child) for child in value)
                    return 0
                counts["album_header_" + field + "_artist_links"] = count_header_credits(album_document)
            count_linked_artist_runs(album_document, counts)
    if args.operation == "artist-runs":
        count_linked_artist_runs(document, counts)
    if args.operation == "home-continuation":
        token_path = first_renderer_path(document, "nextContinuationData")
        if token_path:
            counts["continuation_source_path"] = "/".join(token_path[:12])
        token = find_continuation(document)
        if token:
            encoded = quote(token, safe="")
            next_request = Request(
                "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false"
                f"&ctoken={encoded}&continuation={encoded}",
                data=json.dumps(payload).encode(),
                headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com"},
            )
            with urlopen(next_request, timeout=15) as response:
                next_document = json.load(response)
            counts["continuation_page_loaded"] = 1
            column = next_document.get("contents", {}).get("singleColumnBrowseResultsRenderer")
            if isinstance(column, dict):
                tabs = column.get("tabs")
                if isinstance(tabs, list):
                    counts["continuation_single_column_tabs"] = len(tabs)
                    counts["continuation_single_column_fields"] = [key for key in ("tabs", "contents") if key in column]
                    counts["continuation_tab_renderers"] = sum(
                        isinstance(tab, dict) and isinstance(tab.get("tabRenderer"), dict) for tab in tabs
                    )
                    counts["continuation_tab_has_content"] = sum(
                        bool(isinstance(tab, dict) and isinstance(tab.get("tabRenderer"), dict)
                             and tab["tabRenderer"].get("content"))
                        for tab in tabs
                    )
            for key in ("alerts", "onResponseReceivedActions", "onResponseReceivedCommands"):
                counts["continuation_has_" + key] = key in next_document
            continuation_counts = {}
            collect(next_document, continuation_counts)
            for key, value in continuation_counts.items():
                counts["continuation_" + key] = value
            for key in next_document:
                if key not in ("trackingParams", "responseContext"):
                    counts["continuation_top_" + key] = 1
            continuation_contents = next_document.get("contents")
            if isinstance(continuation_contents, dict):
                for key, value in continuation_contents.items():
                    counts["continuation_contents_" + key] = (
                        len(value) if isinstance(value, list) else 1
                    )
            for key in ("musicTwoRowItemRenderer", "musicCarouselShelfRenderer",
                        "sectionListContinuation", "sectionListRenderer", "musicShelfContinuation",
                        "nextContinuationData", "messageRenderer", "musicDescriptionShelfRenderer"):
                renderer_path = first_renderer_path(next_document, key)
                if renderer_path:
                    counts["continuation_path_" + key] = "/".join(renderer_path[:7])
    if args.operation == "artist":
        browse_id = find_catalog_browse_id(document, "UC")
        if browse_id:
            artist_request = Request(
                "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                data=json.dumps({"context": payload["context"], "browseId": browse_id}).encode(),
                headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com"},
            )
            with urlopen(artist_request, timeout=15) as response:
                artist_document = json.load(response)
            counts["artist_browse_response"] = 1
            collect(artist_document, counts)
            endpoints = list(artist_song_shelf_endpoints(artist_document))
            counts["artist_song_shelf_browse_endpoints"] = len(endpoints)
            if args.artist_radio:
                top_ids = []
                def collect_ids(node, renderer, ids):
                    if isinstance(node, dict):
                        row = node.get(renderer)
                        if isinstance(row, dict):
                            info = row.get("playlistItemData", row)
                            video_id = info.get("videoId") if isinstance(info, dict) else None
                            if isinstance(video_id, str) and video_id not in ids:
                                ids.append(video_id)
                        for child in node.values():
                            collect_ids(child, renderer, ids)
                    elif isinstance(node, list):
                        for child in node:
                            collect_ids(child, renderer, ids)
                collect_ids(artist_document, "musicResponsiveListItemRenderer", top_ids)
                radio_counts = []
                for seed in top_ids[:5]:
                    request = Request(
                        "https://music.youtube.com/youtubei/v1/next?prettyPrint=false",
                        data=json.dumps({"context": payload["context"], "videoId": seed,
                                         "playlistId": "RDAMVM" + seed, "isAudioOnly": True}).encode(),
                        headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com"},
                    )
                    with urlopen(request, timeout=15) as response:
                        radio = json.load(response)
                    ids = []
                    collect_ids(radio, "playlistPanelVideoRenderer", ids)
                    radio_counts.append(len(set(ids) - set(top_ids[:5])))
                counts["artist_radio_unique_outside_top_five"] = radio_counts

            if endpoints:
                endpoint = endpoints[0]
                body = {"context": payload["context"], "browseId": endpoint["browseId"]}
                if isinstance(endpoint.get("params"), str):
                    body["params"] = endpoint["params"]
                shelf_request = Request(
                    "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                    data=json.dumps(body).encode(),
                    headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com"},
                )
                with urlopen(shelf_request, timeout=15) as response:
                    shelf_document = json.load(response)
                shelf_counts = {}
                collect(shelf_document, shelf_counts)
                counts["artist_expanded_shelf"] = shelf_counts
                token = artist_shelf_continuation(shelf_document)
                if token:
                    next_request = Request(
                        "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                        data=json.dumps({"context": payload["context"], "continuation": token}).encode(),
                        headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com"},
                    )
                    with urlopen(next_request, timeout=15) as response:
                        next_document = json.load(response)
                    next_counts = {}
                    collect(next_document, next_counts)
                    counts["artist_expanded_continuation"] = next_counts
            for key in ("sectionListRenderer", "musicCarouselShelfRenderer", "musicShelfRenderer"):
                renderer_path = first_renderer_path(artist_document, key)
                if renderer_path:
                    counts["artist_path_" + key] = "/".join(renderer_path[:12])
    if args.operation == "lyrics-browse":
        browse_id = find_lyrics_browse_id(document)
        if browse_id:
            browse_request = Request(
                "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                data=json.dumps({"context": payload["context"], "browseId": browse_id}).encode(),
                headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com"},
            )
            with urlopen(browse_request, timeout=15) as response:
                browse_document = json.load(response)
            collect(browse_document, counts)
    result = {"authenticated": False, "operation": args.operation, "counts": counts}
    args.output.write_text(json.dumps(result, indent=2))
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError):
        raise SystemExit("Probe public không hoàn tất; chưa có bằng chứng shape. Không lưu payload.")
