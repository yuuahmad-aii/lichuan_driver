# Modbus Positional Deviation Monitor
Aplikasi Flutter untuk membaca nilai deviasi posisi secara real-time dari perangkat Modbus RTU melalui port serial, menampilkannya dalam bentuk grafik, dan mencatat log ke berkas CSV.

## 🎯 Fitur Utama
1. 🔌 Koneksi Serial

Pilih port COM, sambungkan/disambungkan ke perangkat.
Konfigurasi 115200 baud, 8 data bit, even parity, 1 stop bit.
2. 📡 Polling Modbus RTU

Mengirim permintaan baca register (Function Code 03) tiap 50 ms.
Membaca register 0x01BE (lower) & 0x01BF (upper) → gabung jadi nilai 32‑bit signed.
3. 📈 Grafik Real-time

Menampilkan deviasi posisi menggunakan fl_chart.
Jendela data bergerak hingga 100 titik, sumbu waktu dalam detik.
4. 📝 Pencatatan Data

Pilih folder log, mulai/berhenti rekam.
File CSV berformat Log_Deviation_YYYYMMDD_HHMMSS.csv berisi timestamp & nilai.
5. 🧼 Manajemen Buffer & CRC

Buffering data masuk dan pembersihan otomatis.
CRC16 (Modbus) untuk membentuk frame request.

## 📦 Struktur Utama (di main.dart)
ModbusApp → MaterialApp
DashboardScreen → Stateful widget menangani UI & logika.
Variabel port, koneksi, polling, chart, logging, dan buffer.
Metode penting:
_refreshPorts(), _connect(), _disconnect()
_sendModbusRequest(), _handleIncomingData()
_calculateCRC()
_selectFolder(), _toggleLogging(), _startLogging(), _stopLogging()

## 💡 Cara Menggunakan
Pastikan perangkat Modbus RTU tersambung lewat USB‑serial.
Jalankan aplikasi (flutter run).
Pilih COM port dan tekan Connect.
Pantau nilai deviasi di layar dan grafik.
Untuk menyimpan data, pilih folder, lalu tekan Mulai Rekam.
Tekan Berhenti Rekam dan Disconnect bila selesai.

## 📁 Hasil Log
File CSV disimpan di folder yang dipilih, berisi:

## 🛠️ Kebutuhan Paket
Dependencies di pubspec.yaml:

flutter_libserialport
fl_chart
file_picker
intl
(Tambahkan sesuai versi yang digunakan.)

## 🚀 Pengembangan
Silakan modifikasi parameter Modbus (ID slave, alamat, jumlah register) atau gaya UI sesuai kebutuhan. Aplikasi ini memberi framework sederhana untuk pemantauan deviasi posisi melalui protokol RTU.

