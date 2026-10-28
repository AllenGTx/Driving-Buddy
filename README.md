# 🚗 DrivingBuddy — AI Driver Fatigue Monitoring & Cabin Telemetry

<p align="center">
  <img src="assets/images/DrivingBuddyLogo.png" alt="DrivingBuddy Logo" width="180">
</p>

<p align="center">
  <b>Asisten Cerdas Keselamatan Berkendara Berbasis AI Face Mesh & Telemetri Real-Time</b>
</p>

---

## 📌 Tentang DrivingBuddy

**DrivingBuddy** adalah aplikasi mobile inovatif pendamping pengemudi yang dirancang untuk mencegah kecelakaan fatal akibat kelelahan dan **microsleep**. Menggunakan teknologi **AI On-Device (Google ML Kit Face Mesh)** dan sensor telemetri kabin, aplikasi ini secara mandiri mendeteksi tanda-tanda kantuk secara *real-time* tanpa mengirim video pengemudi ke server (*100% privacy-friendly*).

### 🌟 Fitur Utama

1. **AI Face Mesh Drowsiness & Microsleep Detection (Real-Time)**
   - **Mata (EAR - Eye Aspect Ratio):** Mendeteksi mata terpejam $\ge 1.7$ detik sebagai potensi bahaya fatal microsleep.
   - **Mulut (MAR - Mouth Aspect Ratio):** Mendeteksi frekuensi menguap dan pola kelelahan beruntun.
   - **Orientasi Kepala (Head Tilt & Head Bobbing):** Mendeteksi kepala miring atau tersentak lemas akibat kehilangan kontrol otot leher. Opsi deteksi postur kepala dapat disetel hidup/mati di menu Pengaturan.

2. **Sistem Peringatan Multi-Level & Kustomisasi Alarm**
   - Alarm suara berfrekuensi tinggi otomatis berbunyi ketika kantuk atau microsleep terdeteksi.
   - Mendukung pemilihan file audio kustom (MP3/WAV) langsung dari File Manager / Penyimpanan Ponsel.
   - Pilihan gambar/meme peringatan kustom yang muncul saat bahaya.

3. **100% Automated WhatsApp Emergency SOS (Fonnte Gateway)**
   - Jika alarm berbunyi selama 1 menit penuh tanpa respon tombol *"Saya Sudah Bangun"*, sistem secara otomatis mengirimkan pesan darurat via API WhatsApp Gateway ke nomor kontak darurat keluarga.
   - Pesan darurat menyertakan koordinat titik GPS tepat, tautan Google Maps, dan kecepatan kendaraan saat insiden.

4. **Telemetri GPS & Kartu Berkendara (Strava-Style Driving Card)**
   - Perekaman rute akurat (*GPS breadcrumbs polyline*) mengikuti lekukan jalan raya.
   - Menghitung jarak tempuh, durasi perjalanan, kecepatan rata-rata, dan skor keselamatan berkendara (*Safety Score*).
   - Menghasilkan ringkasan kartu visual keren yang dapat disimpan atau dibagikan ke media sosial.

5. **Mode Offline Penuh (Offline-First)**
   - Pengemudi tetap dapat memulai, memantau, dan menyelesaikan perjalanan di daerah tanpa sinyal internet (*blank spot*).
   - Data sesi disimpan dalam *cache* lokal dan otomatis disinkronkan ke cloud (Firebase Firestore) saat perangkat kembali terhubung ke internet.

6. **Rekomendasi Pitstop & Tempat Istirahat Terdekat**
   - Menemukan SPBU, Rest Area, minimarket, dan kafe terdekat menggunakan integrasi OpenStreetMap / Google Maps.

---

## 🛠️ Prasyarat Lingkungan (Prerequisites)

Sebelum melakukan build atau deployment, pastikan komputer/laptop Anda telah terpasang:

- **Flutter SDK:** Versi 3.24.x atau lebih baru ([Download Flutter](https://docs.flutter.dev/get-started/install))
- **Android SDK & Platform Tools:** Termasuk `adb` (Android Debug Bridge).
- **Java Development Kit (JDK):** JDK 17 atau JDK 21.
- **Git:** Untuk manajemen versi repositori.
- **Ponsel Android:** Minimal Android 8.0 (Oreo) atau lebih baru dengan fitur USB Debugging aktif.

---

## 🚀 Panduan Deploy / Instalasi ke Android

### Langkah 1: Clone Repositori
```bash
git clone https://github.com/AllenGTx/Driving-Buddy.git
cd Driving-Buddy
```

### Langkah 2: Unduh Dependensi Flutter
Jalankan perintah berikut di root folder proyek:
```bash
flutter pub get
```

### Langkah 3: Konfigurasi File Layanan Firebase
Pastikan file konfigurasi Android berikut berada di tempatnya:
- `android/app/google-services.json`
*(Jika menggunakan project Firebase baru, unduh `google-services.json` dari Firebase Console dan letakkan di dalam folder `android/app/`)*.

---

### Langkah 4: Build APK

#### A. Build Debug APK (Untuk Uji Coba Cepat / Development)
```bash
flutter build apk --debug
```
*Hasil APK akan berada di:*  
`build/app/outputs/flutter-apk/app-debug.apk`

#### B. Build Release APK (Untuk Performa Maksimal)
```bash
flutter build apk --release
```
*Hasil APK akan berada di:*  
`build/app/outputs/flutter-apk/app-release.apk`

---

### Langkah 5: Deploy / Pasang ke HP via ADB

1. Hubungkan ponsel Android Anda ke PC/Laptop menggunakan kabel USB.
2. Pastikan **USB Debugging (Debugging USB)** sudah diaktifkan di menu *Opsi Pengembang (Developer Options)* pada ponsel.
3. Periksa apakah perangkat terdeteksi dengan menjalankan:
   ```bash
   adb devices
   ```
4. Pasang APK langsung ke HP Anda:

   **Untuk Windows (Command Prompt / PowerShell):**
   ```cmd
   C:\Android\platform-tools\adb.exe install -r "build\app\outputs\flutter-apk\app-debug.apk"
   ```
   *Atau jika `adb` sudah terdaftar di PATH lingkungan:*
   ```bash
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

5. Aplikasi **DrivingBuddy** akan langsung terpasang dan siap digunakan di ponsel Anda! 🎉

---

## 📱 Izin Perangkat (Permissions) yang Digunakan

Aplikasi memerlukan beberapa izin sistem Android agar fitur bekerja optimal:
- **Kamera (`android.permission.CAMERA`):** Untuk sensor pendeteksi wajah AI real-time.
- **Lokasi (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`):** Untuk telemetri kecepatan GPS, rute peta, dan pencarian tempat istirahat terdekat.
- **Penyimpanan / Berkas Audio:** Untuk memilih audio peringatan kustom.
- **Internet (`android.permission.INTERNET`):** Untuk pengiriman sinyal darurat SOS otomatis, peta, dan sinkronisasi cloud.

---

## 📄 Lisensi & Kontributor

Dikembangkan dengan dedikasi untuk keselamatan berkendara di Indonesia.  
- **Pengembang:** [AllenGTx](https://github.com/AllenGTx) & [Vodyanitsa1](https://github.com/Vodyanitsa1)
