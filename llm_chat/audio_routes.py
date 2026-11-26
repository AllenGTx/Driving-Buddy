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

# PENTING: Whisper `prompt` adalah contoh kalimat transkrip sebelumnya, BUKAN instruksi sistem!
# Jangan gunakan kata seperti "Ejaan nama tepat:" karena memicu halusinasi "X dieja X-Y-Z".
STT_VOCAB_PROMPT = (
    "Halo Rina, Furina, Jane, John. Tolong bantu saya cari tempat istirahat, "
    "rest area, SPBU Pertamina, Indomaret, Alfamart, atau hotel terdekat."
)

_HALLUCINATION_PATTERNS = (
    re.compile(r"\bdieja\b", re.IGNORECASE),
    re.compile(r"\b(?:[a-zA-Z]-){3,}[a-zA-Z]\b"),
    re.compile(r"terima\s+kasih\s+(?:telah|sudah)\s+menonton", re.IGNORECASE),
    re.compile(r"jangan\s+lupa\s+(?:like|subscribe|komen)", re.IGNORECASE),
    re.compile(r"(?:subtitle|subtitel|diterjemahkan)\s+oleh", re.IGNORECASE),
    re.compile(r"amara\.org", re.IGNORECASE),
)


def clean_stt_transcript(raw_text: str) -> str:
    """Bersihkan artefak halusinasi Whisper saat audio berisi derau kabin atau hening."""
    text = (raw_text or "").strip()
    if not text:
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
    voicebox_url = (env.get("VOICEBOX_URL") or os.environ.get("VOICEBOX_URL") or "http://127.0.0.1:17493").rstrip("/")
    skip_local_voicebox = (env.get("SKIP_LOCAL_VOICEBOX") or os.environ.get("SKIP_LOCAL_VOICEBOX") or "") == "1"
    furina_cloud_url = (env.get("FURINA_TTS_URL") or os.environ.get("FURINA_TTS_URL") or "").rstrip("/")

    router = APIRouter(tags=["audio"])

    def _client(timeout_s: float) -> httpx.AsyncClient:
        if http is not None:
            return http
        return httpx.AsyncClient(timeout=httpx.Timeout(timeout_s, connect=min(2.0, timeout_s)))

    @router.post("/stt", summary="Transkripsi suara pengemudi dengan rantai failover otomatis")
    async def transcribe_audio(
        file: UploadFile = File(...),
        hint: Optional[str] = Form(default=None),
    ) -> Dict[str, Any]:
        raw = await file.read()
        if not raw or len(raw) > 8 * 1024 * 1024:
            raise HTTPException(status_code=422, detail={"error": "invalid_audio", "message": "Ukuran audio tidak valid."})

        filename = file.filename or "speech.m4a"
        mime = file.content_type or "audio/mp4"
        clean_hint = re.sub(r"(?i)nama\s*buddy\s*:\s*", "", (hint or "")).strip()
        vocab = f"Halo {clean_hint}. {STT_VOCAB_PROMPT}" if clean_hint and clean_hint.lower() not in STT_VOCAB_PROMPT.lower() else STT_VOCAB_PROMPT
        errors = []

        # Tier 1: Groq Whisper (2 kolam kuota terpisah: large-v3-turbo -> large-v3)
        if groq_key:
            for w_model in ("whisper-large-v3-turbo", "whisper-large-v3"):
                try:
                    client = _client(4.5)
                    try:
                        resp = await client.post(
                            "https://api.groq.com/openai/v1/audio/transcriptions",
                            headers={"Authorization": f"Bearer {groq_key}"},
                            data={
                                "model": w_model,
                                "language": "id",
                                "temperature": "0",
                                "prompt": vocab,
                            },
                            files={"file": (filename, raw, mime)},
                        )
                        if resp.status_code == 200:
                            text = clean_stt_transcript(resp.json().get("text") or "")
                            if text:
                                return {"text": text, "provider": f"groq_{w_model}"}
                            return {"text": "", "provider": f"groq_{w_model}_empty"}
                        errors.append(f"groq({w_model}):{resp.status_code}")
                        if resp.status_code != 429 and resp.status_code < 500:
                            break
                    finally:
                        if http is None:
                            await client.aclose()
                except Exception as exc:
                    errors.append(f"groq({w_model}):{type(exc).__name__}")

        # Tier 2: Voicebox Local Whisper (:17493/transcribe) bila tidak di-skip
        if not skip_local_voicebox:
            try:
                client = _client(2.5)
                try:
                    resp = await client.post(
                        f"{voicebox_url}/transcribe",
                        files={"file": (filename, raw, mime)},
                    )
                    if resp.status_code == 200:
                        body = resp.json()
                        text = clean_stt_transcript(body.get("text") or body.get("transcript") or "")
                        if text:
                            return {"text": text, "provider": "voicebox_whisper"}
                    errors.append(f"voicebox:{resp.status_code}")
                finally:
                    if http is None:
                        await client.aclose()
            except Exception as exc:
                errors.append(f"voicebox:{type(exc).__name__}")

        # Tier 3: Gemini Multimodal Audio STT
        if gemini_key:
            try:
                client = _client(5.0)
                try:
                    b64 = base64.b64encode(raw).decode("ascii")
                    payload = {
                        "contents": [{
                            "parts": [
                                {
                                    "text": (
                                        "Transkripsikan ucapan Bahasa Indonesia pada audio ini persis apa adanya "
                                        "tanpa tambahan penjelasan atau ejaan. Jika hanya suara bising/hening tanpa "
                                        "ucapan manusia, kembalikan teks kosong."
                                    )
                                },
                                {"inline_data": {"mime_type": mime, "data": b64}},
                            ]
                        }],
                        "generationConfig": {"temperature": 0.0, "maxOutputTokens": 128},
                    }
                    resp = await client.post(
                        f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={gemini_key}",
                        json=payload,
                    )
                    if resp.status_code == 200:
                        cands = resp.json().get("candidates") or []
                        if cands:
                            parts = cands[0].get("content", {}).get("parts") or []
                            text = clean_stt_transcript("".join(p.get("text", "") for p in parts))
                            return {"text": text, "provider": "gemini_audio"}
                    errors.append(f"gemini:{resp.status_code}")
                finally:
                    if http is None:
                        await client.aclose()
            except Exception as exc:
                errors.append(f"gemini:{type(exc).__name__}")

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
                try:
                    prof_resp = await client.get(f"{voicebox_url}/profiles")
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

                    resp = await client.post(f"{voicebox_url}/generate", json=gen_payload)
                    if resp.status_code == 200:
                        ctype = resp.headers.get("content-type", "")
                        if "audio/" in ctype or resp.content[:4] in (b"RIFF", b"ID3\x03", b"ID3\x04", b"\xff\xfb"):
                            return Response(content=resp.content, media_type=ctype if "audio/" in ctype else "audio/wav")
                        data = resp.json()
                        audio_url = data.get("audio_url") or data.get("url") or data.get("path")
                        if audio_url:
                            dl_url = audio_url if str(audio_url).startswith("http") else f"{voicebox_url}/{str(audio_url).lstrip('/')}"
                            audio_resp = await client.get(dl_url)
                            if audio_resp.status_code == 200:
                                return Response(content=audio_resp.content, media_type=audio_resp.headers.get("content-type", "audio/wav"))
                finally:
                    if http is None:
                        await client.aclose()
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
                try:
                    resp = await client.post(
                        furina_cloud_url,
                        headers=fwd_headers,
                        json={
                            "text": req.text,
                            "language": req.language,
                            "voice_profile": req.voice_profile.lower(),
                        },
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
                finally:
                    if http is None:
                        await client.aclose()
            except Exception as exc:
                log.warning("[TTS] Cloud TTS gagal: %s", exc)

        raise HTTPException(
            status_code=503,
            detail={"error": "tts_unavailable", "message": "Voicebox/Cloud Furina belum aktif, gunakan fallback TTS lokal."},
        )

    return router
