import asyncio
from fastapi import FastAPI
from fastapi.testclient import TestClient

from llm_chat.client import BaseLLM, FallbackChainLLM, LLMError, LLMResult
from llm_chat.config import load_fallback_chain, load_settings
from llm_chat.prompts import build_messages, pick_fallback
from llm_chat.router import build_router
from llm_chat.schemas import NearbyPlaceBrief


class _FailLLM(BaseLLM):
    def __init__(self, provider: str, kind: str = "rate_limited"):
        self.provider = provider
        self.model = f"{provider}-m"
        self._kind = kind

    async def complete(self, messages):
        raise LLMError(self._kind, "kuota habis", status=429)

    async def list_models(self):
        return [self.model]


class _OkLLM(BaseLLM):
    def __init__(self, provider: str, reply: str):
        self.provider = provider
        self.model = f"{provider}-m"
        self._reply = reply

    async def complete(self, messages):
        return LLMResult(text=self._reply, model=self.model, provider=self.provider)

    async def list_models(self):
        return [self.model]


def test_fallback_chain_moves_from_groq_to_gemini_to_cerebras():
    chain = FallbackChainLLM([
        _FailLLM("freellmapi", "network"),
        _FailLLM("groq", "rate_limited"),
        _OkLLM("cerebras", "Halo Allen, aku siap nemenin kamu nyetir."),
    ])
    res = asyncio.run(chain.complete([{"role": "user", "content": "halo"}]))
    assert res.provider == "cerebras"
    assert "Allen" in res.text


def test_load_fallback_chain_orders_providers():
    chain = load_fallback_chain({
        "FREELLM_API_KEY": "fl_123",
        "GROQ_API_KEY": "gsk_123",
        "GEMINI_API_KEY": "AIza123",
        "CEREBRAS_API_KEY": "csk-123",
    })
    dedup_providers = list(dict.fromkeys(s.provider for s in chain))
    assert dedup_providers == ["freellmapi", "groq", "gemini", "cerebras"]
    # Pastikan satu GROQ_API_KEY membuka beberapa kolam model gratis terpisah
    groq_models = [s.model for s in chain if s.provider == "groq"]
    assert "openai/gpt-oss-120b" in groq_models
    assert "qwen/qwen3.8-27b" in groq_models
    assert "openai/gpt-oss-20b" in groq_models


def test_tired_fallback_uses_custom_buddy_name_without_error_jargon():
    msg = pick_fallback(None, "halo", buddy_name="Rina")
    assert msg == "Sorry nih, Rina lagi capek banget, sorry banget ya aku butuh istirahat."
    assert "error" not in msg.lower()


def test_places_context_injected_into_system_prompt():
    places = [NearbyPlaceBrief(name="Indomaret Telaga Mas", category="Minimarket", distance_m=320, ahead=True)]
    msgs = build_messages([], "Dimana Indomaret terdekat?", None, buddy_name="Rina", nearby_places=places)
    sys_txt = msgs[0]["content"]
    assert "Indomaret Telaga Mas" in sys_txt
    assert "320 meter" in sys_txt
    assert '"Rina"' in sys_txt


def test_chat_endpoint_returns_tired_message_when_all_providers_exhausted():
    app = FastAPI()
    s = load_settings({"LLM_PROVIDER": "groq", "LLM_API_KEY": "gsk_x"})
    app.include_router(build_router(s, llm=FallbackChainLLM([_FailLLM("groq"), _FailLLM("gemini")])))
    client = TestClient(app)
    r = client.post("/chat", json={
        "session_id": "sesi-1",
        "message": "Halo namaku Allen",
        "buddy_name": "Rina",
    })
    assert r.status_code == 200
    body = r.json()
    assert body["fallback"] is True
    assert "Sorry nih, Rina lagi capek banget" in body["reply"]
