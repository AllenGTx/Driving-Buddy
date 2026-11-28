"""Pencarian Web/Google Real-Time Gratis & Streaming Lagu Penuh untuk Dynamic Island.

Mendukung:
1. Pertanyaan umum & cek fakta berita terkini (mis. politik, viral, peristiwa hari ini/kemarin)
2. Skor sepak bola / olahraga terkini (mis. Man United vs Sporting Lisbon)
3. Pencarian daftar lagu resmi (antrean playlist 5 lagu + sampul HD) dan resolusi audio stream penuh
   tanpa pernah memaksa pengguna keluar dari aplikasi Driving Buddy ke halaman pencarian Spotify.
"""
from __future__ import annotations

import asyncio
import html
import logging
import re
import time
import urllib.parse
import xml.etree.ElementTree as ET
from typing import Any, AsyncIterator, Dict, List, Optional, Tuple

import httpx

log = logging.getLogger("driving_buddy.search")

_SEARCH_TRIGGER_PATTERNS = re.compile(
    r"\b(?:"
    r"cari\s+di\s+google|cari\s+tau|cari\s+tahu|coba\s+cari|tolong\s+cari|googling|search|"
    r"apakah\s+benar|bener\s+ga|bener\s+gak|benar\s+tidak|hoaks|hoax|cek\s+fakta|fakta\s+atau|"
    r"berita|kabar\s+terbaru|viral|isu\s+|gosip|melengserkan|lengser|pemilu|presiden|wapres|menteri|prabowo|gibran|"
    r"skor|hasil\s+pertandingan|pertandingan|lawan|vs|versus|klasemen|liga\s+champions|premier\s+league|timnas|"
    r"man\s+united|manchester|sporting|real\s+madrid|barcelona|arsenal|liverpool|chelsea|juventus|milan|inter|persib|persija|"
    r"kemarin|tadi\s+malam|semalam|hari\s+ini|minggu\s+ini|bulan\s+ini|tahun\s+202[4-9]|terbaru|sekarang\s+siapa|"
    r"harga\s+|kurs\s+|rupiah|dollar|bitcoin|emas\s+hari\s+ini|cuaca\s+di|jadwal\s+"
    r")\b",
    re.IGNORECASE,
)

# Jangan picu web search untuk perintah navigasi lokal atau pemutar musik
_LOCAL_ACTION_EXCLUDE = re.compile(
    r"\b(?:indomaret|alfamart|alfamidi|spbu|pertamina|rest\s+area|tempat\s+istirahat|hotel\s+terdekat|"
    r"arahkan\s+saya|buka\s+google\s+map|setelkan\s+lagu|putar\s+lagu|play\s+lagu|ganti\s+lagu|hentikan\s+lagu|stop\s+lagu)\b",
    re.IGNORECASE,
)

_STRIP_SEARCH_PREFIX = re.compile(
    r"^(?:tolong\s+|coba\s+|eh\s+|rina\s+|jane\s+|john\s+|furina\s+)*"
    r"(?:cari(?:kan)?\s+di\s+google|coba\s+cari(?:\s+tau|\s+tahu)?|tolong\s+cari(?:kan)?|"
    r"aku\s+penasaran(?:\s+nih)?)\s*[,:]?\s*",
    re.IGNORECASE,
)

_SC_CLIENT_ID: Optional[str] = None
_SC_CLIENT_ID_AT: float = 0.0
_STREAM_META_CACHE: Dict[str, Tuple[float, Dict[str, Any]]] = {}


def needs_live_web_search(message: str) -> bool:
    text = (message or "").strip()
    if len(text) < 6:
        return False
    if _LOCAL_ACTION_EXCLUDE.search(text):
        return False
    return bool(_SEARCH_TRIGGER_PATTERNS.search(text))


def extract_clean_search_query(message: str) -> str:
    cleaned = _STRIP_SEARCH_PREFIX.sub("", (message or "").strip()).strip(" ?!.,")
    return cleaned if len(cleaned) >= 3 else message.strip()


def _strip_html(raw: str) -> str:
    if not raw:
        return ""
    txt = html.unescape(re.sub(r"<[^>]+>", " ", raw))
    return re.sub(r"\s+", " ", txt).strip()


async def _fetch_google_news_rss(client: httpx.AsyncClient, query: str, hl: str = "id", gl: str = "ID") -> List[str]:
    ceid = f"{gl}:{hl}"
    url = f"https://news.google.com/rss/search?q={urllib.parse.quote(query)}&hl={hl}&gl={gl}&ceid={ceid}"
    try:
        resp = await client.get(url)
        if resp.status_code != 200:
            return []
        root = ET.fromstring(resp.content)
        out: List[str] = []
        for item in root.findall(".//item")[:5]:
            title = _strip_html(item.findtext("title") or "")
            pub = (item.findtext("pubDate") or "")[:16].strip()
            desc = _strip_html(item.findtext("description") or "")
            extra = f" — {desc}" if desc and desc[:35].lower() not in title.lower() else ""
            if title:
                out.append(f"[{pub}] {title}{extra}"[:240])
        return out
    except Exception as exc:
        log.debug("[WebSearch] Google News RSS gagal: %s", exc)
        return []


async def _fetch_bing_rss(client: httpx.AsyncClient, query: str) -> List[str]:
    url = f"https://www.bing.com/search?q={urllib.parse.quote(query)}&format=rss"
    try:
        resp = await client.get(url)
        if resp.status_code != 200:
            return []
        root = ET.fromstring(resp.content)
        out: List[str] = []
        for item in root.findall(".//item")[:4]:
            title = _strip_html(item.findtext("title") or "")
            desc = _strip_html(item.findtext("description") or "")
            if title and "kamus besar bahasa indonesia" not in title.lower():
                out.append(f"{title}: {desc}"[:240])
        return out
    except Exception as exc:
        log.debug("[WebSearch] Bing RSS gagal: %s", exc)
        return []


async def _fetch_wikipedia_summary(client: httpx.AsyncClient, query: str) -> List[str]:
    url = (
        "https://id.wikipedia.org/w/api.php?action=query&list=search"
        f"&srsearch={urllib.parse.quote(query)}&utf8=1&format=json&srlimit=2"
    )
    try:
        resp = await client.get(url)
        if resp.status_code != 200:
            return []
        items = (resp.json().get("query") or {}).get("search") or []
        out: List[str] = []
        for it in items[:2]:
            title = _strip_html(it.get("title") or "")
            snip = _strip_html(it.get("snippet") or "")
            if title and snip:
                out.append(f"[Wikipedia: {title}] {snip}"[:220])
        return out
    except Exception:
        return []


async def search_live_web(raw_message: str, timeout_s: float = 2.0) -> Optional[str]:
    """Ambil ringkasan fakta real-time dari Google News ID/Global + Bing Web + Wikipedia dalam <2 detik."""
    query = extract_clean_search_query(raw_message)
    if not query:
        return None

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36",
        "Accept-Language": "id-ID,id;q=0.9,en-US;q=0.8",
    }
    is_sports = bool(re.search(r"\b(?:skor|vs|versus|lawan|pertandingan|united|sporting|madrid|barca|liga)\b", query, re.I))

    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(timeout_s, connect=1.0), headers=headers, follow_redirects=True) as client:
            tasks = [
                _fetch_google_news_rss(client, query, hl="id", gl="ID"),
                _fetch_bing_rss(client, query),
            ]
            if is_sports:
                tasks.append(_fetch_google_news_rss(client, f"{query} score result", hl="en", gl="US"))
            else:
                tasks.append(_fetch_wikipedia_summary(client, query))

            results = await asyncio.gather(*tasks, return_exceptions=True)
    except Exception as exc:
        log.debug("[WebSearch] Gagal menjalankan pencarian paralel: %s", exc)
        return None

    merged: List[str] = []
    seen_lower: set[str] = set()
    for group in results:
        if isinstance(group, list):
            for row in group:
                key = row[:55].lower()
                if key not in seen_lower:
                    seen_lower.add(key)
                    merged.append(row)
                if len(merged) >= 6:
                    break
        if len(merged) >= 6:
            break

    if not merged:
        return None

    return (
        "HASIL PENCARIAN GOOGLE & BERITA TERKINI REAL-TIME (gunakan fakta di bawah ini untuk menjawab secara akurat; "
        "jika berita berupa rumor/klaim belum terbukti, sampaikan jujur bahwa di berita itu masih isu/belum ada bukti resmi):\n- "
        + "\n- ".join(merged)
    )


def _clean_music_query(query: str) -> str:
    clean_q = re.sub(r"\b(?:by|oleh|dari|lagu|song|musik|music|spotify)\b", " ", (query or ""), flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", clean_q).strip()


async def search_music_track(query: str, timeout_s: float = 3.8) -> Dict[str, Any]:
    """Cari lagu resmi + antrean playlist (hingga 5 lagu terkait) untuk Dynamic Island in-app."""
    clean_q = _clean_music_query(query)
    if not clean_q:
        return {"found": False, "tracks": []}

    headers = {"User-Agent": "DrivingBuddy/1.0"}
    tracks: List[Dict[str, Any]] = []

    async with httpx.AsyncClient(timeout=httpx.Timeout(timeout_s, connect=1.5), headers=headers, follow_redirects=True) as client:
        # 1. iTunes Search API (sampul HD resmi + durasi studio akurat + daftar lagu terkait untuk tombol Next/Prev)
        try:
            it_url = f"https://itunes.apple.com/search?term={urllib.parse.quote(clean_q)}&media=music&entity=song&limit=6"
            it_resp = await client.get(it_url)
            if it_resp.status_code == 200:
                items = it_resp.json().get("results") or []
                seen_keys: set[str] = set()
                for it in items:
                    title = (it.get("trackName") or "").strip()
                    artist = (it.get("artistName") or "Spotify").strip()
                    if not title:
                        continue
                    dedup = f"{title.lower()}::{artist.lower()}"
                    if dedup in seen_keys:
                        continue
                    seen_keys.add(dedup)
                    art = (it.get("artworkUrl100") or "").replace("100x100bb", "300x300bb")
                    dur_s = max(30, int((it.get("trackTimeMillis") or 210000) / 1000))
                    sp_q = f"{title} {artist}".strip()
                    tracks.append(
                        {
                            "title": title,
                            "artist": artist,
                            "album": it.get("collectionName") or "",
                            "cover_url": art,
                            "preview_url": it.get("previewUrl") or "",
                            "duration_s": dur_s,
                            "spotify_query": sp_q,
                            "stream_path": f"/music/stream?q={urllib.parse.quote(sp_q)}&dur={dur_s}",
                        }
                    )
                    if len(tracks) >= 5:
                        break
        except Exception:
            pass

        # 2. Fallback Deezer Public Search API bila iTunes kosong
        if not tracks:
            try:
                dz_url = f"https://api.deezer.com/search?q={urllib.parse.quote(clean_q)}&limit=6"
                dz_resp = await client.get(dz_url)
                if dz_resp.status_code == 200:
                    items = dz_resp.json().get("data") or []
                    seen_keys = set()
                    for it in items:
                        title = (it.get("title") or "").strip()
                        artist = ((it.get("artist") or {}).get("name") or "Spotify").strip()
                        if not title:
                            continue
                        dedup = f"{title.lower()}::{artist.lower()}"
                        if dedup in seen_keys:
                            continue
                        seen_keys.add(dedup)
                        album_obj = it.get("album") or {}
                        dur_s = max(30, int(it.get("duration") or 210))
                        sp_q = f"{title} {artist}".strip()
                        tracks.append(
                            {
                                "title": title,
                                "artist": artist,
                                "album": album_obj.get("title") or "",
                                "cover_url": album_obj.get("cover_medium") or album_obj.get("cover") or "",
                                "preview_url": it.get("preview") or "",
                                "duration_s": dur_s,
                                "spotify_query": sp_q,
                                "stream_path": f"/music/stream?q={urllib.parse.quote(sp_q)}&dur={dur_s}",
                            }
                        )
                        if len(tracks) >= 5:
                            break
            except Exception:
                pass

    if tracks:
        best = dict(tracks[0])
        best["found"] = True
        best["tracks"] = tracks
        return best

    fallback_track = {
        "title": clean_q.title(),
        "artist": "Music Stream",
        "album": "",
        "cover_url": "",
        "preview_url": "",
        "duration_s": 210,
        "spotify_query": clean_q,
        "stream_path": f"/music/stream?q={urllib.parse.quote(clean_q)}&dur=210",
    }
    return {
        "found": True,
        **fallback_track,
        "tracks": [fallback_track],
    }


async def _get_soundcloud_client_id(client: httpx.AsyncClient) -> Optional[str]:
    global _SC_CLIENT_ID, _SC_CLIENT_ID_AT
    now = time.monotonic()
    if _SC_CLIENT_ID and (now - _SC_CLIENT_ID_AT) < 3600.0:
        return _SC_CLIENT_ID

    try:
        home = await client.get("https://soundcloud.com")
        if home.status_code != 200:
            return _SC_CLIENT_ID
        scripts = re.findall(r'src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"', home.text)
        for s_url in reversed(scripts[-5:]):
            js_resp = await client.get(s_url)
            if js_resp.status_code != 200:
                continue
            m = re.search(r'client_id\s*:\s*"([a-zA-Z0-9]{28,36})"', js_resp.text) or re.search(
                r'client_id="([a-zA-Z0-9]{28,36})"', js_resp.text
            )
            if m:
                _SC_CLIENT_ID = m.group(1)
                _SC_CLIENT_ID_AT = now
                return _SC_CLIENT_ID
    except Exception as exc:
        log.debug("[MusicStream] Gagal mengambil SoundCloud client_id: %s", exc)
    return _SC_CLIENT_ID


def _resolve_ytdlp_sync(query: str, target_dur_s: int = 210) -> Optional[Dict[str, Any]]:
    """Coba ekstrak URL audio m4a/mp3 studio penuh via yt-dlp jika diizinkan jaringan server."""
    try:
        import yt_dlp  # type: ignore
    except Exception:
        return None

    ydl_opts = {
        "format": "bestaudio[ext=m4a][abr<=160]/bestaudio[ext=mp4]/bestaudio[protocol^=http][ext!=webm]/bestaudio",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 4,
        "extract_flat": False,
    }
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f"ytsearch2:{query} official audio", download=False)
            entries = (info or {}).get("entries") or []
            for ent in entries:
                if not ent:
                    continue
                u = ent.get("url") or ""
                dur = int(ent.get("duration") or 0)
                ext = (ent.get("ext") or "m4a").lower()
                if u.startswith("http") and 60 <= dur <= 720 and "manifest.googlevideo.com" not in u:
                    mime = "audio/mpeg" if ext == "mp3" else "audio/mp4"
                    return {
                        "mode": "direct_url",
                        "url": u,
                        "mime": mime,
                        "headers": ent.get("http_headers") or {},
                        "duration_s": dur,
                    }
    except Exception as exc:
        log.debug("[MusicStream] yt-dlp dilewati: %s", exc)
    return None


async def _resolve_soundcloud_full_stream(
    client: httpx.AsyncClient,
    query: str,
    target_dur_s: int = 210,
) -> Optional[Dict[str, Any]]:
    """Resolusi lagu utuh penuh (2–6 menit) via SoundCloud v2: Progressive MP3 atau CMAF fMP4 160kbps."""
    cid = await _get_soundcloud_client_id(client)
    if not cid:
        return None

    q_low = query.lower()
    wants_sped = "sped" in q_low or "nightcore" in q_low
    wants_remix = "remix" in q_low or "dj" in q_low

    search_url = (
        f"https://api-v2.soundcloud.com/search/tracks?q={urllib.parse.quote(query)}"
        f"&client_id={cid}&limit=16"
    )
    resp = await client.get(search_url)
    if resp.status_code != 200:
        return None

    candidates: List[Tuple[float, Dict[str, Any]]] = []
    for tr in resp.json().get("collection") or []:
        if tr.get("policy") == "SNIP":
            continue
        dur_ms = int(tr.get("duration") or 0)
        dur_s = dur_ms // 1000
        # Pastikan lagu utuh penuh (>= 85 detik, <= 11 menit), bukan cuplikan 30 detik
        if dur_s < 85 or dur_s > 660:
            continue
        tcs = tr.get("media", {}).get("transcodings") or []
        if not tcs:
            continue

        title_low = (tr.get("title") or "").lower()
        score = 100.0
        # Prioritaskan durasi yang paling dekat dengan rekaman studio asli
        if target_dur_s > 45:
            score -= min(45.0, abs(dur_s - target_dur_s) * 0.42)
        if not wants_sped and any(w in title_low for w in ("sped up", "nightcore", "slowed", "8d audio", "chipmunk")):
            score -= 28.0
        if not wants_remix and any(w in title_low for w in ("remix", "bootleg", "dj ", "karaoke", "instrumental")):
            score -= 24.0
        if "cover" in title_low and "cover" not in q_low:
            score -= 10.0

        has_prog = any(
            tc.get("format", {}).get("protocol") == "progressive" and not tc.get("snipped")
            for tc in tcs
        )
        if has_prog:
            score += 8.0
        candidates.append((score, tr))

    candidates.sort(key=lambda pair: pair[0], reverse=True)

    for _, tr in candidates[:4]:
        tcs = tr.get("media", {}).get("transcodings") or []
        dur_s = max(60, int((tr.get("duration") or 210000) // 1000))

        # 1) Utamakan Progressive MP3 langsung bila tersedia
        for tc in tcs:
            fmt = tc.get("format") or {}
            if fmt.get("protocol") == "progressive" and not tc.get("snipped"):
                sep = "&" if "?" in tc.get("url", "") else "?"
                r = await client.get(f"{tc['url']}{sep}client_id={cid}")
                if r.status_code == 200:
                    mp3_url = r.json().get("url") or ""
                    if mp3_url.startswith("http"):
                        return {
                            "mode": "direct_url",
                            "url": mp3_url,
                            "mime": "audio/mpeg",
                            "headers": {},
                            "duration_s": dur_s,
                        }

        # 2) Gunakan HLS CMAF fMP4 (init.mp4 + data*.m4s) yang disatukan mulus sebagai audio/mp4 utuh!
        for tc in tcs:
            fmt = tc.get("format") or {}
            mime = fmt.get("mime_type") or ""
            if not tc.get("snipped") and "mp4" in mime:
                sep = "&" if "?" in tc.get("url", "") else "?"
                r = await client.get(f"{tc['url']}{sep}client_id={cid}")
                if r.status_code != 200:
                    continue
                m3u8_url = r.json().get("url") or ""
                if not m3u8_url.startswith("http"):
                    continue
                m3u8_resp = await client.get(m3u8_url)
                if m3u8_resp.status_code != 200:
                    continue
                m3u8_txt = m3u8_resp.text
                map_match = re.search(r'#EXT-X-MAP:URI="([^"]+)"', m3u8_txt)
                seg_urls = [
                    ln.strip()
                    for ln in m3u8_txt.splitlines()
                    if ln.strip().startswith("http")
                ]
                if map_match and seg_urls:
                    all_parts = [map_match.group(1), *seg_urls]
                    return {
                        "mode": "fmp4_segments",
                        "segments": all_parts,
                        "mime": "audio/mp4",
                        "duration_s": dur_s,
                    }
    return None


async def resolve_in_app_music_stream(query: str, target_dur_s: int = 210) -> Optional[Dict[str, Any]]:
    """Resolusi sumber audio terbaik untuk diputar otomatis di dalam Dynamic Island (0 perpindahan layar)."""
    clean_q = _clean_music_query(query)
    if not clean_q:
        return None

    cache_key = f"{clean_q.lower()}::{target_dur_s}"
    cached = _STREAM_META_CACHE.get(cache_key)
    now = time.monotonic()
    if cached and (now - cached[0]) < 300.0:
        return cached[1]

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36",
    }

    # 1. Coba yt-dlp (rekaman studio YouTube Audio) secara paralel dengan SoundCloud Full Track
    async with httpx.AsyncClient(timeout=httpx.Timeout(6.5, connect=2.0), headers=headers, follow_redirects=True) as client:
        sc_task = asyncio.create_task(_resolve_soundcloud_full_stream(client, clean_q, target_dur_s=target_dur_s))
        yt_task = asyncio.to_thread(_resolve_ytdlp_sync, clean_q, target_dur_s)

        yt_res, sc_res = await asyncio.gather(yt_task, sc_task, return_exceptions=True)

        chosen: Optional[Dict[str, Any]] = None
        if isinstance(yt_res, dict) and yt_res.get("url"):
            # Verifikasi cepat apakah URL googlevideo tidak diblokir IP server (HTTP 200/206)
            try:
                probe_headers = dict(yt_res.get("headers") or {})
                probe_headers["Range"] = "bytes=0-1023"
                probe = await client.get(yt_res["url"], headers=probe_headers)
                if probe.status_code in (200, 206):
                    chosen = yt_res
            except Exception:
                chosen = None

        if chosen is None and isinstance(sc_res, dict):
            chosen = sc_res

        # 3. Fallback ke preview jernih iTunes/Deezer bila jaringan penuh
        if chosen is None:
            meta = await search_music_track(clean_q, timeout_s=3.0)
            prev = (meta.get("preview_url") or "").strip()
            if prev.startswith("http"):
                chosen = {
                    "mode": "direct_url",
                    "url": prev,
                    "mime": "audio/mp4" if ".m4a" in prev.lower() else "audio/mpeg",
                    "headers": {},
                    "duration_s": 30,
                }

    if chosen is not None:
        _STREAM_META_CACHE[cache_key] = (now, chosen)
        if len(_STREAM_META_CACHE) > 96:
            oldest = min(_STREAM_META_CACHE, key=lambda k: _STREAM_META_CACHE[k][0])
            _STREAM_META_CACHE.pop(oldest, None)
    return chosen


async def iter_resolved_music_bytes(stream_info: Dict[str, Any]) -> AsyncIterator[bytes]:
    """Alirkan byte audio secara berkesinambungan ke AudioPlayer Dynamic Island."""
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36",
    }
    extra_headers = stream_info.get("headers") or {}
    merged_headers = {**headers, **extra_headers}

    mode = stream_info.get("mode")
    async with httpx.AsyncClient(
        timeout=httpx.Timeout(25.0, connect=4.0),
        headers=merged_headers,
        follow_redirects=True,
    ) as client:
        if mode == "direct_url":
            url = stream_info["url"]
            async with client.stream("GET", url) as resp:
                resp.raise_for_status()
                async for chunk in resp.aiter_bytes(chunk_size=32768):
                    if chunk:
                        yield chunk
        elif mode == "fmp4_segments":
            segments: List[str] = stream_info.get("segments") or []
            for seg_url in segments:
                resp = await client.get(seg_url)
                if resp.status_code in (200, 206) and resp.content:
                    yield resp.content
