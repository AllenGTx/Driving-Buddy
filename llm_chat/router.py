"""Endpoint HTTP untuk chat dengan LLM.

Dipasang ke aplikasi FastAPI yang sudah ada:

    from llm_chat import build_router
    app.include_router(build_router())

Prinsip: alarm kantuk TIDAK boleh bergantung pada LLM. Kalau LLM mati/lambat,
endpoint tetap menjawab (HTTP 200, `fallback: true`) dengan balasan darurat.
"""
from __future__ import annotations

import base64
import logging
import math
import time
import urllib.parse
from typing import Any, Awaitable, Callable, Dict, Optional, Tuple

from fastapi import APIRouter, HTTPException, Path, Query, Request
from fastapi.responses import JSONResponse, RedirectResponse, Response, StreamingResponse

from .audio_routes import build_audio_router
from .client import BaseLLM, FallbackChainLLM, LLMError, make_llm
from .config import Settings, load_fallback_chain, load_settings
from .prompts import build_messages, clean_reply, pick_fallback
from .schemas import SESSION_ID_PATTERN, ChatRequest, ChatResponse
from .store import RateLimiter, SessionStore
from .web_search import (
    assemble_full_music_bytes,
    iter_resolved_music_bytes,
    needs_live_web_search,
    resolve_in_app_music_stream,
    search_live_web,
    search_music_track,
)

log = logging.getLogger("driving_buddy.llm")

DEEP_CHECK_CACHE_S = 30.0


InlineTtsFn = Callable[[str, str, str, str], Awaitable[Tuple[bytes, str]]]


def build_router(
    settings: Optional[Settings] = None,
    llm: Optional[BaseLLM] = None,
    clock: Callable[[], float] = time.monotonic,
    inline_tts_fn: Optional[InlineTtsFn] = None,
) -> APIRouter:
    """Buat router /chat, /stt, dan /tts. Tanpa argumen = baca konfigurasi dari environment / file .env."""
    auto_chain = settings is None and llm is None
    settings = settings or load_settings()
    if llm is None and settings.configured:
        if auto_chain:
            chain_settings = load_fallback_chain()
            if len(chain_settings) > 1:
                llm = FallbackChainLLM([make_llm(s) for s in chain_settings])
            else:
                llm = make_llm(settings)
        else:
            llm = make_llm(settings)

    store = SessionStore(settings.max_sessions, settings.session_ttl_s, settings.history_turns, clock=clock)
    session_limiter = RateLimiter(settings.rate_per_session_per_min, clock=clock)
    global_limiter = RateLimiter(settings.rate_global_per_min, clock=clock)
    deep_cache: Dict[str, Tuple[float, Dict[str, Any]]] = {}

    if not settings.configured:
        log.error("[LLM] chat NONAKTIF: %s", settings.problem)
    elif settings.provider == "mock":
        log.warning("[LLM] provider=mock -> balasan palsu, belum terhubung ke LLM sungguhan")
    else:
        log.info("[LLM] siap: provider=%s model=%s host=%s", settings.provider, settings.model,
                 settings.base_url_host)

    router = APIRouter(tags=["llm"])

    def check_rate_limit(session_id: str) -> None:
        for limiter, key in ((session_limiter, session_id), (global_limiter, "*")):
            allowed, wait_s = limiter.hit(key)
            if not allowed:
                retry = max(1, math.ceil(wait_s))
                raise HTTPException(
                    status_code=429,
                    detail={"error": "rate_limited", "retry_after_s": retry},
                    headers={"Retry-After": str(retry)},
                )

    @router.post(
        "/chat",
        response_model=ChatResponse,
        summary="Kirim ucapan pengemudi, terima balasan singkat dari Buddy (LLM)",
        responses={
            429: {"description": "Terlalu banyak permintaan (lihat header Retry-After)."},
            503: {"description": "LLM belum dikonfigurasi di server (cek GET /chat/health)."},
        },
    )
    async def chat(req: ChatRequest, request: Request) -> ChatResponse:
        if llm is None:
            raise HTTPException(
                status_code=503,
                detail={"error": "llm_not_configured", "message": settings.problem},
            )
        check_rate_limit(req.session_id)

        started = time.perf_counter()
        session = store.get(req.session_id)
        fallback, error = False, None
        model_name = llm.model
        provider_used = settings.provider
        audio_b64: Optional[str] = None
        audio_mime: Optional[str] = None
        tts_error: Optional[str] = None

        async with session.lock:
            if req.reset:
                session.history.clear()
            web_ctx: Optional[str] = None
            if auto_chain and needs_live_web_search(req.message):
                web_ctx = await search_live_web(req.message, timeout_s=2.8)
            messages = build_messages(
                list(session.history),
                req.message,
                req.driver_state,
                buddy_name=req.buddy_name,
                voice_profile=req.voice_profile,
                nearby_places=req.nearby_places,
                web_search_context=web_ctx,
            )
            try:
                result = await llm.complete(messages)
                reply = clean_reply(
                    result.text,
                    settings.max_reply_chars,
                    voice_profile=req.voice_profile,
                    buddy_name=req.buddy_name,
                )
                if not reply:
                    raise LLMError("empty", "balasan kosong setelah dibersihkan")
                session.add_turn(req.message, reply)
                model_name = result.model or model_name
                if isinstance(llm, FallbackChainLLM) and getattr(result, "provider", None):
                    provider_used = result.provider
            except LLMError as err:
                fallback, error = True, err.kind
                reply = pick_fallback(req.driver_state, req.message, buddy_name=req.buddy_name)
                level = log.error if err.kind in ("auth", "not_found", "bad_request") else log.warning
                level("[LLM] gagal (%s), pakai balasan darurat: %s", err.kind, err.detail[:200])
            except Exception:  # bug tak terduga: jangan sampai chat menjatuhkan aplikasi
                fallback, error = True, "internal"
                reply = pick_fallback(req.driver_state, req.message, buddy_name=req.buddy_name)
                log.exception("[LLM] error tak terduga di /chat")

        if req.include_audio and inline_tts_fn is not None and not fallback and reply:
            prof = (req.voice_profile or "furina").strip().lower()
            client_ip = request.headers.get("x-forwarded-for") or (
                request.client.host if request.client else ""
            )
            try:
                audio_bytes, mime = await inline_tts_fn(reply, prof, req.language, client_ip)
                if audio_bytes and len(audio_bytes) > 256:
                    audio_b64 = base64.b64encode(audio_bytes).decode("ascii")
                    audio_mime = mime
            except HTTPException as exc:
                if exc.status_code == 503 and prof == "furina":
                    tts_error = "furina_exhausted"
            except Exception as exc:
                if prof == "furina" and "exhausted" in str(exc).lower():
                    tts_error = "furina_exhausted"
                log.debug("[LLM] inline TTS dilewati (%s)", exc)

        return ChatResponse(
            reply=reply,
            session_id=req.session_id,
            provider=provider_used,
            model=model_name,
            latency_ms=int((time.perf_counter() - started) * 1000),
            fallback=fallback,
            error=error,
            audio_b64=audio_b64,
            audio_mime=audio_mime,
            tts_error=tts_error,
        )

    @router.delete("/chat/{session_id}", summary="Hapus riwayat percakapan satu sesi")
    async def clear_chat(session_id: str = Path(..., min_length=1, max_length=64, pattern=SESSION_ID_PATTERN)):
        return {"session_id": session_id, "cleared": store.reset(session_id)}

    @router.get("/chat/health", summary="Cek konfigurasi LLM (deep=true: cek koneksi & nama model ke provider)")
    async def chat_health(deep: bool = False) -> Dict[str, Any]:
        info: Dict[str, Any] = {
            "status": "ok" if llm is not None else "not_configured",
            "provider": settings.provider,
            "model": settings.model,
            "host": settings.base_url_host or None,
            "problem": settings.problem,
            "active_sessions": len(store),
        }
        if deep and llm is not None:
            now = clock()
            cached = deep_cache.get("deep")
            if cached is None or now - cached[0] > DEEP_CHECK_CACHE_S:
                deep_cache["deep"] = (now, await _deep_check(llm, settings))
            info.update(deep_cache["deep"][1])
        return info

    @router.get("/music/search", summary="Cari lagu resmi & antrean playlist untuk Dynamic Island in-app")
    async def music_search(q: str = Query(..., min_length=1, max_length=160)) -> Dict[str, Any]:
        return await search_music_track(q)

    @router.get("/music/stream", summary="Alirkan audio lagu penuh langsung ke dalam Dynamic Island tanpa keluar aplikasi")
    async def music_stream(
        q: str = Query(..., min_length=1, max_length=180),
        dur: int = Query(210, ge=15, le=900),
        mode: str = Query("stream", description="'stream'=streaming bytes, 'url'=JSON URL langsung/download, 'file'=file utuh seekable"),
    ):
        info = await resolve_in_app_music_stream(q, target_dur_s=dur)
        if not info:
            raise HTTPException(status_code=404, detail={"error": "music_stream_not_found"})

        if mode == "url":
            stream_mode = info.get("mode")
            if stream_mode == "direct_url":
                return JSONResponse({
                    "url": info["url"],
                    "mime": info.get("mime", "audio/mpeg"),
                    "duration_s": info.get("duration_s", dur),
                    "mode": "direct",
                })
            # Untuk fmp4_segments tanpa DRM: arahkan Flutter mengunduh file utuh via mode=file (100% bisa diputar penuh!)
            return JSONResponse({
                "url": f"/music/stream?q={urllib.parse.quote(q)}&dur={dur}&mode=file",
                "mime": info.get("mime", "audio/mp4"),
                "duration_s": info.get("duration_s", dur),
                "mode": "download",
            })

        if mode == "file":
            full_bytes = await assemble_full_music_bytes(info)
            if not full_bytes or len(full_bytes) < 4096:
                raise HTTPException(status_code=502, detail={"error": "music_assembly_failed"})
            return Response(
                content=full_bytes,
                media_type=info.get("mime", "audio/mp4"),
                headers={
                    "Cache-Control": "public, max-age=300",
                    "Accept-Ranges": "bytes",
                    "Content-Length": str(len(full_bytes)),
                    "X-Music-Duration": str(info.get("duration_s", dur)),
                },
            )

        return StreamingResponse(
            iter_resolved_music_bytes(info),
            media_type=info.get("mime", "audio/mp4"),
            headers={
                "Cache-Control": "public, max-age=300",
                "X-Music-Duration": str(info.get("duration_s", dur)),
                "X-Music-Mode": str(info.get("mode", "stream")),
            },
        )

    router.include_router(build_audio_router())
    return router


async def _deep_check(llm: BaseLLM, settings: Settings) -> Dict[str, Any]:
    """Tanya daftar model ke provider: membuktikan API key + koneksi benar tanpa memakai token."""
    try:
        ids = await llm.list_models()
    except LLMError as err:
        log.warning("[LLM] deep check gagal (%s): %s", err.kind, err.detail[:200])
        return {"reachable": False, "error": err.kind, "http_status": err.status}
    return {"reachable": True, "model_available": settings.model in ids, "models_listed": len(ids)}
