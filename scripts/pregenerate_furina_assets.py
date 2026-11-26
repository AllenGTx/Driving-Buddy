"""Generate 7 file audio tetap suara Furina Indonesia (Edge-TTS id-ID-GadisNeural + RVC v2) lewat HF Space."""
from __future__ import annotations

from pathlib import Path
import httpx

SPACE_URL = "https://allengt-driving-buddy.hf.space"
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio" / "furina"

LINES = {
    "wake_1.wav": "Ya? Ada apa?",
    "wake_2.wav": "Ya? Mau tanya apa?",
    "wake_3.wav": "Ya? Gimana sayang...?",
    "drowsy_yawn.wav": "Eh, kamu sudah menguap dua kali nih dalam lima menit. Kalau mulai ngantuk, menepi sebentar ya.",
    "drowsy_eyes.wav": "Aduh, mengantuk ya? Coba cari tempat istirahat ya.",
    "drowsy_general.wav": "Kamu kelihatan mulai lelah di jalan. Yuk istirahat sebentar biar segar lagi.",
    "tired.wav": "Maaf ya... Furina lagi capek nih, butuh istirahat. Mungkin kamu mau bicara sama Jane?",
}


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old_file in ("tired_normal.wav", "tired_drowsy.wav"):
        old_path = OUT_DIR / old_file
        if old_path.exists():
            old_path.unlink()

    with httpx.Client(timeout=90.0) as client:
        for filename, text in LINES.items():
            resp = client.post(
                f"{SPACE_URL}/tts",
                json={"text": text, "voice_profile": "furina", "language": "id"},
            )
            resp.raise_for_status()
            target = OUT_DIR / filename
            target.write_bytes(resp.content)
            print(f"Tersimpan: {target.name} ({len(resp.content)} bytes)")


if __name__ == "__main__":
    main()
