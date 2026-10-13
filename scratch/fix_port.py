with open("lib/main.dart", "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace("Menguji koneksi ke $ip:$kServerPort...", "Menguji koneksi ke $ip...")
content = content.replace("Berhasil terhubung ke $ip:$kServerPort", "Berhasil terhubung ke $ip")
content = content.replace("Gagal: Tidak bisa reach $ip:$kServerPort", "Gagal: Tidak bisa reach $ip")

with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(content)
print("done")
