import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:transfer_files/core/network_utils.dart';
import 'package:transfer_files/core/transfer_model.dart';
import 'package:transfer_files/ui/shared/app_theme.dart';

/// Panel de conexión que muestra la IP local, permite ingresar la IP remota,
/// y controla el estado de conexión con animaciones suaves.
class ConnectionPanel extends StatefulWidget {
  /// IP local del dispositivo
  final String localIp;

  /// Puerto local del servidor
  final int localPort;

  /// PIN local configurado en este dispositivo
  final String localPin;

  /// Callback al cambiar el PIN local
  final void Function(String newPin)? onPinChanged;

  /// Callback al conectar con una IP remota y su PIN
  final void Function(String ip, String pin) onConnect;

  /// Callback al desconectar
  final VoidCallback onDisconnect;

  /// Callback para alternar IPs locales
  final VoidCallback? onCycleIp;

  /// Indica si hay múltiples IPs locales disponibles
  final bool hasMultipleIps;

  /// Indica si hay una conexión activa
  final bool isConnected;

  /// Información del dispositivo remoto conectado (opcional)
  final DeviceInfo? remoteDeviceInfo;

  const ConnectionPanel({
    super.key,
    required this.localIp,
    required this.localPort,
    this.localPin = '1234',
    this.onPinChanged,
    required this.onConnect,
    required this.onDisconnect,
    required this.isConnected,
    this.onCycleIp,
    this.hasMultipleIps = false,
    this.remoteDeviceInfo,
  });

  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel>
    with TickerProviderStateMixin {
  /// Controlador del campo de texto para la IP remota
  final TextEditingController _ipController = TextEditingController();

  /// Controlador del campo de texto para el PIN remoto
  final TextEditingController _pinController = TextEditingController();

  /// Controlador para la animación del indicador de pulso
  late AnimationController _pulseController;

  /// Animación de escala para el pulso
  late Animation<double> _pulseAnimation;

  /// Controlador para la animación del botón de conexión
  late AnimationController _buttonController;

  /// Mensaje de error de validación
  String? _errorText;

  /// Controla si el panel está colapsado al estar conectado
  bool _isCollapsed = true;

  @override
  void initState() {
    super.initState();

    // Animación de pulso para el indicador de conexión
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Animación para el botón
    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Iniciar pulso si ya está conectado
    if (widget.isConnected) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ConnectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Controlar animación de pulso según el estado de conexión
    if (widget.isConnected && !oldWidget.isConnected) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isConnected && oldWidget.isConnected) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _pinController.dispose();
    _pulseController.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  /// Valida y ejecuta la conexión
  void _handleConnect() {
    final ip = _ipController.text.trim();
    final pin = _pinController.text.trim();
    if (ip.isEmpty) {
      setState(() => _errorText = 'Ingresa una dirección IP');
      return;
    }
    if (!isValidIp(ip)) {
      setState(() => _errorText = 'IP no válida');
      return;
    }
    if (pin.isEmpty) {
      setState(() => _errorText = 'Ingresa el PIN de 4 dígitos');
      return;
    }
    if (pin.length != 4 || int.tryParse(pin) == null) {
      setState(() => _errorText = 'El PIN debe tener 4 dígitos');
      return;
    }
    setState(() => _errorText = null);
    widget.onConnect(ip, pin);
  }

  @override
  Widget build(BuildContext context) {
    final showCollapsed = widget.isConnected && _isCollapsed;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        // Fondo glassmorphism
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        // Borde con gradiente simulado
        border: Border.all(
          color: widget.isConnected
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColors.border,
          width: 1.5,
        ),
        // Sombra sutil
        boxShadow: [
          BoxShadow(
            color: widget.isConnected
                ? AppColors.success.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(showCollapsed ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Encabezado: título y estado ──────────────────
            Row(
              children: [
                // Icono de red
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.wifi_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Título
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conexión de Red',
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isConnected
                            ? 'Conectado a ${widget.remoteDeviceInfo?.name ?? "Dispositivo"}'
                            : 'Sin conexión activa',
                        style: GoogleFonts.inter(
                          color: widget.isConnected
                              ? AppColors.success
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Indicador de conexión con pulso
                _buildConnectionIndicator(),
                if (widget.isConnected) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      _isCollapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () {
                      setState(() {
                        _isCollapsed = !_isCollapsed;
                      });
                    },
                  ),
                ],
              ],
            ),

            if (!showCollapsed) ...[
              const SizedBox(height: 20),

              // ─── Info del dispositivo local ────────────────────
              _buildLocalInfo(),

              const SizedBox(height: 16),

              // ─── Dispositivo remoto (si conectado) ─────────────
              if (widget.isConnected && widget.remoteDeviceInfo != null)
                _buildRemoteDeviceInfo()
              else ...[
                // ─── Campo de IP remota ──────────────────────────
                _buildIpInput(),
              ],

              const SizedBox(height: 18),

              // ─── Botón de conectar/desconectar ─────────────────
              _buildActionButton(),
            ],
          ],
        ),
      ),
    );
  }

  /// Indicador visual de conexión con animación de pulso
  Widget _buildConnectionIndicator() {
    final color = widget.isConnected ? AppColors.success : AppColors.error;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Anillo exterior pulsante (solo cuando conectado)
            if (widget.isConnected)
              Container(
                width: 28 * _pulseAnimation.value,
                height: 28 * _pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(
                    alpha: 0.15 * (1.4 - _pulseAnimation.value),
                  ),
                ),
              ),
            // Punto central
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Diálogo para configurar el PIN local de 4 dígitos
  void _showChangePinDialog() {
    final controller = TextEditingController(text: widget.localPin);
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Configurar PIN Local',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Otros dispositivos deberán ingresar este PIN de 4 dígitos para conectarse a tu dispositivo:',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 4,
                autofocus: true,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppColors.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  errorText: dialogError,
                  hintText: '1234',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final newPin = controller.text.trim();
                if (newPin.length != 4 || int.tryParse(newPin) == null) {
                  setDialogState(() {
                    dialogError = 'Debe ser de 4 números';
                  });
                  return;
                }
                widget.onPinChanged?.call(newPin);
                Navigator.of(ctx).pop();
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Muestra la información de red local
  Widget _buildLocalInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.computer_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Este dispositivo',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: widget.hasMultipleIps ? widget.onCycleIp : null,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.localIp,
                            style: GoogleFonts.inter(
                              color: AppColors.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          ':${widget.localPort}',
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (widget.hasMultipleIps) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.swap_horiz_rounded,
                            color: AppColors.primary,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Badge interactivo para ver y cambiar el PIN
          InkWell(
            onTap: _showChangePinDialog,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.primary,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PIN: ${widget.localPin}',
                    style: GoogleFonts.inter(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.edit_rounded,
                    color: AppColors.textSecondary,
                    size: 12,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Muestra la información del dispositivo remoto conectado
  Widget _buildRemoteDeviceInfo() {
    final remote = widget.remoteDeviceInfo!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              remote.platform == 'android'
                  ? Icons.headset_rounded
                  : Icons.desktop_windows_rounded,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dispositivo remoto',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  remote.name,
                  style: GoogleFonts.inter(
                    color: AppColors.success,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${remote.ip}:${remote.port}',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Icono de enlace
          const Icon(
            Icons.link_rounded,
            color: AppColors.success,
            size: 20,
          ),
        ],
      ),
    );
  }

  /// Campo de texto para ingresar la IP remota y el PIN remoto
  Widget _buildIpInput() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Campo de IP
        Expanded(
          flex: 3,
          child: TextField(
            controller: _ipController,
            keyboardType: TextInputType.number,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              labelText: 'IP remota',
              hintText: '192.168.1.100',
              errorText: _errorText,
              prefixIcon: const Icon(Icons.lan_rounded, size: 20),
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            onSubmitted: (_) => _handleConnect(),
          ),
        ),
        const SizedBox(width: 10),
        // Campo de PIN
        Expanded(
          flex: 2,
          child: TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
            decoration: const InputDecoration(
              counterText: '',
              labelText: 'PIN Remoto',
              hintText: '1234',
              prefixIcon: Icon(Icons.lock_rounded, size: 20),
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            onSubmitted: (_) => _handleConnect(),
          ),
        ),
      ],
    );
  }

  /// Botón principal de conectar/desconectar con animación
  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          );
        },
        child: widget.isConnected
            ? // Botón de desconectar
              SizedBox(
                key: const ValueKey('disconnect'),
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: widget.onDisconnect,
                  icon: const Icon(Icons.link_off_rounded, size: 20),
                  label: Text(
                    'Desconectar',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              )
            : // Botón de conectar con gradiente
              Container(
                key: const ValueKey('connect'),
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: -4,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _handleConnect,
                  icon: const Icon(Icons.link_rounded, size: 20),
                  label: Text(
                    'Conectar',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
