import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const ModbusApp());
}

class ModbusApp extends StatelessWidget {
  const ModbusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Modbus Positional Deviation',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Serial Port variables
  List<String> availablePorts = [];
  String? selectedPort;
  SerialPort? serialPort;
  SerialPortReader? reader;
  bool isConnected = false;

  // Modbus Configuration
  final int baudRate = 115200;
  final int slaveId = 1; 
  final int startAddress = 0x01BE; 
  final int numRegisters = 2; 

  // Data & Chart variables
  Timer? pollingTimer;
  Timer? uiUpdateTimer; // Timer terpisah untuk update UI agar tidak hang
  
  List<FlSpot> chartData = [];
  double currentTime = 0; 
  int currentDeviation = 0; 
  final int maxDataPoints = 100; 

  // Logging variables
  String? logDirectory;
  File? logFile;
  IOSink? logSink;
  bool isLogging = false;

  // Modbus Buffer
  List<int> rxBuffer = [];

  @override
  void initState() {
    super.initState();
    _refreshPorts();
  }

  @override
  void dispose() {
    pollingTimer?.cancel();
    uiUpdateTimer?.cancel();
    _disconnect();
    super.dispose();
  }

  void _refreshPorts() {
    setState(() {
      availablePorts = SerialPort.availablePorts;
      if (availablePorts.isNotEmpty) {
        selectedPort = availablePorts.first;
      }
    });
  }

  Future<void> _connect() async {
    if (selectedPort == null) return;

    serialPort = SerialPort(selectedPort!);

    try {
      if (serialPort!.openReadWrite()) {
        SerialPortConfig config = serialPort!.config;
        config.baudRate = baudRate;
        config.bits = 8;
        config.parity = 2; 
        config.stopBits = 1;
        serialPort!.config = config;

        reader = SerialPortReader(serialPort!);
        reader!.stream.listen(_handleIncomingData);

        setState(() {
          isConnected = true;
          chartData.clear();
          currentTime = 0;
          rxBuffer.clear(); // Bersihkan buffer saat mulai
        });

        // 1. Timer untuk POLLING DATA ke alat (50ms / 20Hz)
        pollingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
          _sendModbusRequest();
        });

        // 2. Timer untuk UPDATE UI (100ms / 10Hz) -> MENCEGAH HANG
        uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (mounted && isConnected) {
            setState(() {
              // Rebuild UI hanya terjadi disini, terpisah dari penerimaan data
            });
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Terhubung ke $selectedPort')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal terhubung: $e')));
    }
  }

  void _disconnect() {
    pollingTimer?.cancel();
    uiUpdateTimer?.cancel();
    if (isLogging) _stopLogging();

    reader?.close();
    if (serialPort != null && serialPort!.isOpen) {
      serialPort!.close();
    }
    serialPort?.dispose();

    setState(() {
      isConnected = false;
    });
  }

  void _sendModbusRequest() {
    if (serialPort == null || !serialPort!.isOpen) return;

    var frame = ByteData(6);
    frame.setUint8(0, slaveId);
    frame.setUint8(1, 3); 
    frame.setUint16(2, startAddress, Endian.big);
    frame.setUint16(4, numRegisters, Endian.big);

    int crc = _calculateCRC(frame.buffer.asUint8List());
    var fullFrame = BytesBuilder();
    fullFrame.add(frame.buffer.asUint8List());
    fullFrame.addByte(crc & 0xFF); 
    fullFrame.addByte((crc >> 8) & 0xFF); 

    try {
      serialPort!.write(fullFrame.toBytes());
    } catch (e) {
      if (kDebugMode) print("Write error: $e");
    }
  }

  void _handleIncomingData(Uint8List data) {
    rxBuffer.addAll(data);

    // Gunakan WHILE loop untuk memproses semua frame yang mungkin menumpuk di buffer
    // Jangan gunakan rxBuffer.clear() agar data yang belum lengkap tidak terbuang
    while (rxBuffer.length >= 9) {
      // Cek apakah byte pertama adalah header yang benar (ID dan FC03)
      if (rxBuffer[0] == slaveId && rxBuffer[1] == 3 && rxBuffer[2] == 4) {
        
        // --- VALIDASI CRC UNTUK MENCEGAH DATA SAMPAH MERUSAK PROGRAM ---
        int receivedCrc = rxBuffer[7] | (rxBuffer[8] << 8);
        int calculatedCrc = _calculateCRC(Uint8List.fromList(rxBuffer.sublist(0, 7)));

        if (receivedCrc == calculatedCrc) {
          // Data Valid! Ekstrak nilai
          int lowWord = (rxBuffer[3] << 8) | rxBuffer[4];
          int highWord = (rxBuffer[5] << 8) | rxBuffer[6];

          int combined = (highWord << 16) | lowWord;
          if ((combined & 0x80000000) != 0) {
            combined = combined - 0x100000000;
          }

          // UPDATE DATA SECARA SILENT (TANPA setState)
          currentDeviation = combined;
          currentTime += 0.05; 

          chartData.add(FlSpot(currentTime, currentDeviation.toDouble()));
          if (chartData.length > maxDataPoints) {
            chartData.removeAt(0); 
          }

          if (isLogging && logSink != null) {
            String timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
            logSink!.writeln('$timestamp,$currentDeviation');
          }

          // Buang 1 frame (9 byte) yang sudah berhasil diproses dari buffer
          rxBuffer.removeRange(0, 9);
        } else {
          // Jika CRC salah, buang 1 byte pertama agar loop mencari header berikutnya
          rxBuffer.removeAt(0);
        }
      } else {
        // Jika bukan header yang valid, buang 1 byte pertama dan cari lagi
        rxBuffer.removeAt(0);
      }
    }
  }

  int _calculateCRC(Uint8List data) {
    int crc = 0xFFFF;
    for (int i = 0; i < data.length; i++) {
      crc ^= data[i];
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc = crc >> 1;
        }
      }
    }
    return crc;
  }

  Future<void> _selectFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pilih Folder untuk Menyimpan Log',
    );

    if (selectedDirectory != null) {
      setState(() {
        logDirectory = selectedDirectory;
      });
    }
  }

  void _toggleLogging() {
    if (isLogging) {
      _stopLogging();
    } else {
      _startLogging();
    }
  }

  void _startLogging() {
    if (logDirectory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih folder log terlebih dahulu!')),
      );
      return;
    }

    String fileName = 'Log_Deviation_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    logFile = File('$logDirectory\\$fileName');
    logSink = logFile!.openWrite();

    logSink!.writeln('Timestamp,Positional_Deviation');

    setState(() {
      isLogging = true;
    });
  }

  Future<void> _stopLogging() async {
    setState(() {
      isLogging = false;
    });

    try {
      await logSink?.flush();
      await logSink?.close();
    } catch (e) {
      if (kDebugMode) {
        print('Error saat menutup file log: $e');
      }
    }

    logSink = null;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Log disimpan di: ${logFile?.path}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Modbus Positional Deviation Monitor',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isConnected ? null : _refreshPorts,
            tooltip: 'Refresh COM Ports',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // BARIS ATAS: KONTROL KONEKSI
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.usb, size: 30),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedPort,
                        decoration: const InputDecoration(
                          labelText: 'Pilih COM Port',
                        ),
                        items: availablePorts.map((port) {
                          return DropdownMenuItem(
                            value: port,
                            child: Text(port),
                          );
                        }).toList(),
                        onChanged: isConnected
                            ? null
                            : (val) => setState(() => selectedPort = val),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      '115200 8E1',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 24),
                    ElevatedButton.icon(
                      onPressed: isConnected ? _disconnect : _connect,
                      icon: Icon(isConnected ? Icons.stop : Icons.play_arrow),
                      label: Text(isConnected ? 'Disconnect' : 'Connect'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConnected
                            ? Colors.red.shade100
                            : Colors.green.shade100,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // BARIS TENGAH: DISPLAY NILAI & GRAFIK
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // PANEL KIRI: NILAI AKTUAL & LOGGER
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 4,
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              children: [
                                const Text(
                                  'Current Positional Deviation',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  isConnected
                                      ? currentDeviation.toString()
                                      : '---',
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Data Logging',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Divider(),
                                Text(
                                  logDirectory != null
                                      ? 'Folder: $logDirectory'
                                      : 'Folder belum dipilih',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: isLogging ? null : _selectFolder,
                                  icon: const Icon(Icons.folder),
                                  label: const Text('Pilih Folder'),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        (!isConnected || logDirectory == null)
                                        ? null
                                        : _toggleLogging,
                                    icon: Icon(
                                      isLogging
                                          ? Icons.stop_circle
                                          : Icons.fiber_manual_record,
                                    ),
                                    label: Text(
                                      isLogging
                                          ? 'Berhenti Rekam'
                                          : 'Mulai Rekam',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isLogging
                                          ? Colors.red
                                          : Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // PANEL KANAN: GRAFIK
                  Expanded(
                    flex: 3,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Grafik Real-time',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: chartData.isEmpty
                                  ? const Center(
                                      child: Text('Menunggu data...'),
                                    )
                                  : LineChart(
                                      LineChartData(
                                        gridData: const FlGridData(
                                          show: true,
                                          drawVerticalLine: true,
                                        ),
                                        titlesData: const FlTitlesData(
                                          leftTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              reservedSize: 50,
                                            ),
                                          ),
                                          rightTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                          topTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ), 
                                        ),
                                        borderData: FlBorderData(show: true),
                                        lineBarsData: [
                                          LineChartBarData(
                                            spots: chartData,
                                            isCurved: false, 
                                            color: Colors.blue,
                                            barWidth: 2,
                                            dotData: const FlDotData(
                                              show: false,
                                            ),
                                          ),
                                        ],
                                        minX: chartData.first.x,
                                        maxX: chartData.last.x,
                                        minY: -50,
                                        maxY: 50,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}