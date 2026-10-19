import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';

import '../../core/file_utils.dart';
import '../../core/network_utils.dart';
import '../../core/transfer_client.dart';
import '../../core/transfer_model.dart';
import '../../core/transfer_server.dart';
import '../shared/app_theme.dart';
import '../shared/connection_panel.dart';
import '../shared/progress_overlay.dart';
import '../shared/transfer_card.dart';

class QuestHome extends StatefulWidget {
  const QuestHome({super.key});

  @override
  State<QuestHome> createState() => _QuestHomeState();
}

class _QuestHomeState extends State<QuestHome>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TransferServer _server = TransferServer(
    deviceName:
        'Meta Quest', // Podríamos usar device_info_plus para el nombre real
    devicePlatform: 'android',
  );
  final TransferClient _client = TransferClient();
  List<String> _localIps = ['0.0.0.0'];
  int _currentIpIndex = 0;
  String get _localIp => _localIps[_currentIpIndex];
  final int _localPort = defaultPort;

  bool _isConnected = false;
  DeviceInfo? _remoteDevice;

  final List<PlatformFile> _selectedFiles = [];
  final List<TransferItem> _transferHistory = [];

  bool _isTransferring = false;
  bool _isReceiving = false;
  String _currentTransferFile = '';
  double _currentTransferProgress = 0.0;
  String _currentTransferSpeed = '';
  int _currentTransferredBytes = 0;
  int _currentTotalBytes = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requestPermissionsAndInit();
  }

  @override
  void dispose() {
    _server.stop();
    _client.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissionsAndInit() async {
    // Solicitar permisos de almacenamiento para Android/Quest usando MethodChannel nativo
    if (Platform.isAndroid) {
      const platform = MethodChannel('com.transferfiles/permissions');
      try {
        final bool isGranted = await platform.invokeMethod(
          'requestStoragePermission',
        );
        if (!isGranted) {
          _showSnackBar(
            'Por favor, concede acceso a todos los archivos y reinicia la app.',
            AppColors.error,
          );
        }
      } catch (e) {
        print("Error requesting permissions: $e");
      }
    }

    await _initNetwork();
    await _initServer();
  }

  Future<void> _initNetwork() async {
    final ips = await getAllLocalIpAddresses();
    if (mounted) {
      setState(() {
        _localIps = ips;
      });
    }
  }

  Future<void> _initServer() async {
    _server.onFileReceived = (item) {
      setState(() {
        _transferHistory.insert(0, item);
      });
      _showSnackBar('Archivo recibido: ${item.fileName}', AppColors.success);
    };

    _server.onPeerConnected = (peer) {
      setState(() {
        _isConnected = true;
        _remoteDevice = peer;
      });
      if (peer.sessionToken != null) {
        _server.setSessionToken(peer.sessionToken);
      }
      _server.authorizeIp(peer.ip);
      _showSnackBar('Conectado por ${peer.name}', AppColors.success);
    };

    _server.onPeerDisconnected = () {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _remoteDevice = null;
        });
        _showSnackBar('El dispositivo remoto se ha desconectado', AppColors.error);
      }
    };

    _server.onProgress = (fileName, received, total) {
      setState(() {
        _isReceiving = true;
        _currentTransferFile = fileName;
        _currentTransferredBytes = received;
        _currentTotalBytes = total;
        _currentTransferProgress = total > 0 ? (received / total) : 0.0;
      });

      if (total > 0 && received >= total) {
        Future.delayed(const Duration(milliseconds: 300), () {
          setState(() {
            _isReceiving = false;
          });
        });
      }
    };

    await _server.start(_localIp, _localPort);
  }

  Future<void> _connectToRemote(String ip, String pin) async {
    if (!isValidIp(ip)) {
      _showSnackBar('Dirección IP inválida', AppColors.error);
      return;
    }

    setState(() {
      _isConnected = false;
      _remoteDevice = null;
    });

    final localDevice = DeviceInfo(
      name: _server.deviceName,
      ip: _localIp,
      port: _localPort,
      platform: _server.devicePlatform,
    );

    final device = await _client.requestConnection(
      ip,
      defaultPort,
      localDevice,
      pin: pin,
    );

    if (device != null) {
      setState(() {
        _isConnected = true;
        _remoteDevice = device;
      });
      // Sincronizar el token de sesión en nuestro servidor local
      _server.setSessionToken(device.sessionToken);
      _server.authorizeIp(device.ip);
      _showSnackBar('Conectado a ${device.name}', AppColors.success);
    } else {
      final errorMsg = _client.lastError ?? 'No se pudo conectar a $ip';
      _showSnackBar(errorMsg, AppColors.error);
    }
  }

  void _disconnect() {
    if (_remoteDevice != null) {
      _client.disconnect(
        _remoteDevice!.ip,
        _remoteDevice!.port,
        sessionToken: _remoteDevice?.sessionToken,
      );
    }
    _server.setSessionToken(null);
    setState(() {
      _isConnected = false;
      _remoteDevice = null;
    });
    _showSnackBar('Desconectado', AppColors.textSecondary);
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);

      if (result != null) {
        setState(() {
          for (var file in result.files) {
            if (!_selectedFiles.any((f) => f.path == file.path)) {
              _selectedFiles.add(file);
            }
          }
        });
      }
    } catch (e) {
      _showSnackBar('Error al seleccionar archivos: $e', AppColors.error);
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  Future<void> _sendFiles() async {
    if (!_isConnected || _remoteDevice == null) return;
    if (_selectedFiles.isEmpty) return;

    setState(() {
      _isTransferring = true;
    });

    int successCount = 0;

    for (int i = 0; i < _selectedFiles.length; i++) {
      final file = _selectedFiles[i];
      if (file.path == null) continue;

      setState(() {
        _currentTransferFile = file.name;
        _currentTransferProgress = 0.0;
        _currentTransferSpeed = 'Calculando...';
      });

      int lastTime = DateTime.now().millisecondsSinceEpoch;
      int lastBytes = 0;

      final success = await _client.sendFile(
        _remoteDevice!.ip,
        _remoteDevice!.port,
        file.path!,
        sessionToken: _remoteDevice?.sessionToken,
        onProgress: (sent, total) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final timeDiff = now - lastTime;

          if (timeDiff >= 500) {
            final bytesDiff = sent - lastBytes;
            final speed = (bytesDiff / (timeDiff / 1000)).round();

            setState(() {
              _currentTransferProgress = sent / total;
              _currentTransferSpeed = '${formatTransferSpeed(speed)}';
              _currentTransferredBytes = sent;
              _currentTotalBytes = total;
            });

            lastTime = now;
            lastBytes = sent;
          } else {
            setState(() {
              _currentTransferProgress = sent / total;
              _currentTransferredBytes = sent;
              _currentTotalBytes = total;
            });
          }
        },
      );

      final item = TransferItem(
        id: 'send_${DateTime.now().millisecondsSinceEpoch}',
        fileName: file.name,
        filePath: file.path!,
        fileSize: file.size,
        transferredBytes: success ? file.size : 0,
        status: success ? TransferStatus.completed : TransferStatus.failed,
        isIncoming: false,
      );

      setState(() {
        _transferHistory.insert(0, item);
      });

      if (success) {
        successCount++;
      } else {
        final err =
            _client.lastError ?? 'Error desconocido al enviar ${file.name}';
        _showSnackBar('Fallo al enviar ${file.name}: $err', AppColors.error);
      }
    }

    setState(() {
      _isTransferring = false;
      _selectedFiles.clear();
    });

    _showSnackBar(
      'Transferencia completada ($successCount/${_selectedFiles.length})',
      successCount == _selectedFiles.length
          ? AppColors.success
          : AppColors.error,
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Para Quest, usamos acentos en púrpura para diferenciar
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: AppColors
              .secondary, // Usar secondary (púrpura) como primario aquí
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 20,
            ), // Botones más grandes
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  // Header Quest
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 16.0,
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.secondary.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: const Icon(
                                Icons.headset_mic,
                                color: AppColors.secondary,
                                size: 36,
                              ),
                            ),
                            if (_isConnected)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TransferFiles',
                              style: GoogleFonts.inter(
                                fontSize: 32, // Más grande para Quest
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: AppColors.secondary.withValues(
                                      alpha: 0.6,
                                    ),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Módulo Quest',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Connection Panel (adaptado)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: ConnectionPanel(
                      localIp: _localIp,
                      localPort: _localPort,
                      localPin: _server.pin,
                      onPinChanged: (newPin) {
                        setState(() {
                          _server.setPin(newPin);
                        });
                        _showSnackBar('PIN local actualizado a $newPin', AppColors.success);
                      },
                      hasMultipleIps: _localIps.length > 1,
                      onCycleIp: () {
                        setState(() {
                          _currentIpIndex = (_currentIpIndex + 1) % _localIps.length;
                        });
                      },
                      isConnected: _isConnected,
                      remoteDeviceInfo: _remoteDevice,
                      onConnect: _connectToRemote,
                      onDisconnect: _disconnect,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Tabs grandes
                  TabBar(
                    controller: _tabController,
                    indicatorColor: AppColors.secondary,
                    labelColor: AppColors.secondary,
                    unselectedLabelColor: AppColors.textSecondary,
                    labelStyle: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    tabs: const [
                      Tab(
                        text: 'ENVIAR',
                        icon: Icon(Icons.upload_file, size: 28),
                      ),
                      Tab(
                        text: 'RECIBIDOS',
                        icon: Icon(Icons.download, size: 28),
                      ),
                    ],
                  ),

                  // Tab Views
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [_buildSendTab(), _buildReceiveTab()],
                    ),
                  ),
                ],
              ),
            ),

            if (_isTransferring)
              ProgressOverlay(
                fileName: _currentTransferFile,
                progress: _currentTransferProgress,
                speed: _currentTransferSpeed,
                transferredBytes: _currentTransferredBytes,
                totalBytes: _currentTotalBytes,
                isUpload: true,
                onCancel: () {},
              ),
            if (_isReceiving)
              ProgressOverlay(
                fileName: _currentTransferFile,
                progress: _currentTransferProgress,
                speed: _currentTransferSpeed,
                transferredBytes: _currentTransferredBytes,
                totalBytes: _currentTotalBytes,
                isUpload: false,
                onCancel: () {},
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendTab() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _pickFiles,
              icon: const Icon(Icons.add_photo_alternate, size: 32),
              label: const Text(
                'SELECCIONAR ARCHIVOS',
                style: TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceLight,
                foregroundColor: AppColors.secondary,
                side: BorderSide(
                  color: AppColors.secondary.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
            ),

            const SizedBox(height: 24),

            if (_selectedFiles.isNotEmpty) ...[
              Text(
                'Archivos seleccionados (${_selectedFiles.length})',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
            ],

            Expanded(
              child: _selectedFiles.isEmpty
                  ? Center(
                      child: Text(
                        'Toca el botón arriba para seleccionar archivos',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _selectedFiles.length,
                      itemBuilder: (context, index) {
                        final file = _selectedFiles[index];
                        return Card(
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: AppColors.border),
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Icon(
                              getFileIcon(file.extension ?? ''),
                              color: AppColors.secondary,
                              size: 36,
                            ),
                            title: Text(
                              file.name,
                              style: const TextStyle(fontSize: 18),
                            ),
                            subtitle: Text(
                              formatFileSize(file.size),
                              style: const TextStyle(fontSize: 14),
                            ),
                            trailing: IconButton(
                              iconSize: 32,
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: AppColors.error,
                              ),
                              onPressed: () => _removeFile(index),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: _isConnected && _selectedFiles.isNotEmpty
                  ? _sendFiles
                  : null,
              icon: const Icon(Icons.send, size: 28),
              label: const Text(
                'ENVIAR A PC',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildReceiveTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: _transferHistory.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox,
                    size: 80,
                    color: AppColors.textSecondary.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No has recibido archivos',
                    style: TextStyle(
                      fontSize: 20,
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _transferHistory.length,
              itemBuilder: (context, index) {
                final item = _transferHistory[index];
                return GestureDetector(
                  onTap: () async {
                    if (item.status == TransferStatus.completed) {
                      try {
                        await OpenFile.open(item.filePath);
                      } catch (e) {
                        _showSnackBar(
                          'No se pudo abrir el archivo',
                          AppColors.error,
                        );
                      }
                    }
                  },
                  child: TransferCard(item: item),
                );
              },
            ),
    );
  }
}
