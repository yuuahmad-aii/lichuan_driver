import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MPU6050 DAQ Viewer',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: const Color(0xFF1E1E2C),
      ),
      home: const DashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Serial Port Variables
  List<String> _availablePorts = [];
  String? _selectedPort;
  SerialPort? _serialPort;
  SerialPortReader? _reader;
  StreamSubscription? _subscription;
  bool _isConnected = false;

  // Data Processing Variables
  String _buffer = '';
  final int _maxDataPoints = 200; // Jumlah titik yang ditampilkan di grafik
  final List<FlSpot> _dataAx = [];
  final List<FlSpot> _dataAy = [];
  final List<FlSpot> _dataAz = [];
  double _timeCounter = 0;

  // ==== KONFIGURASI GRAFIK ====
  // Sesuaikan nilai ini dengan output MPU6050 Anda.
  // Jika output MPU6050 adalah RAW (mentah), rentangnya biasanya -32768 hingga +32767.
  // Jika output sudah dikonversi ke satuan G, rentangnya biasanya -2.0 hingga +2.0 (atau -4 hingga 4).
  final double _minY = -35000; 
  final double _maxY = 35000;  

  // Logging Variables
  bool _isLogging = false;
  String? _selectedDirectory;
  IOSink? _logFileSink;
  int _logCount = 0;

  // UI Update Timer
  Timer? _uiUpdateTimer;

  @override
  void initState() {
    super.initState();
    _refreshPorts();
    
    // Timer untuk merender grafik setiap 50ms (20 FPS)
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_isConnected && mounted) {
        setState(() {}); // Paksa refresh UI
      }
    });
  }

  @override
  void dispose() {
    _disconnect();
    _uiUpdateTimer?.cancel();
    super.dispose();
  }

  void _refreshPorts() {
    setState(() {
      _availablePorts = SerialPort.availablePorts;
      if (!_availablePorts.contains(_selectedPort)) {
        _selectedPort = null;
      }
    });
  }

  void _connect() {
    if (_selectedPort == null) return;

    try {
      _serialPort = SerialPort(_selectedPort!);
      if (!_serialPort!.openReadWrite()) {
        _showError('Gagal membuka port $_selectedPort');
        return;
      }

      SerialPortConfig config = _serialPort!.config;
      config.baudRate = 115200;
      _serialPort!.config = config;

      _reader = SerialPortReader(_serialPort!);
      _subscription = _reader!.stream.listen(_onDataReceived);

      setState(() {
        _isConnected = true;
        _dataAx.clear();
        _dataAy.clear();
        _dataAz.clear();
        _timeCounter = 0;
      });
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _disconnect() {
    _stopLogging();
    _subscription?.cancel();
    _reader?.close();
    if (_serialPort != null && _serialPort!.isOpen) {
      _serialPort!.close();
    }
    setState(() {
      _isConnected = false;
    });
  }

  void _onDataReceived(List<int> data) {
    // Menggunakan String.fromCharCodes lebih aman untuk data ASCII 
    // berkecepatan tinggi dibanding utf8.decode untuk menghindari crash byte terputus
    _buffer += String.fromCharCodes(data);
    int index;
    // Parsing per baris
    while ((index = _buffer.indexOf('\n')) != -1) {
      String line = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);
      if (line.isNotEmpty) {
        _processDataLine(line);
      }
    }
  }

  void _processDataLine(String line) {
    // Simpan ke log jika sedang merekam
    if (_isLogging && _logFileSink != null) {
      _logFileSink!.writeln(line);
      _logCount++;
    }

    // Pisahkan berdasarkan koma (ax,ay,az,gx,gy,gz)
    List<String> parts = line.split(',');
    if (parts.length >= 6) {
      double? ax = double.tryParse(parts[0]);
      double? ay = double.tryParse(parts[1]);
      double? az = double.tryParse(parts[2]);

      if (ax != null && ay != null && az != null) {
        _timeCounter += 1;

        _dataAx.add(FlSpot(_timeCounter, ax));
        _dataAy.add(FlSpot(_timeCounter, ay));
        _dataAz.add(FlSpot(_timeCounter, az));

        // Buang data lama agar grafik memiliki efek "scrolling"
        if (_dataAx.length > _maxDataPoints) {
          _dataAx.removeAt(0);
          _dataAy.removeAt(0);
          _dataAz.removeAt(0);
        }
      }
    }
  }

  Future<void> _pickDirectory() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _selectedDirectory = result;
      });
    }
  }

  void _startLogging() {
    if (_selectedDirectory == null) {
      _showError('Pilih folder penyimpanan terlebih dahulu!');
      return;
    }
    
    String timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    String fileName = '$_selectedDirectory\\log_mpu6050_$timestamp.csv';
    
    File file = File(fileName);
    _logFileSink = file.openWrite();
    _logFileSink!.writeln('ax,ay,az,gx,gy,gz');
    
    setState(() {
      _isLogging = true;
      _logCount = 0;
    });
  }

  void _stopLogging() async {
    if (_isLogging) {
      setState(() {
        _isLogging = false;
      });
      await _logFileSink?.flush();
      await _logFileSink?.close();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Log disimpan. Total data: $_logCount baris')),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MPU6050 Vibration DAQ (1kHz)'),
        backgroundColor: const Color(0xFF2C2C3E),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isConnected ? null : _refreshPorts,
            tooltip: 'Refresh COM Ports',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // TOP PANEL: Koneksi Port Serial
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFF2C2C3E), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Text('COM Port: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: _selectedPort,
                    hint: const Text('Pilih Port'),
                    items: _availablePorts.map((String port) {
                      return DropdownMenuItem<String>(value: port, child: Text(port));
                    }).toList(),
                    onChanged: _isConnected ? null : (val) => setState(() => _selectedPort = val),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConnected ? Colors.redAccent : Colors.green,
                    ),
                    onPressed: _isConnected ? _disconnect : _connect,
                    child: Text(_isConnected ? 'Disconnect' : 'Connect'),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // MIDDLE PANEL: Grafik Real-Time
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF2C2C3E), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Grafik Akselerasi Real-Time (X: Merah, Y: Hijau, Z: Biru)', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _dataAx.isEmpty 
                        ? const Center(child: Text('Menunggu data...'))
                        : LineChart(
                            LineChartData(
                              // PERBAIKAN 1: Mencegah grafik sumbu X bergetar (Auto-scale X dimatikan)
                              minX: _dataAx.first.x,
                              maxX: _dataAx.first.x + _maxDataPoints,
                              
                              // PERBAIKAN 2: Mencegah grafik sumbu Y bergetar (Auto-scale Y dimatikan)
                              minY: _minY, 
                              maxY: _maxY, 

                              gridData: FlGridData(show: true, drawVerticalLine: false),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50)),
                                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.withAlpha(200))),
                              lineBarsData: [
                                // Line Akselerasi X
                                LineChartBarData(
                                  spots: _dataAx,
                                  isCurved: false,
                                  color: Colors.redAccent,
                                  barWidth: 2,
                                  dotData: FlDotData(show: false),
                                ),
                                // Line Akselerasi Y
                                LineChartBarData(
                                  spots: _dataAy,
                                  isCurved: false,
                                  color: Colors.greenAccent,
                                  barWidth: 2,
                                  dotData: FlDotData(show: false),
                                ),
                                // Line Akselerasi Z
                                LineChartBarData(
                                  spots: _dataAz,
                                  isCurved: false,
                                  color: Colors.lightBlueAccent,
                                  barWidth: 2,
                                  dotData: FlDotData(show: false),
                                ),
                              ],
                            ),
                          ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // BOTTOM PANEL: Data Logging
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFF2C2C3E), borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.folder),
                        label: const Text('Pilih Folder'),
                        onPressed: _isLogging ? null : _pickDirectory,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _selectedDirectory == null ? 'Folder belum dipilih' : _selectedDirectory!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: const Icon(Icons.play_circle_fill),
                          label: const Text('Mulai Log Data', style: TextStyle(fontSize: 16)),
                          onPressed: (!_isConnected || _isLogging) ? null : _startLogging,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: const Icon(Icons.stop_circle),
                          label: const Text('Hentikan Log', style: TextStyle(fontSize: 16)),
                          onPressed: _isLogging ? _stopLogging : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isLogging)
                    Text('Merekam... ($_logCount baris data)', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}