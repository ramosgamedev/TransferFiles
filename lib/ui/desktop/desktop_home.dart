import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/file_utils.dart';
import '../../core/network_utils.dart';
import '../../core/transfer_client.dart';
import '../../core/transfer_model.dart';
import '../../core/transfer_server.dart';
import '../shared/app_theme.dart';
import '../shared/connection_panel.dart';
import '../shared/progress_overlay.dart';
import '../shared/transfer_card.dart';

class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key});

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome>
    with SingleTickerProviderStateMixin, TrayListener, WindowListener {
  late TabController _tabController;
  final TransferServer _server = TransferServer(
    deviceName: Platform.localHostname,
    devicePlatform: 'windows',
  );
  final TransferClient _client = TransferClient();

  // Estado de red
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
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      trayManager.addListener(this);
      windowManager.addListener(this);
      _initSystemTray();
    }
    _initNetworkAndServer();
  }

  Future<void> _initSystemTray() async {
    try {
      await windowManager.setPreventClose(true);

      if (Platform.isWindows) {
        await trayManager.setIcon('windows/runner/resources/app_icon.ico');
      }
      await trayManager.setToolTip('TransferFiles (En segundo plano)');

      final menu = Menu(
        items: [
          MenuItem(
            key: 'show_window',
            label: 'Abrir TransferFiles',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit_app',
            label: 'Salir completamente',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('Error inicializando System Tray: $e');
    }
  }

  // --- Callbacks de WindowListener y TrayListener ---
  @override
  void onWindowClose() async {
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      await windowManager.show();
      await windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      await windowManager.destroy();
    }
  }

  Future<void> _initNetworkAndServer() async {
    await _initNetwork();
    await _initServer();
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      trayManager.destroy();
    }
    _server.stop();
    _client.dispose();
    _tabController.dispose();
    super.dispose();
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
      // Autorizar explícitamente la IP del remoto para permitir envío bidireccional
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
          // Agregar archivos que no estén ya en la lista
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
    int failCount = 0;

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
            // Actualizar velocidad cada 500ms
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

      // Registrar en historial
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
        failCount++;
        final err =
            _client.lastError ?? 'Error desconocido al enviar ${file.name}';
        _showSnackBar('Fallo al enviar ${file.name}: $err', AppColors.error);
      }
    }

    setState(() {
      _isTransferring = false;
      _selectedFiles.clear();
    });

    if (failCount == 0) {
      _showSnackBar('¡$successCount archivos enviados!', AppColors.success);
    } else {
      _showSnackBar(
        'Enviados: $successCount, Fallidos: $failCount',
        AppColors.error,
      );
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.computer,
                              color: AppColors.primary,
                              size: 32,
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
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              shadows: [
                                Shadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.5,
                                  ),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Módulo PC',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Status Bar moved here
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _server.isRunning
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _server.isRunning
                                    ? 'Servidor Activo (Puerto $_localPort)'
                                    : 'Servidor Detenido',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Connection Panel
                ConnectionPanel(
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

                const SizedBox(height: 16),

                // Tabs
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Enviar Archivos', icon: Icon(Icons.upload_file)),
                    Tab(text: 'Archivos Recibidos', icon: Icon(Icons.download)),
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

          // Progress Overlay
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
    );
  }

  Widget _buildSendTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Add Files Button / Drop Zone
          InkWell(
            onTap: _pickFiles,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add_circle_outline,
                    size: 40,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Seleccionar archivos',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Selected Files List
          Text(
            'Archivos seleccionados (${_selectedFiles.length})',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),

          if (_selectedFiles.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No hay archivos seleccionados',
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _selectedFiles.length,
              itemBuilder: (context, index) {
                final file = _selectedFiles[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: AppColors.surfaceLight,
                  child: ListTile(
                    leading: Icon(
                      getFileIcon(file.extension ?? ''),
                      color: AppColors.primary,
                    ),
                    title: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                    subtitle: Text(
                      formatFileSize(file.size),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.error,
                      ),
                      onPressed: () => _removeFile(index),
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 16),

          // Send Button
          ElevatedButton.icon(
            onPressed: _isConnected && _selectedFiles.isNotEmpty
                ? _sendFiles
                : null,
            icon: const Icon(Icons.send),
            label: const Text('Enviar Archivos'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiveTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Historial',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.folder_open),
                label: const Text('Abrir Carpeta'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _transferHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: AppColors.textSecondary.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay transferencias recientes',
                        style: TextStyle(
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
                    return TransferCard(item: _transferHistory[index]);
                  },
                ),
        ],
      ),
    );
  }
}
