"""Generate aset audio offline instan (0ms, 0 kuota) untuk Jane, John, dan sinyal putus Furina/Jane/John."""
from __future__ import annotations

import time
from pathlib import Path
import httpx

SPACE_URL = "https://allengt-driving-buddy.hf.space"
ASSETS_AUDIO = Path(__file__).resolve().parent.parent / "assets" / "audio"

BUNDLES = {
    "jane": {
        "wake_1.wav": "Ya? Ada yang bisa Jane bantu?",
        "wake_2.wav": "Halo! Mau tanya apa nih?",
        "wake_3.wav": "Iya, Jane dengerin kok!",
        "drowsy_yawn.wav": "Eh, kamu sudah menguap dua kali nih dalam lima menit! Kalau mulai ngantuk, menepi sebentar ya.",
        "drowsy_eyes.wav": "Aduh, matamu mulai kelihatan sayu nih... Yuk cari tempat istirahat sebentar ya!",
        "drowsy_general.wav": "Kamu kelihatan mulai lelah di jalan. Yuk istirahat sebentar biar segar lagi!",
        "offline_signal.wav": "Wah, sinyal internet lagi putus nih... Tapi tenang, Jane tetap siaga jagain mata kamu di jalan ya!",
    },
    "john": {
        "wake_1.wav": "Ya bro? Ada yang bisa John bantu?",
        "wake_2.wav": "Siap! Mau tanya apa nih?",
        "wake_3.wav": "Iya bro, John dengerin!",
        "drowsy_yawn.wav": "Eh bro, kamu udah menguap dua kali nih dalam lima menit! Kalau ngantuk, menepi dulu sebentar ya.",
        "drowsy_eyes.wav": "Waduh, mata kamu mulai sayu tuh... Coba cari rest area terdekat dulu yuk!",
        "drowsy_general.wav": "Kelihatannya kamu mulai capek nyetir nih. Istirahat sebentar yuk biar fokus lagi!",
        "offline_signal.wav": "Waduh, sinyal internet lagi hilang nih bro... Tenang aja, sensor keselamatan tetap aktif jagain kamu!",
    },
    "furina": {
        "offline_signal.wav": "Eh, sinyalnya lagi putus nih... Tapi tenang ya, Rina tetap di sini jagain kamu menyetir kok!",
    },
}


def wait_space_running() -> None:
    for _ in range(18):
        try:
            r = httpx.get("https://huggingface.co/api/spaces/AllenGT/driving-buddy", timeout=10.0)
            st = r.json().get("runtime", {}).get("stage")
            if st == "RUNNING":
                return
            print("Menunggu HF Space RUNNING (saat ini:", st, ")...")
        except Exception:
            pass
        time.sleep(5)


def main() -> None:
    wait_space_running()
    with httpx.Client(timeout=45.0) as client:
        for profile, files in BUNDLES.items():
            out_dir = ASSETS_AUDIO / profile
            out_dir.mkdir(parents=True, exist_ok=True)
            for fname, text in files.items():
                resp = client.post(
                    f"{SPACE_URL}/tts",
                    json={"text": text, "voice_profile": profile, "language": "id"},
                )
                resp.raise_for_status()
                target = out_dir / fname
                target.write_bytes(resp.content)
                prov = resp.headers.get("x-furina-provider") or resp.headers.get("x-voice-provider")
                print(f"[{profile}] {fname} -> {len(resp.content)} bytes (provider={prov})")


if __name__ == "__main__":
    main()
