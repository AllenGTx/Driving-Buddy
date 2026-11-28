"""Pencarian Web/Google Real-Time Gratis & Streaming Lagu Penuh untuk Dynamic Island.

Mendukung:
1. Pertanyaan umum & cek fakta berita terkini (mis. politik, viral, peristiwa hari ini/kemarin)
2. Skor olahraga real-time: sepak bola, basket NBA, Formula 1, bulu tangkis, e-sport MPL/MLBB/VALORANT/Dota,
   Olimpiade, SEA Games, tinju/MMA, tenis, dan turnamen apa pun yang bisa dicari di ESPN/Google/Bing.
3. Pencarian daftar lagu resmi (antrean playlist 5 lagu + sampul HD) dan resolusi audio stream penuh
   tanpa pernah memaksa pengguna keluar dari aplikasi Driving Buddy ke halaman pencarian Spotify.
"""
from __future__ import annotations

import asyncio
import datetime as dt
import html
import logging
import re
import time
import unicodedata
import urllib.parse
import xml.etree.ElementTree as ET
from typing import Any, AsyncIterator, Dict, List, Optional, Tuple

import httpx

log = logging.getLogger("driving_buddy.search")

_SEARCH_TRIGGER_PATTERNS = re.compile(
    r"\b(?:"
    r"cari\s+di\s+google|cari\s+tau|cari\s+tahu|coba\s+cari|tolong\s+cari|googling|search|"
    r"apakah\s+benar|bener\s+ga|bener\s+gak|benar\s+tidak|hoaks|hoax|cek\s+fakta|fakta\s+atau|fakta\s+sejarah|\bsejarah\b|"
    r"berita|kabar\s+terbaru|viral|isu\s+|gosip|melengserkan|lengser|pemilu|presiden|wapres|menteri|prabowo|gibran|"
    # Sepak bola
    r"skor|berapa\s+skor|hasil\s+pertandingan|menang\s+berapa|kalah\s+berapa|pertandingan|lawan|vs|versus|klasemen|"
    r"liga\s+champions|premier\s+league|liga\s+inggris|timnas|ucl|europa\s+league|la\s+liga|serie\s+a|bundesliga|"
    r"man\s+united|man\s+utd|man\s+u|mu\b|manchester|sporting|real\s+madrid|barcelona|barca|arsenal|liverpool|chelsea|"
    r"juventus|milan|inter|bayern|psg|tottenham|persib|persija|arema|bali\s+united|psm|timnas|"
    # Basket NBA
    r"nba|lakers|celtics|warriors|bulls|heat|suns|nuggets|bucks|nets|knicks|"
    r"lebron|curry|durant|giannis|jokic|doncic|ibl\s+basket|"
    # E-sport & Gaming
    r"mpl|mobile\s+legends|mlbb|rrq|evos|onic|alter\s+ego|aura|bigetron|"
    r"valorant|vct|dota\s+2|the\s+international|csgo|cs2|pubg|free\s+fire|ffws|"
    r"league\s+of\s+legends|lol|worlds|lck|lpl|t1\b|esport|e-sport|turnamen|"
    # Formula 1 & balap
    r"formula\s+1|f1|grand\s+prix|gp\s+\w+|verstappen|hamilton|leclerc|norris|sainz|alonso|"
    r"red\s+bull|ferrari|mercedes|mclaren|"
    # Olimpiade & olahraga lain
    r"olimpiade|asian\s+games|sea\s+games|paralimpik|medali|"
    r"bulu\s+tangkis|bulutangkis|kevin\s+sanjaya|ginting|jonatan|"
    r"tenis|wimbledon|us\s+open|french\s+open|australian\s+open|grand\s+slam|"
    r"tinju|mma|ufc|one\s+championship|boxing|"
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


_MONTH_MAP = {
    "jan": 1, "januari": 1, "january": 1,
    "feb": 2, "februari": 2, "february": 2, "peb": 2,
    "mar": 3, "maret": 3, "march": 3,
    "apr": 4, "april": 4,
    "mei": 5, "may": 5,
    "jun": 6, "juni": 6, "june": 6,
    "jul": 7, "juli": 7, "july": 7,
    "agu": 8, "ags": 8, "agustus": 8, "aug": 8, "august": 8,
    "sep": 9, "sept": 9, "september": 9,
    "okt": 10, "oktober": 10, "oct": 10, "october": 10,
    "nov": 11, "november": 11, "nop": 11,
    "des": 12, "desember": 12, "dec": 12, "december": 12,
}

_TEAM_ALIASES = (
    # Sepak bola — Premier League
    (re.compile(r"\b(?:manchester\s+united|man\s+united|man\s+utd|man\s+u|mufc|mu)\b", re.I), "Manchester United", ("manchester united", "man utd", "man united")),
    (re.compile(r"\b(?:manchester\s+city|man\s+city|mcfc)\b", re.I), "Manchester City", ("manchester city", "man city")),
    (re.compile(r"\bliverpool\b", re.I), "Liverpool", ("liverpool",)),
    (re.compile(r"\barsenal\b", re.I), "Arsenal", ("arsenal",)),
    (re.compile(r"\bchelsea\b", re.I), "Chelsea", ("chelsea",)),
    (re.compile(r"\b(?:tottenham|spurs)\b", re.I), "Tottenham", ("tottenham", "spurs")),
    (re.compile(r"\bnewcastle\b", re.I), "Newcastle", ("newcastle",)),
    (re.compile(r"\b(?:aston\s+villa|villa)\b", re.I), "Aston Villa", ("aston villa",)),
    # Sepak bola — La Liga
    (re.compile(r"\b(?:real\s+madrid|madrid)\b", re.I), "Real Madrid", ("real madrid",)),
    (re.compile(r"\b(?:barcelona|barca|fcb)\b", re.I), "Barcelona", ("barcelona",)),
    (re.compile(r"\b(?:atletico\s+madrid|atletico)\b", re.I), "Atletico Madrid", ("atletico madrid",)),
    # Sepak bola — Eropa lain
    (re.compile(r"\bsporting\b", re.I), "Sporting", ("sporting",)),
    (re.compile(r"\bbayern\b", re.I), "Bayern Munich", ("bayern",)),
    (re.compile(r"\b(?:borussia\s+dortmund|dortmund|bvb)\b", re.I), "Borussia Dortmund", ("dortmund",)),
    (re.compile(r"\b(?:inter\s+milan|inter)\b", re.I), "Inter", ("inter",)),
    (re.compile(r"\b(?:ac\s+milan|milan)\b", re.I), "AC Milan", ("milan",)),
    (re.compile(r"\bjuventus\b", re.I), "Juventus", ("juventus",)),
    (re.compile(r"\bnapoli\b", re.I), "Napoli", ("napoli",)),
    (re.compile(r"\b(?:psg|paris\s+saint.germain)\b", re.I), "PSG", ("psg", "paris saint-germain")),
    (re.compile(r"\b(?:ajax)\b", re.I), "Ajax", ("ajax",)),
    (re.compile(r"\b(?:porto)\b", re.I), "Porto", ("porto",)),
    # Sepak bola — Indonesia
    (re.compile(r"\bpersib\b", re.I), "Persib", ("persib",)),
    (re.compile(r"\bpersija\b", re.I), "Persija", ("persija",)),
    (re.compile(r"\barema\b", re.I), "Arema", ("arema",)),
    (re.compile(r"\bbali\s+united\b", re.I), "Bali United", ("bali united",)),
    (re.compile(r"\bpsm\b", re.I), "PSM Makassar", ("psm",)),
    (re.compile(r"\btimnas(?:\s+indonesia)?\b", re.I), "Indonesia", ("indonesia",)),
    # NBA Basketball
    (re.compile(r"\b(?:lakers|los\s+angeles\s+lakers)\b", re.I), "Lakers", ("lakers",)),
    (re.compile(r"\b(?:celtics|boston\s+celtics)\b", re.I), "Celtics", ("celtics",)),
    (re.compile(r"\b(?:warriors|golden\s+state)\b", re.I), "Warriors", ("warriors",)),
    (re.compile(r"\b(?:bulls|chicago\s+bulls)\b", re.I), "Bulls", ("bulls",)),
    (re.compile(r"\b(?:heat|miami\s+heat)\b", re.I), "Heat", ("heat",)),
    (re.compile(r"\b(?:suns|phoenix\s+suns)\b", re.I), "Suns", ("suns",)),
    (re.compile(r"\b(?:nuggets|denver\s+nuggets)\b", re.I), "Nuggets", ("nuggets",)),
    (re.compile(r"\b(?:bucks|milwaukee\s+bucks)\b", re.I), "Bucks", ("bucks",)),
    (re.compile(r"\b(?:knicks|new\s+york\s+knicks)\b", re.I), "Knicks", ("knicks",)),
    # Formula 1 (driver bukan tim, tapi berguna untuk matching)
    (re.compile(r"\bverstappen\b", re.I), "Max Verstappen", ("verstappen",)),
    (re.compile(r"\blewis\s+hamilton\b", re.I), "Lewis Hamilton", ("hamilton",)),
    (re.compile(r"\bleclerc\b", re.I), "Charles Leclerc", ("leclerc",)),
    # E-sport MPL / Mobile Legends
    (re.compile(r"\b(?:rrq|rrq\s+hoshi)\b", re.I), "RRQ Hoshi", ("rrq",)),
    (re.compile(r"\b(?:evos|evos\s+legends)\b", re.I), "EVOS Legends", ("evos",)),
    (re.compile(r"\b(?:onic|onic\s+esports)\b", re.I), "ONIC Esports", ("onic",)),
    (re.compile(r"\b(?:alter\s+ego)\b", re.I), "Alter Ego", ("alter ego",)),
    (re.compile(r"\b(?:aura|aura\s+fire)\b", re.I), "Aura Fire", ("aura",)),
    # Bulu Tangkis
    (re.compile(r"\bkevin\s+sanjaya\b", re.I), "Kevin Sanjaya", ("kevin sanjaya",)),
    (re.compile(r"\bginting\b", re.I), "Anthony Ginting", ("ginting",)),
    (re.compile(r"\bjonatan\s+christie\b", re.I), "Jonatan Christie", ("jonatan",)),
)


def _normalize_sports_query(query: str) -> str:
    """Normalisasi alias tim/atlet umum agar pencarian Google News lebih akurat."""
    out = re.sub(r"\b(?:man\s+u|mu)\b", "Manchester United", query, flags=re.I)
    out = re.sub(r"\bman\s+united\b", "Manchester United", out, flags=re.I)
    out = re.sub(r"\bman\s+city\b", "Manchester City", out, flags=re.I)
    out = re.sub(r"\bbarca\b", "Barcelona", out, flags=re.I)
    out = re.sub(r"\b(?:spurs)\b", "Tottenham", out, flags=re.I)
    out = re.sub(r"\b(?:bvb|dortmund)\b", "Borussia Dortmund", out, flags=re.I)
    out = re.sub(r"\b(?:psg)\b", "Paris Saint-Germain", out, flags=re.I)
    out = re.sub(r"\b(?:lakers)\b", "Los Angeles Lakers", out, flags=re.I)
    out = re.sub(r"\b(?:warriors)\b", "Golden State Warriors", out, flags=re.I)
    out = re.sub(r"\bformula\s+(?:satu|one)\b", "Formula 1", out, flags=re.I)
    out = re.sub(r"\b(?:mlbb|mobile\s+legends)\b", "Mobile Legends MLBB", out, flags=re.I)
    out = re.sub(r"\bmpl\s+id\b", "MPL Indonesia", out, flags=re.I)
    out = re.sub(r"\b(?:bulutangkis|bulu\s+tangkis)\b", "badminton", out, flags=re.I)
    return re.sub(r"\s+", " ", out).strip()


def _extract_sports_dates_ymd(query: str, today: Optional[dt.date] = None) -> List[str]:
    base_today = today or (dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=7)).date()
    low = query.lower()
    dates: List[str] = []

    # 1) Tanggal eksplisit mis. "22 nov", "22 november", "22 november 2026"
    m = re.search(
        r"\b(\d{1,2})\s+(jan|januari|january|feb|februari|february|peb|mar|maret|march|apr|april|mei|may|jun|juni|june|jul|juli|july|agu|ags|agustus|aug|august|sep|sept|september|okt|oktober|oct|october|nov|november|nop|des|desember|dec|december)(?:\s+(20\d{2}))?\b",
        low,
    )
    if m:
        day = int(m.group(1))
        month = _MONTH_MAP.get(m.group(2), 0)
        year = int(m.group(3)) if m.group(3) else base_today.year
        if 1 <= day <= 31 and 1 <= month <= 12:
            try:
                target = dt.date(year, month, day)
                if not m.group(3) and (target - base_today).days > 14:
                    target = dt.date(year - 1, month, day)
                # Cek tanggal itu + +-1 hari untuk perbedaan zona waktu WIB vs UTC
                for delta in (0, -1, 1):
                    dates.append((target + dt.timedelta(days=delta)).strftime("%Y%m%d"))
                return dates
            except ValueError:
                pass

    # 2) Tanggal numerik dd/mm atau dd-mm
    m_num = re.search(r"\b(\d{1,2})[/-](\d{1,2})(?:[/-](20\d{2}))?\b", low)
    if m_num:
        d_val, mo_val = int(m_num.group(1)), int(m_num.group(2))
        y_val = int(m_num.group(3)) if m_num.group(3) else base_today.year
        if 1 <= d_val <= 31 and 1 <= mo_val <= 12:
            try:
                target = dt.date(y_val, mo_val, d_val)
                return [target.strftime("%Y%m%d")]
            except ValueError:
                pass

    # 3) Kemarin / tadi malam / hari ini, atau 6 hari terakhir bila tanggal tidak disebutkan
    if "kemarin" in low or "tadi malam" in low or "semalam" in low:
        return [
            (base_today - dt.timedelta(days=1)).strftime("%Y%m%d"),
            base_today.strftime("%Y%m%d"),
            (base_today - dt.timedelta(days=2)).strftime("%Y%m%d"),
        ]
    return [(base_today - dt.timedelta(days=d)).strftime("%Y%m%d") for d in range(0, 7)]


async def _fetch_espn_scoreboard(client: httpx.AsyncClient, query: str) -> List[str]:
    """Ambil skor resmi dari ESPN Public Scoreboard API untuk berbagai olahraga (gratis, tanpa API key).

    Mendukung: sepak bola (soccer/all), basket NBA, Formula 1, bulu tangkis, MMA, tenis Grand Slam.
    ESPN scoreboard API path: /apis/site/v2/sports/{sport}/{league}/scoreboard?dates=YYYYMMDD
    """
    matched_teams: List[Tuple[str, Tuple[str, ...]]] = []
    for pat, label, kws in _TEAM_ALIASES:
        if pat.search(query):
            matched_teams.append((label, kws))
    if not matched_teams:
        return []

    low = query.lower()
    dates_ymd = _extract_sports_dates_ymd(query)[:7]

    # Deteksi sport berdasarkan kata kunci dalam query
    # ESPN scoreboard path: sport/league
    _SPORT_ROUTES: List[Tuple[re.Pattern, str]] = [
        # Basket NBA
        (re.compile(r"\b(?:nba|lakers|celtics|warriors|bulls|heat|suns|nuggets|bucks|knicks|nets)\b", re.I), "basketball/nba"),
        # Formula 1
        (re.compile(r"\b(?:formula\s*1|f1|grand\s+prix|gp\s+\w+|verstappen|leclerc|hamilton|norris|sainz|alonso)\b", re.I), "racing/f1"),
        # MMA / UFC
        (re.compile(r"\b(?:ufc|mma|one\s+championship|boxing|tinju|khabib|mcgregor)\b", re.I), "mma/ufc"),
        # Tenis Grand Slam / ATP / WTA
        (re.compile(r"\b(?:tenis|tennis|wimbledon|us\s+open|french\s+open|australian\s+open|grand\s+slam|atp|wta)\b", re.I), "tennis/atp"),
        # Baseball (MLB)
        (re.compile(r"\b(?:mlb|baseball|yankees|dodgers|red\s+sox)\b", re.I), "baseball/mlb"),
        # American Football NFL
        (re.compile(r"\b(?:nfl|american\s+football|touchdown|super\s+bowl|chiefs|eagles|cowboys)\b", re.I), "football/nfl"),
        # Hockey NHL
        (re.compile(r"\b(?:nhl|hockey|rangers|maple\s+leafs|canadiens)\b", re.I), "hockey/nhl"),
        # Sepak bola — default fallback (harus paling akhir)
        (re.compile(r"\b(?:skor|man\s+united|man\s+u|liverpool|arsenal|chelsea|barcelona|liga|ucl|premier|la\s+liga|persib|persija|timnas|sepak\s+bola)\b", re.I), "soccer/all"),
    ]

    # Tentukan route sport yang paling relevan
    sport_route = "soccer/all"  # default
    for pat_s, route in _SPORT_ROUTES:
        if pat_s.search(low):
            sport_route = route
            break

    urls = [
        f"https://site.api.espn.com/apis/site/v2/sports/{sport_route}/scoreboard?dates={ymd}"
        for ymd in dates_ymd
    ]

    # Untuk F1, gunakan juga endpoint hasil race
    if sport_route == "racing/f1":
        # F1 race result tersedia di ESPN dengan path berbeda
        urls = [
            f"https://site.api.espn.com/apis/site/v2/sports/racing/f1/scoreboard?dates={ymd}"
            for ymd in dates_ymd
        ]

    async def _get_day(url: str):
        try:
            r = await client.get(url)
            if r.status_code == 200:
                return r.json().get("events") or []
        except Exception:
            pass
        return []

    day_lists = await asyncio.gather(*(_get_day(u) for u in urls), return_exceptions=True)
    out: List[str] = []
    for events in day_lists:
        if not isinstance(events, list):
            continue
        for ev in events:
            for comp in ev.get("competitions") or []:
                comps = comp.get("competitors") or []
                if len(comps) < 2:
                    continue
                haystack = " ".join(
                    f"{c.get('team', {}).get('displayName', '')} {c.get('team', {}).get('shortDisplayName', '')} {c.get('athlete', {}).get('displayName', '')} {c.get('athlete', {}).get('lastName', '')}"
                    for c in comps
                ).lower()
                # Untuk olahraga individu (F1, tenis, MMA) cukup 1 nama yang match
                min_hits = 1 if sport_route in ("racing/f1", "tennis/atp", "mma/ufc") else min(2, len(matched_teams))
                team_hits = sum(1 for _, kws in matched_teams if any(kw in haystack for kw in kws))
                if team_hits < min_hits:
                    continue

                home = next((c for c in comps if c.get("homeAway") == "home"), comps[0])
                away = next((c for c in comps if c.get("homeAway") == "away"), comps[1])

                # Nama tim atau atlet (F1/tenis memakai athlete, basket/sepakbola memakai team)
                def _name(c: dict) -> str:
                    return (
                        c.get("team", {}).get("shortDisplayName")
                        or c.get("team", {}).get("displayName")
                        or c.get("athlete", {}).get("displayName")
                        or "?"
                    )

                h_name = _name(home)
                a_name = _name(away)
                h_score = home.get("score", "?")
                a_score = away.get("score", "?")
                status_txt = (comp.get("status") or {}).get("type", {}).get("shortDetail") or "Result"
                ev_date = (ev.get("date") or "")[:10]
                league = (
                    (ev.get("season") or {}).get("slug")
                    or (ev.get("competitions") or [{}])[0].get("type", {}).get("abbreviation")
                    or sport_route.split("/")[-1].upper()
                ).replace("-", " ").title()

                # Pencetak poin/gol — berlaku untuk sepakbola dan basket
                scorers: List[str] = []
                for det in (comp.get("details") or [])[:8]:
                    clk = (det.get("clock") or {}).get("displayValue") or ""
                    aths = det.get("athletesInvolved") or []
                    pname = aths[0].get("shortName") if aths else ""
                    if pname and det.get("scoringPlay"):
                        scorers.append(f"{pname} {clk}".strip())
                sport_label = sport_route.split("/")[-1].upper()
                extra = f" | Gol: {', '.join(scorers)}" if scorers and sport_route.startswith("soccer") else ""
                out.append(f"[Skor Resmi {ev_date} {sport_label}] {h_name} {h_score} - {a_score} {a_name} ({status_txt}){extra}"[:260])
    return out


async def search_live_web(raw_message: str, timeout_s: float = 2.8) -> Optional[str]:
    """Ambil ringkasan fakta real-time dari ESPN Scoreboard + Google News ID/Global + Bing + Wikipedia."""
    query = extract_clean_search_query(raw_message)
    if not query:
        return None

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36",
        "Accept-Language": "id-ID,id;q=0.9,en-US;q=0.8",
    }
    is_sports = bool(
        re.search(
            r"\b(?:"
            # Sepak bola
            r"skor|hasil|vs|versus|lawan|pertandingan|united|utd|man\s*u|liverpool|sporting|madrid|barca|arsenal|chelsea|"
            r"liga|timnas|persib|persija|arema|psm|premier|la\s+liga|serie\s+a|bundesliga|ucl|champions|"
            # Basket
            r"nba|lakers|celtics|warriors|bulls|heat|suns|nuggets|bucks|knicks|"
            # E-sport & gaming
            r"mpl|mlbb|mobile\s+legends|rrq|evos|onic|alter\s+ego|valorant|vct|dota|pubg|free\s+fire|"
            r"esport|e-sport|turnamen|"
            # F1 & balap
            r"formula\s*1|f1|grand\s+prix|verstappen|leclerc|hamilton|norris|sainz|"
            # Olahraga lain
            r"olimpiade|asian\s+games|sea\s+games|bulutangkis|bulu\s+tangkis|badminton|"
            r"tenis|wimbledon|us\s+open|french\s+open|atp|wta|"
            r"tinju|mma|ufc|one\s+championship"
            r")\b",
            query,
            re.I,
        )
    )

    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(timeout_s, connect=1.2), headers=headers, follow_redirects=True) as client:
            if is_sports:
                clean_sports = _normalize_sports_query(query)
                # Hapus tanggal mentah di kueri berita agar artikel pasca-laga (H+1) tetap ditemukan!
                rss_sports = re.sub(
                    r"\b(?:\d{1,2}\s+(?:jan|januari|feb|februari|mar|maret|apr|april|mei|jun|juni|jul|juli|agu|agustus|sep|september|okt|oktober|nov|november|des|desember)(?:\s+20\d{2})?|kemarin|tadi\s+malam|semalam|skor|hasil|pertandingan)\b",
                    " ",
                    clean_sports,
                    flags=re.I,
                )
                rss_sports = re.sub(r"\s+", " ", rss_sports).strip() or clean_sports
                tasks = [
                    _fetch_espn_scoreboard(client, query),
                    _fetch_google_news_rss(client, f"hasil {rss_sports}", hl="id", gl="ID"),
                    _fetch_google_news_rss(client, f"{rss_sports} score result", hl="en", gl="US"),
                    # Wikipedia untuk profil atlet / fakta turnamen
                    _fetch_wikipedia_summary(client, rss_sports),
                ]
            else:
                tasks = [
                    _fetch_google_news_rss(client, query, hl="id", gl="ID"),
                    _fetch_bing_rss(client, query),
                    _fetch_wikipedia_summary(client, query),
                ]

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

    now_wib = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=7)).strftime("%d %b %Y")
    return (
        f"HASIL PENCARIAN GOOGLE & SKOR TERKINI REAL-TIME (tanggal sekarang {now_wib} WIB; gunakan fakta di bawah ini untuk menjawab akurat; "
        "jika berita berupa rumor/klaim belum terbukti, sampaikan jujur bahwa di berita itu masih isu/belum ada bukti resmi):\n- "
        + "\n- ".join(merged)
    )


def _strip_accents(text: str) -> str:
    """Hapus tanda diakritik/aksen unicode (mis. eńau -> enau, Beyoncé -> Beyonce)."""
    return "".join(
        ch for ch in unicodedata.normalize("NFKD", text or "")
        if not unicodedata.combining(ch)
    )


def _clean_music_query(query: str) -> str:
    normalized = _strip_accents(query or "")
    clean_q = re.sub(r"\b(?:by|oleh|dari|lagu|song|musik|music|spotify)\b", " ", normalized, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", clean_q).strip()


def _strip_feat_for_search(query: str) -> str:
    """Hapus bagian feat./ft. agar pencarian katalog lebih toleran bila artis tamu terlalu panjang."""
    stripped = re.sub(r"\b(?:feat\.?|ft\.?|featuring)\b.*$", "", query or "", flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", stripped).strip()


def _base_song_title(title: str) -> str:
    t = re.sub(r"\s*[\(\[].*?[\)\]]", "", (title or "")).strip()
    t = re.sub(r"\s*[-–]\s*(?:remaster(?:ed)?|live|acoustic|radio\s+edit|single\s+version).*$", "", t, flags=re.I)
    return re.sub(r"[^\w\s]", "", t.lower()).strip()


def _score_track_match(clean_q: str, title: str, artist: str) -> float:
    q_words = [w for w in re.findall(r"\w+", clean_q.lower()) if len(w) >= 2]
    t_low = title.lower()
    a_low = artist.lower()
    base_t = _base_song_title(title)
    score = 0.0
    for w in q_words:
        if w in base_t:
            score += 3.0
        elif w in t_low:
            score += 2.0
        if w in a_low:
            score += 2.5
    if base_t and base_t in clean_q.lower():
        score += 6.0
    # Bonus besar jika artis persis cocok dengan kata-kata di query (mis. "paramore" → Paramore)
    # Ini mencegah lagu artis lain yang kebetulan berjudul mirip muncul duluan
    q_low = clean_q.lower()
    artist_words = [w for w in re.findall(r"\w+", a_low) if len(w) >= 3]
    exact_artist_matches = sum(1 for w in artist_words if w in q_low)
    if artist_words and exact_artist_matches == len(artist_words):
        # Semua kata artis cocok di query → bonus besar (artis eksak)
        score += 8.0
    elif exact_artist_matches > 0:
        score += 3.0 * exact_artist_matches
    if any(w in t_low for w in ("karaoke", "tribute", "instrumental", "8-bit", "ringtone", "cover")):
        score -= 8.0
    return score


def _make_track_dict(title: str, artist: str, album: str, cover_url: str, preview_url: str, dur_s: int) -> Dict[str, Any]:
    sp_q = f"{title} {artist}".strip()
    return {
        "title": title,
        "artist": artist,
        "album": album,
        "cover_url": cover_url,
        "preview_url": preview_url,
        "duration_s": max(30, dur_s),
        "spotify_query": sp_q,
        "stream_path": f"/music/stream?q={urllib.parse.quote(sp_q)}&dur={max(30, dur_s)}",
    }


async def search_music_track(query: str, timeout_s: float = 4.2) -> Dict[str, Any]:
    """Cari lagu utama yang diminta + antrean rekomendasi lagu lain dari artis/genre terkait."""
    clean_q = _clean_music_query(query)
    if not clean_q:
        return {"found": False, "tracks": []}

    headers = {"User-Agent": "DrivingBuddy/1.0"}
    candidates: List[Tuple[float, Dict[str, Any]]] = []

    async with httpx.AsyncClient(timeout=httpx.Timeout(min(timeout_s, 2.8), connect=1.2), headers=headers, follow_redirects=True) as client:
        it_task = client.get(
            f"https://itunes.apple.com/search?term={urllib.parse.quote(clean_q)}&media=music&entity=song&limit=10"
        )
        dz_task = client.get(
            f"https://api.deezer.com/search?q={urllib.parse.quote(clean_q)}&limit=10"
        )
        it_resp, dz_resp = await asyncio.gather(it_task, dz_task, return_exceptions=True)

        if isinstance(it_resp, httpx.Response) and it_resp.status_code == 200:
            for it in (it_resp.json().get("results") or []):
                title = (it.get("trackName") or "").strip()
                artist = (it.get("artistName") or "Spotify").strip()
                if not title:
                    continue
                art = (it.get("artworkUrl100") or "").replace("100x100bb", "300x300bb")
                dur_s = int((it.get("trackTimeMillis") or 210000) / 1000)
                tr = _make_track_dict(title, artist, it.get("collectionName") or "", art, it.get("previewUrl") or "", dur_s)
                candidates.append((_score_track_match(clean_q, title, artist) + 0.5, tr))

        if isinstance(dz_resp, httpx.Response) and dz_resp.status_code == 200:
            for it in (dz_resp.json().get("data") or []):
                title = (it.get("title") or "").strip()
                artist = ((it.get("artist") or {}).get("name") or "Spotify").strip()
                if not title:
                    continue
                album_obj = it.get("album") or {}
                dur_s = int(it.get("duration") or 210)
                tr = _make_track_dict(
                    title,
                    artist,
                    album_obj.get("title") or "",
                    album_obj.get("cover_medium") or album_obj.get("cover") or "",
                    it.get("preview") or "",
                    dur_s,
                )
                candidates.append((_score_track_match(clean_q, title, artist), tr))

        tracks: List[Dict[str, Any]] = []
        seen_base_titles: set[str] = set()
        if candidates:
            candidates.sort(key=lambda pair: pair[0], reverse=True)
            primary = candidates[0][1]
            tracks.append(primary)
            seen_base_titles.add(_base_song_title(primary["title"]))

            # Ambil rekomendasi lagu LAIN yang berbeda judul dari artis yang sama (seperti Radio Spotify!)
            primary_artist = primary["artist"]
            try:
                rec_it_task = client.get(
                    f"https://itunes.apple.com/search?term={urllib.parse.quote(primary_artist)}&media=music&entity=song&attribute=artistTerm&limit=15"
                )
                artist_q = urllib.parse.quote(f'artist:"{primary_artist}"')
                rec_dz_task = client.get(
                    f"https://api.deezer.com/search?q={artist_q}&order=RANKING&limit=15"
                )
                rec_it, rec_dz = await asyncio.gather(rec_it_task, rec_dz_task, return_exceptions=True)
                rec_pool: List[Dict[str, Any]] = []
                if isinstance(rec_dz, httpx.Response) and rec_dz.status_code == 200:
                    for it in (rec_dz.json().get("data") or []):
                        t_name = (it.get("title") or "").strip()
                        a_name = ((it.get("artist") or {}).get("name") or primary_artist).strip()
                        alb = it.get("album") or {}
                        if t_name:
                            rec_pool.append(_make_track_dict(
                                t_name, a_name, alb.get("title") or "",
                                alb.get("cover_medium") or alb.get("cover") or "",
                                it.get("preview") or "", int(it.get("duration") or 210),
                            ))
                if isinstance(rec_it, httpx.Response) and rec_it.status_code == 200:
                    for it in (rec_it.json().get("results") or []):
                        t_name = (it.get("trackName") or "").strip()
                        a_name = (it.get("artistName") or primary_artist).strip()
                        if t_name:
                            rec_pool.append(_make_track_dict(
                                t_name, a_name, it.get("collectionName") or "",
                                (it.get("artworkUrl100") or "").replace("100x100bb", "300x300bb"),
                                it.get("previewUrl") or "", int((it.get("trackTimeMillis") or 210000) / 1000),
                            ))
                target_artist_low = primary_artist.strip().lower()
                # Pass 1: prioritaskan lagu dari artis yang persis sama (misal Oasis -> Oasis, bukan "Oasis Music Artist")
                for strict_artist in (True, False):
                    if len(tracks) >= 5:
                        break
                    for cand in rec_pool:
                        cand_artist_low = (cand.get("artist") or "").strip().lower()
                        if strict_artist and cand_artist_low != target_artist_low:
                            continue
                        bt = _base_song_title(cand["title"])
                        if not bt or bt in seen_base_titles:
                            continue
                        if any(w in cand["title"].lower() for w in ("karaoke", "instrumental", "tribute")):
                            continue
                        seen_base_titles.add(bt)
                        tracks.append(cand)
                        if len(tracks) >= 5:
                            break
            except Exception:
                pass

            # Lengkapi sampai 5 lagu dari hasil pencarian awal bila masih kurang
            if len(tracks) < 5:
                for _, cand in candidates[1:]:
                    bt = _base_song_title(cand["title"])
                    if not bt or bt in seen_base_titles:
                        continue
                    seen_base_titles.add(bt)
                    tracks.append(cand)
                    if len(tracks) >= 5:
                        break

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


def _is_unwanted_variant(text: str, query: str) -> bool:
    """Tolak versi cover, acoustic, slowed, pitched, remix, dll kecuali diminta eksplisit di query."""
    t_low = (text or "").lower()
    q_low = (query or "").lower()
    bad_terms = (
        "cover",
        "acoustic",
        "slowed",
        "reverb",
        "pitched",
        "nightcore",
        "sped up",
        "speed up",
        "karaoke",
        "instrumental",
        "8d audio",
        "8d ",
        "remix",
        "bootleg",
        "mashup",
        "tribute",
        "lo-fi",
        "lofi",
        "bass boosted",
        "piano version",
        "guitar cover",
        "guitar version",
        "parody",
        "reaction",
        "tutorial",
        "remake",
        "amapiano",
        "blend",
        # Tambahan: tolak video lirik / visualizer (sering cover atau non-official)
        "lyric video",
        "lyrics video",
        "visualizer",
        "fan made",
        "fan-made",
        "unofficial",
        "tribute to",
        "inspired by",
        "in the style of",
        "how to sing",
        "vocal cover",
        "violin cover",
        "ukulele cover",
        "flute cover",
        "piano cover",
    )
    for term in bad_terms:
        if term in t_low and term.strip() not in q_low:
            return True
    if re.search(r"\blive\b", t_low) and not re.search(r"\blive\b", q_low):
        return True
    return False


def _query_overlap_ratio(query: str, candidate_text: str) -> float:
    q_words = [w for w in re.findall(r"\w+", (query or "").lower()) if len(w) >= 2]
    if not q_words:
        return 0.0
    c_low = (candidate_text or "").lower()
    matched = sum(1 for w in q_words if w in c_low)
    return matched / len(q_words)


def _resolve_ytdlp_sync(query: str, target_dur_s: int = 210) -> Optional[Dict[str, Any]]:
    """Coba ekstrak URL audio m4a/mp3 studio penuh via YouTube Music Official Topic / yt-dlp."""
    try:
        import yt_dlp  # type: ignore
    except Exception:
        return None

    ydl_opts = {
        "format": "bestaudio[ext=m4a][abr<=160]/bestaudio[ext=mp4]/bestaudio[protocol^=http][ext!=webm]/bestaudio",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 4.0,
        "extract_flat": False,
        "extractor_args": {"youtube": {"player_client": ["android_music", "android", "ios", "web"]}},
    }
    search_queries = [f"ytsearch4:{query} topic", f"ytsearch3:{query} official audio"]
    best_candidate: Optional[Tuple[float, Dict[str, Any]]] = None

    for sq in search_queries:
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(sq, download=False)
                entries = (info or {}).get("entries") or []
                for ent in entries:
                    if not ent:
                        continue
                    u = ent.get("url") or ""
                    dur = int(ent.get("duration") or 0)
                    ext = (ent.get("ext") or "m4a").lower()
                    ent_title = ent.get("title") or ""
                    uploader = ent.get("uploader") or ent.get("channel") or ""
                    if _is_unwanted_variant(ent_title, query):
                        continue
                    overlap = _query_overlap_ratio(query, f"{ent_title} {uploader}")
                    if overlap < 0.5:
                        continue
                    if not (u.startswith("http") and 60 <= dur <= 720 and "manifest.googlevideo.com" not in u):
                        continue
                    score = overlap * 50.0
                    # Prioritas tinggi untuk kanal resmi YouTube Music "- Topic"
                    if uploader.lower().endswith("- topic") or "official" in uploader.lower():
                        score += 40.0
                    if target_dur_s > 45:
                        score -= min(25.0, abs(dur - target_dur_s) * 0.5)
                    mime = "audio/mpeg" if ext == "mp3" else "audio/mp4"
                    cand = {
                        "mode": "direct_url",
                        "url": u,
                        "mime": mime,
                        "headers": ent.get("http_headers") or {},
                        "duration_s": dur,
                    }
                    if best_candidate is None or score > best_candidate[0]:
                        best_candidate = (score, cand)
            if best_candidate and best_candidate[0] >= 75.0:
                return best_candidate[1]
        except Exception as exc:
            log.debug("[MusicStream] yt-dlp dilewati (%s): %s", sq, exc)
    return best_candidate[1] if best_candidate else None


async def _resolve_soundcloud_full_stream(
    client: httpx.AsyncClient,
    query: str,
    target_dur_s: int = 210,
) -> Optional[Dict[str, Any]]:
    """Resolusi lagu utuh penuh (2–6 menit) via SoundCloud v2: hanya terima rekaman asli yang cocok, tolak cover/pitched."""
    cid = await _get_soundcloud_client_id(client)
    if not cid:
        return None

    queries_to_try = [query]
    no_feat = _strip_feat_for_search(query)
    if no_feat and no_feat.lower() != query.lower():
        queries_to_try.append(no_feat)

    candidates: List[Tuple[float, Dict[str, Any]]] = []
    for active_q in queries_to_try:
        search_url = (
            f"https://api-v2.soundcloud.com/search/tracks?q={urllib.parse.quote(active_q)}"
            f"&client_id={cid}&limit=12"
        )
        resp = await client.get(search_url)
        if resp.status_code != 200:
            continue

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

            title_raw = (tr.get("title") or "").strip()
            user_obj = tr.get("user") or {}
            uploader = (user_obj.get("username") or "").strip()
            is_verified = bool(user_obj.get("verified"))

            # TOLAK KERAS cover, acoustic, slowed, pitched, remix, dll jika user tidak memintanya!
            if _is_unwanted_variant(title_raw, active_q):
                continue

            # Wajib ada kecocokan kata kunci query pada judul + nama uploader
            overlap = _query_overlap_ratio(active_q, f"{title_raw} {uploader}")
            if overlap < 0.65:
                continue

            score = 100.0 + overlap * 25.0
            if is_verified:
                # Bonus besar untuk akun terverifikasi (artis resmi / label)
                score += 60.0
            elif not is_verified:
                # Penalti uploader tidak terverifikasi — kemungkinan cover/fan upload
                score -= 20.0
            # Jika durasi berbeda jauh (> 35 detik) dari durasi studio asli, kemungkinan besar versi berbeda/pitched
            if target_dur_s > 45:
                diff_s = abs(dur_s - target_dur_s)
                if diff_s > 35:
                    continue
                score -= min(35.0, diff_s * 0.65)

            has_prog = any(
                tc.get("format", {}).get("protocol") == "progressive" and not tc.get("snipped")
                for tc in tcs
            )
            if has_prog:
                score += 8.0
            candidates.append((score, tr))
        if candidates:
            break

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
                    if mp3_url.startswith("http") and "/cbcs/" not in mp3_url:
                        return {
                            "mode": "direct_url",
                            "url": mp3_url,
                            "mime": "audio/mpeg",
                            "headers": {},
                            "duration_s": dur_s,
                        }

        # 2) Gunakan HLS CMAF fMP4 atau HLS MP3 TANPA DRM (#EXT-X-KEY / /cbcs/ wajib dilewati!)
        for tc in tcs:
            fmt = tc.get("format") or {}
            mime = fmt.get("mime_type") or ""
            if tc.get("snipped") or ("mp4" not in mime and "mpeg" not in mime):
                continue
            sep = "&" if "?" in tc.get("url", "") else "?"
            r = await client.get(f"{tc['url']}{sep}client_id={cid}")
            if r.status_code != 200:
                continue
            m3u8_url = r.json().get("url") or ""
            if not m3u8_url.startswith("http") or "/cbcs/" in m3u8_url:
                continue
            m3u8_resp = await client.get(m3u8_url)
            if m3u8_resp.status_code != 200:
                continue
            m3u8_txt = m3u8_resp.text
            # TOLAK FairPlay / SAMPLE-AES DRM karena tidak akan berbunyi di ExoPlayer Android!
            if "#EXT-X-KEY" in m3u8_txt or "SAMPLE-AES" in m3u8_txt or "skd://" in m3u8_txt:
                continue
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
                    "m3u8_url": m3u8_url,
                    "segments": all_parts,
                    "mime": "audio/mp4",
                    "duration_s": dur_s,
                }
            if seg_urls and "mpeg" in mime:
                return {
                    "mode": "fmp4_segments",
                    "m3u8_url": m3u8_url,
                    "segments": seg_urls,
                    "mime": "audio/mpeg",
                    "duration_s": dur_s,
                }
    return None


async def _resolve_jiosaavn_full_track(
    client: httpx.AsyncClient,
    query: str,
    target_dur_s: int = 210,
) -> Optional[Dict[str, Any]]:
    """Resolusi lagu studio penuh dari JioSaavn (label resmi: 320kbps MP3, tanpa DRM, bebas diunduh).
    Hanya untuk rekaman studio asli; bukan covers atau remix tidak terkenal.
    """
    try:
        saavn_url = f"https://saavn.dev/api/search/songs?query={urllib.parse.quote(query)}&limit=6"
        resp = await client.get(saavn_url)
        if resp.status_code != 200:
            return None
        body = resp.json()
        results = (body.get("data") or {}).get("results") or []
        for tr in results:
            name = (tr.get("name") or "").strip()
            primary_artists = tr.get("primaryArtists") or tr.get("artists", {}).get("primary") or []
            if isinstance(primary_artists, list):
                artist_str = " ".join(a.get("name", "") for a in primary_artists if a.get("name"))
            else:
                artist_str = str(primary_artists)
            # Tolak covers, remixes, karaoke kecuali diminta
            if _is_unwanted_variant(name, query):
                continue
            # Pastikan ada kecocokan kata kunci
            if _query_overlap_ratio(query, f"{name} {artist_str}") < 0.5:
                continue
            dur_s = int(tr.get("duration") or 0)
            if dur_s > 0 and abs(dur_s - target_dur_s) > 60:
                continue
            # Ambil URL 320kbps
            download_urls = tr.get("downloadUrl") or []
            if isinstance(download_urls, list):
                # Prioritas kualitas: 320kbps > 160kbps > 96kbps
                for quality in ("320kbps", "160kbps", "96kbps"):
                    for entry in download_urls:
                        if isinstance(entry, dict) and entry.get("quality") == quality:
                            mp3_url = (entry.get("url") or "").strip()
                            if mp3_url.startswith("http"):
                                return {
                                    "mode": "direct_url",
                                    "url": mp3_url,
                                    "mime": "audio/mpeg",
                                    "headers": {},
                                    "duration_s": max(dur_s, 30),
                                }
    except Exception as exc:
        log.debug("[MusicStream] JioSaavn dilewati: %s", exc)
    return None


async def _search_youtube_video_id(client: httpx.AsyncClient, query: str) -> Optional[str]:
    """Cari videoId YouTube Music Official Topic untuk diekstrak langsung oleh klien Flutter di HP.
    Urutan pencarian: Topic channel → Official Audio → Official video → fallback dari query biasa.
    Hanya ambil video yang bukan cover/karaoke/slowed berdasarkan judul."""
    search_queries = [
        f"{query} topic",
        f"{query} official audio",
        f"{query} official video",
        query,
    ]
    for sq in search_queries:
        try:
            encoded_sq = urllib.parse.quote(sq)
            resp = await client.get(
                f"https://www.youtube.com/results?search_query={encoded_sq}",
                headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"},
                timeout=5.0,
            )
            if resp.status_code != 200:
                continue
            # Ekstrak semua pasangan videoId + judul dari initialData JSON YouTube
            # Format: {"videoId":"XXXXXXXXXXX"}...{"title":{"runs":[{"text":"..."}]}}
            raw = resp.text
            # Ambil videoId kandidat dari halaman
            video_ids = re.findall(r'"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"', raw)
            # Ambil judul di dekat masing-masing videoId — gunakan pendekatan sederhana
            # Cari pasangan "videoId":"ID" diikuti "text":"JUDUL" dalam 500 karakter
            pairs: List[Tuple[str, str]] = []
            for m in re.finditer(r'"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"', raw):
                vid_id = m.group(1)
                snippet = raw[m.start():m.start() + 600]
                title_m = re.search(r'"text"\s*:\s*"([^"]{3,120})"', snippet)
                title = title_m.group(1) if title_m else ""
                if title and not _is_unwanted_variant(title, query):
                    pairs.append((vid_id, title))
            if pairs:
                return pairs[0][0]
        except Exception as exc:
            log.debug("[MusicStream] YouTube videoId search dilewati (%s): %s", sq, exc)
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

        # 2. Fallback ke JioSaavn (full-track MP3 320kbps tanpa DRM, label resmi)
        if chosen is None:
            try:
                saavn_chosen = await _resolve_jiosaavn_full_track(client, clean_q, target_dur_s)
                if saavn_chosen:
                    chosen = saavn_chosen
            except Exception:
                pass

        # 3. Fallback ke YouTube videoId (untuk diekstrak langsung di HP) + preview studio resmi iTunes/Deezer (30 detik)
        if chosen is None:
            yt_vid, meta = await asyncio.gather(
                _search_youtube_video_id(client, clean_q),
                search_music_track(clean_q, timeout_s=3.0),
            )
            prev = (meta.get("preview_url") or "").strip() if isinstance(meta, dict) else ""
            if prev.startswith("http"):
                chosen = {
                    "mode": "direct_url",
                    "url": prev,
                    "mime": "audio/mp4" if ".m4a" in prev.lower() else "audio/mpeg",
                    "headers": {},
                    "duration_s": 30,
                }
                if yt_vid:
                    chosen["yt_video_id"] = yt_vid
            elif yt_vid:
                chosen = {
                    "mode": "yt_video_id",
                    "url": "",
                    "yt_video_id": yt_vid,
                    "mime": "audio/mp4",
                    "headers": {},
                    "duration_s": target_dur_s,
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


async def assemble_full_music_bytes(stream_info: Dict[str, Any]) -> bytes:
    """Unduh seluruh segmen audio secara paralel agar menjadi 1 file utuh seekable (0:00 -> selesai)."""
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
            resp = await client.get(stream_info["url"])
            resp.raise_for_status()
            return resp.content

        segments: List[str] = stream_info.get("segments") or []
        sem = asyncio.Semaphore(8)

        async def _fetch_one(u: str) -> bytes:
            async with sem:
                r = await client.get(u)
                return r.content if r.status_code in (200, 206) else b""

        parts = await asyncio.gather(*(_fetch_one(u) for u in segments))
        return b"".join(parts)
