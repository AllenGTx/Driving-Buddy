"""Endpoint HTTP /stt (4-lapis Speech-to-Text) dan /tts (Voicebox Furina / Cloud TTS)."""
from __future__ import annotations

import base64
import logging
import os
import re
from typing import Any, Dict, Mapping, Optional

import httpx
from fastapi import APIRouter, File, Form, HTTPException, Request, Response, UploadFile
from pydantic import BaseModel, ConfigDict, Field

from .config import _collect_env

log = logging.getLogger("driving_buddy.llm")

# PENTING: Whisper `prompt` dibatasi 224 token (~150 kata) dan bekerja sebagai konteks kalimat.
# Prompt terlalu panjang akan terpotong dan merusak pengenalan kata Bahasa Inggris/Indonesia!
STT_VOCAB_PROMPT = (
    "Yo Rina, Yo Furina, Yo Jane, Yo John, halo Rina, hai John. "
    "Berapa 5 kali 5, 10 tambah 5, 20 bagi 4. "
    "Skor Man United vs Liverpool, Real Madrid, Barcelona, Arsenal, Chelsea, NBA Lakers Celtics, "
    "hasil MPL Mobile Legends RRQ ONIC, Formula 1 Verstappen, Olimpiade bulutangkis, fakta sejarah. "
    "Tolong arahkan saya ke Indomaret, Alfamart, SPBU Pertamina, rest area terdekat. "
    "Tolong setelkan lagu Still Into You Paramore, Ain't It Fun Paramore, Hard Times Paramore, "
    "Last Night on Earth Green Day, Cancer My Chemical Romance, Mirrors Justin Timberlake di Spotify."
)

_STT_CORRECTIONS = (
    # Sepak bola & olahraga
    (re.compile(r"\bskrol\s+(?:ro)?man(?:chester)?\s+united\b", re.IGNORECASE), "skor Man United"),
    (re.compile(r"\bskroll?\s+(?:mu|man\s*u)\b", re.IGNORECASE), "skor Man U"),
    (re.compile(r"\bskroll?\s+(?:roman|raman)\s+united\b", re.IGNORECASE), "skor Man United"),
    (re.compile(r"\bskroll?\s+(?:lfc|liver\s*pool)\b", re.IGNORECASE), "skor Liverpool"),
    # Angka & matematika
    (re.compile(r"\b(?:li|ri|ni)ma\s+kali\s+(?:li|ri|ni)ma\b", re.IGNORECASE), "5 kali 5"),
    (re.compile(r"\be\s*5\b"), "5 kali 5"),
    # E-sport & gaming
    (re.compile(r"\bmpl\s+(?:i\s*d|id|indonesia)\b", re.IGNORECASE), "MPL Indonesia"),
    (re.compile(r"\brrq\s+hosi\b", re.IGNORECASE), "RRQ Hoshi"),
    (re.compile(r"\bonic\s+(?:e\s*sport|sport)s?\b", re.IGNORECASE), "ONIC Esports"),
    (re.compile(r"\bml\s*bb\b", re.IGNORECASE), "MLBB Mobile Legends"),
    # Buddy names
    (re.compile(r"\b(?:yo|hei|halo|hai)\s+ri(?:na|nah)\b", re.IGNORECASE), "Yo Rina"),
    (re.compile(r"\b(?:yo|hei|halo|hai)\s+j(?:ane|en|an)\b", re.IGNORECASE), "Yo Jane"),
    (re.compile(r"\b(?:yo|hei|halo|hai)\s+j(?:on|ohn|onn)\b", re.IGNORECASE), "Yo John"),
    # Musik & band populer yang sering salah eja fonetik
    (re.compile(r"\bbayi\s+para\s+baru\b", re.IGNORECASE), "by Paramore"),
    (re.compile(r"\b(?:para\s*mor[ae]?|parama|para\s+baru|para\s+more?|paramor)\b", re.IGNORECASE), "Paramore"),
    # "Still Into You" — Whisper ID sering mengeja fonetik seperti "ncuyu" / "nyucu"
    (re.compile(r"\b(?:stil(?:l)?\s+in\s*to\s+you|n?cuyu|nyucu)\b", re.IGNORECASE), "Still Into You"),
    (re.compile(r"\bsaya\s*,?\s+it\s+ain'?t\s*,?\s*(?:eh\s*,?\s*)?into\s+you\b", re.IGNORECASE), "Still Into You"),
    # "Ain't It Fun"
    (re.compile(r"\b(?:ain'?t\s+it\s+fun|en\s+it\s+fun|ain\s+it\s+fun)\b", re.IGNORECASE), "Ain't It Fun"),
    # Hard Times
    (re.compile(r"\bhard\s*taim(?:s)?\b", re.IGNORECASE), "Hard Times"),
    (re.compile(r"\bhardtimes\b", re.IGNORECASE), "Hard Times"),
    (re.compile(r"\bgreen\s+dei\b", re.IGNORECASE), "Green Day"),
    (re.compile(r"\bspotif(?:ai|y)?\b", re.IGNORECASE), "Spotify"),
)

_HALLUCINATION_PATTERNS = (
    re.compile(r"\bdieja\b", re.IGNORECASE),
    re.compile(r"\b(?:[a-zA-Z]-){3,}[a-zA-Z]\b"),
    re.compile(r"terima\s+kasih\s+(?:telah|sudah)\s+menonton", re.IGNORECASE),
    re.compile(r"jangan\s+lupa\s+(?:like|subscribe|komen)", re.IGNORECASE),
    re.compile(r"(?:subtitle|subtitel|diterjemahkan)\s+oleh", re.IGNORECASE),
    re.compile(r"amara\.org", re.IGNORECASE),
)


_PURE_HESITATION_RE = re.compile(
    r"^(?:uh+|um+|hm+|er+m*|ah+|eh+|oh+|huh+)(?:[\s,.\-!?]+(?:uh+|um+|hm+|er+m*|ah+|eh+|oh+|huh+))*$",
    re.IGNORECASE,
)


def clean_stt_transcript(raw_text: str) -> str:
    """Bersihkan artefak halusinasi Whisper saat audio berisi derau kabin atau hening."""
    text = (raw_text or "").strip()
    if not text:
        return ""
    if _PURE_HESITATION_RE.fullmatch(text.strip(" .,!?-")):
        return ""
    # Jika Whisper hanya membeo ulang kalimat prompt karena rekaman kosong/bising
    norm = re.sub(r"[^\w\s]", "", text.lower()).strip()
    prompt_norm = re.sub(r"[^\w\s]", "", STT_VOCAB_PROMPT.lower()).strip()
    if norm and (norm == prompt_norm or (len(norm) > 95 and norm in prompt_norm)):
        return ""
    for pat in _HALLUCINATION_PATTERNS:
        if pat.search(text):
            # Jika seluruh kalimat adalah halusinasi ejaan/subtitle pendek, buang
            if "dieja" in text.lower():
                # Potong bagian "dieja ..." bila menempel di belakang, atau tolak jika di awal
                idx = text.lower().find("dieja")
                prefix = text[:idx].strip(" ,.-?!")
                words = prefix.split()
                if len(words) <= 2:
                    return ""
                return " ".join(words[:-1]).strip()
            return ""
    for pat, repl in _STT_CORRECTIONS:
        text = pat.sub(repl, text)
    return text


class TtsRequest(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="ignore")

    text: str = Field(..., min_length=1, max_length=600)
    voice_profile: str = Field(default="furina", max_length=32)
    language: str = Field(default="id", max_length=12)


def build_audio_router(
    environ: Optional[Mapping[str, str]] = None,
    http: Optional[httpx.AsyncClient] = None,
) -> APIRouter:
    env = _collect_env(environ, None)
    groq_key = env.get("GROQ_API_KEY") or (
        env.get("LLM_API_KEY", "") if env.get("LLM_API_KEY", "").startswith("gsk_") else ""
    )
    gemini_key = env.get("GEMINI_API_KEY") or env.get("GOOGLE_API_KEY") or (
        env.get("LLM_API_KEY", "") if env.get("LLM_API_KEY", "").startswith(("AIza", "AQ.")) else ""
    )
    cf_tok = env.get("CLOUDFLARE_API_TOKEN") or env.get("CF_API_TOKEN") or ""
    cf_acc = env.get("CLOUDFLARE_ACCOUNT_ID") or env.get("CF_ACCOUNT_ID") or ""
    voicebox_url = (env.get("VOICEBOX_URL") or os.environ.get("VOICEBOX_URL") or "http://127.0.0.1:17493").rstrip("/")
    skip_local_voicebox = (env.get("SKIP_LOCAL_VOICEBOX") or os.environ.get("SKIP_LOCAL_VOICEBOX") or "") == "1"
    furina_cloud_url = (env.get("FURINA_TTS_URL") or os.environ.get("FURINA_TTS_URL") or "").rstrip("/")

    router = APIRouter(tags=["audio"])

    shared_client = (
        http
        if http is not None
        else httpx.AsyncClient(
            timeout=httpx.Timeout(12.0, connect=2.5),
            limits=httpx.Limits(max_connections=20, max_keepalive_connections=10),
        )
    )

    def _client(timeout_s: float) -> httpx.AsyncClient:
        return shared_client

    @router.post("/stt", summary="Transkripsi suara pengemudi dengan rantai failover otomatis")
    async def transcribe_audio(
        file: UploadFile = File(...),
        hint: Optional[str] = Form(default=None),
        mode: Optional[str] = Form(default=None),
        lang: Optional[str] = Form(default=None),
    ) -> Dict[str, Any]:
        raw = await file.read()
        if not raw or len(raw) > 8 * 1024 * 1024:
            raise HTTPException(status_code=422, detail={"error": "invalid_audio", "message": "Ukuran audio tidak valid."})

        filename = file.filename or "speech.m4a"
        mime = (
            "audio/wav"
            if filename.lower().endswith(".wav")
            else (file.content_type or "audio/mp4")
        )
        clean_hint = re.sub(r"(?i)nama\s*buddy\s*:\s*", "", (hint or "")).strip()
        is_wake_mode = (mode or "").strip().lower() == "wake" or (mode is None and not clean_hint)
        # Preferensi bahasa dari klien Flutter: 'en' untuk modul Inggris, 'id' untuk Indonesia.
        # Kalau tidak dikirim, default ke Indonesia agar kompatibel dengan versi lama.
        client_lang = (lang or "").strip().lower() or "id"
        # Pastikan hanya 'en' atau 'id' yang diterima, lainnya fallback ke 'id'
        whisper_lang = "en" if client_lang.startswith("en") else "id"
        if whisper_lang == "en":
            wake_vocab = "Hey Jane, yo Jane, hey John, yo John, hey Rina, hey Furina, hey buddy."
            cmd_vocab = (
                f"Hey {clean_hint}. Play Earrings by Malcolm Todd, Oh Lord by Foxy Shazam, "
                "Last Night on Earth by Green Day, directions to nearest gas station."
                if clean_hint
                else "Hey Jane, hey John, play a song, directions to nearest rest area."
            )
            vocab = wake_vocab if is_wake_mode else cmd_vocab
        else:
            vocab = (
                "Halo Rina, halo Furina, halo Jane, halo John, yo Rina, yo Jane, yo John, hai buddy."
                if is_wake_mode
                else (
                    f"Halo {clean_hint}. {STT_VOCAB_PROMPT}"
                    if clean_hint and clean_hint.lower() not in STT_VOCAB_PROMPT.lower()
                    else STT_VOCAB_PROMPT
                )
            )
        errors = []
        suspect_whisper_text: Optional[str] = None
        client = _client(5.0)

        # Tier 1: Groq Whisper (wake -> turbo super cepat; command -> large-v3 akurasi maksimal)
        if groq_key:
            model_order = (
                ("whisper-large-v3-turbo", "whisper-large-v3")
                if is_wake_mode
                else ("whisper-large-v3", "whisper-large-v3-turbo")
            )
            for w_model in model_order:
                try:
                    resp = await client.post(
                        "https://api.groq.com/openai/v1/audio/transcriptions",
                        headers={"Authorization": f"Bearer {groq_key}"},
                        data={
                            "model": w_model,
                            "language": whisper_lang,
                            "temperature": "0",
                            "prompt": vocab,
                        },
                        files={"file": (filename, raw, mime)},
                        timeout=3.5 if is_wake_mode else 4.5,
                    )
                    if resp.status_code == 200:
                        text = clean_stt_transcript(resp.json().get("text") or "")
                        if not text:
                            return {"text": "", "provider": f"groq_{w_model}_empty"}
                        # Pada mode command, bila hasil sangat pendek aneh (mis. "e5" dari "5 kali 5") dan ada Gemini, cek ulang!
                        looks_garbled = (
                            not is_wake_mode
                            and gemini_key
                            and (len(text) <= 4 or bool(re.fullmatch(r"[a-zA-Z]\d+", text)))
                        )
                        if looks_garbled:
                            suspect_whisper_text = text
                            break
                        return {"text": text, "provider": f"groq_{w_model}"}
                    errors.append(f"groq({w_model}):{resp.status_code}")
                    if resp.status_code != 429 and resp.status_code < 500:
                        break
                except Exception as exc:
                    errors.append(f"groq({w_model}):{type(exc).__name__}")

        # Tier 2: Cloudflare Workers AI Whisper-Large-V3-Turbo (Gratis Cadangan)
        if suspect_whisper_text is None and cf_tok and cf_acc:
            try:
                b64_cf = base64.b64encode(raw).decode("ascii")
                cf_resp = await client.post(
                    f"https://api.cloudflare.com/client/v4/accounts/{cf_acc}/ai/run/@cf/openai/whisper-large-v3-turbo",
                    headers={"Authorization": f"Bearer {cf_tok}", "Content-Type": "application/json"},
                    json={"audio": b64_cf, "language": whisper_lang, "initial_prompt": vocab},
                    timeout=5.0,
                )
                if cf_resp.status_code == 200:
                    res_obj = cf_resp.json().get("result") or {}
                    text = clean_stt_transcript(res_obj.get("text") or "")
                    if text:
                        return {"text": text, "provider": "cloudflare_whisper"}
                errors.append(f"cloudflare_stt:{cf_resp.status_code}")
            except Exception as exc:
                errors.append(f"cloudflare_stt:{type(exc).__name__}")

        # Tier 3: Voicebox Local Whisper (:17493/transcribe) bila tidak di-skip
        if suspect_whisper_text is None and not skip_local_voicebox:
            try:
                resp = await client.post(
                    f"{voicebox_url}/transcribe",
                    files={"file": (filename, raw, mime)},
                    timeout=2.5,
                )
                if resp.status_code == 200:
                    body = resp.json()
                    text = clean_stt_transcript(body.get("text") or body.get("transcript") or "")
                    if text:
                        return {"text": text, "provider": "voicebox_whisper"}
                errors.append(f"voicebox:{resp.status_code}")
            except Exception as exc:
                errors.append(f"voicebox:{type(exc).__name__}")

        # Tier 4 / Recovery: Gemini 2.5 Flash Multimodal Audio STT (sangat akurat untuk angka, hitungan & campuran Inggris-Indonesia)
        if gemini_key:
            try:
                b64 = base64.b64encode(raw).decode("ascii")
                payload = {
                    "contents": [{
                        "parts": [
                            {
                                "text": (
                                    "Transkripsikan ucapan pengemudi Indonesia ini persis apa adanya (bisa bercampur "
                                    "angka hitungan seperti '5 kali 5', istilah Inggris/bola seperti 'skor Man United vs Liverpool', "
                                    "atau judul lagu), tanpa penjelasan tambahan atau ejaan. Jika hanya bising/hening, "
                                    "kembalikan string kosong."
                                )
                            },
                            {"inline_data": {"mime_type": mime, "data": b64}},
                        ]
                    }],
                    "generationConfig": {
                        "temperature": 0.0,
                        "maxOutputTokens": 96,
                        "thinkingConfig": {"thinkingBudget": 0},
                    },
                }
                resp = await client.post(
                    f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={gemini_key}",
                    json=payload,
                    timeout=4.5,
                )
                if resp.status_code == 200:
                    cands = resp.json().get("candidates") or []
                    if cands:
                        parts = cands[0].get("content", {}).get("parts") or []
                        text = clean_stt_transcript("".join(p.get("text", "") for p in parts))
                        if text:
                            return {"text": text, "provider": "gemini_audio"}
                errors.append(f"gemini:{resp.status_code}")
            except Exception as exc:
                errors.append(f"gemini:{type(exc).__name__}")

        if suspect_whisper_text:
            return {"text": suspect_whisper_text, "provider": "groq_fallback_short"}

        raise HTTPException(
            status_code=503,
            detail={"error": "stt_unavailable", "attempts": errors},
        )

    @router.post("/tts", summary="Sintesis suara karakter Furina via Voicebox (:17493) atau Cloud TTS")
    async def synthesize_speech(req: TtsRequest, request: Request) -> Response:
        lang = "ms" if req.language.lower() in ("id", "id-id", "ind") else req.language

        # 1. Coba Voicebox lokal (:17493) bila berjalan di mesin lokal
        if not skip_local_voicebox:
            try:
                client = _client(4.0)
                prof_resp = await client.get(f"{voicebox_url}/profiles", timeout=4.0)
                profile_id = None
                if prof_resp.status_code == 200:
                    items = prof_resp.json()
                    if isinstance(items, dict):
                        items = items.get("profiles") or items.get("items") or []
                    for p in items or []:
                        if str(p.get("name", "")).lower() == req.voice_profile.lower():
                            profile_id = p.get("id") or p.get("profile_id")
                            break
                gen_payload: Dict[str, Any] = {
                    "text": req.text,
                    "profile": req.voice_profile,
                    "language": lang,
                }
                if profile_id:
                    gen_payload["profile_id"] = profile_id

                resp = await client.post(f"{voicebox_url}/generate", json=gen_payload, timeout=4.0)
                if resp.status_code == 200:
                    ctype = resp.headers.get("content-type", "")
                    if "audio/" in ctype or resp.content[:4] in (b"RIFF", b"ID3\x03", b"ID3\x04", b"\xff\xfb"):
                        return Response(content=resp.content, media_type=ctype if "audio/" in ctype else "audio/wav")
                    data = resp.json()
                    audio_url = data.get("audio_url") or data.get("url") or data.get("path")
                    if audio_url:
                        dl_url = audio_url if str(audio_url).startswith("http") else f"{voicebox_url}/{str(audio_url).lstrip('/')}"
                        audio_resp = await client.get(dl_url, timeout=4.0)
                        if audio_resp.status_code == 200:
                            return Response(content=audio_resp.content, media_type=audio_resp.headers.get("content-type", "audio/wav"))
            except Exception as exc:
                log.debug("[TTS] Voicebox lokal belum aktif: %s", exc)

        # 2. Coba endpoint Cloud Neural/Furina TTS (4-Provider Furina RVC v2 + Jane & John Neural gratis)
        if furina_cloud_url:
            fwd_headers: Dict[str, str] = {}
            xff = request.headers.get("x-forwarded-for") or (request.client.host if request.client else "")
            if xff:
                fwd_headers["X-Forwarded-For"] = xff
            ip_tok = request.headers.get("x-ip-token")
            if ip_tok:
                fwd_headers["X-IP-Token"] = ip_tok

            try:
                client = _client(28.0)
                resp = await client.post(
                    furina_cloud_url,
                    headers=fwd_headers,
                    json={
                        "text": req.text,
                        "language": req.language,
                        "voice_profile": req.voice_profile.lower(),
                    },
                    timeout=28.0,
                )
                if resp.status_code == 200 and resp.content:
                    out_headers: Dict[str, str] = {}
                    for h in ("x-furina-provider", "x-voice-provider"):
                        val = resp.headers.get(h)
                        if val:
                            out_headers[h] = val
                    return Response(
                        content=resp.content,
                        media_type=resp.headers.get("content-type", "audio/wav"),
                        headers=out_headers,
                    )
            except Exception as exc:
                log.warning("[TTS] Cloud TTS gagal: %s", exc)

        raise HTTPException(
            status_code=503,
            detail={"error": "tts_unavailable", "message": "Voicebox/Cloud Furina belum aktif, gunakan fallback TTS lokal."},
        )

    return router
