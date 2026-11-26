# Deploy Gratis 24/7 ke Hugging Face Spaces

1. Buka [huggingface.co/new-space](https://huggingface.co/new-space), buat Space baru dengan SDK **Docker** (pilih **Blank**) dan hardware **CPU basic (Free · 2 vCPU · 16 GB RAM)**.
2. Di tab **Settings -> Variables and secrets**, tambahkan Secrets berikut:
   - `GROQ_API_KEY`: API key dari `console.groq.com`
   - `GEMINI_API_KEY`: API key dari `aistudio.google.com`
   - `CEREBRAS_API_KEY`: API key dari `cloud.cerebras.ai`
   - `FURINA_TTS_URL`: (opsional) URL endpoint Space TTS Furina
3. Salin `Dockerfile.hf` menjadi `Dockerfile` di repositori Space, bersama `server.py`, `requirements-llm.txt`, dan folder `llm_chat/`, lalu push ke Space.
4. URL publik Space kamu akan berformat `https://<username>-<nama-space>.hf.space`. Masukkan URL tersebut di pengaturan server aplikasi atau `--dart-define=LLM_API_BASE_URL=https://<username>-<nama-space>.hf.space`.
