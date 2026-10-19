import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:transfer_files/core/transfer_model.dart';
import 'package:transfer_files/core/file_utils.dart';
import 'package:transfer_files/core/network_utils.dart';
import 'package:transfer_files/ui/shared/app_theme.dart';

/// Widget de tarjeta para mostrar un ítem de transferencia de archivo.
/// Incluye efecto glassmorphism, barra de progreso animada,
/// indicador de estado y dirección de transferencia.
class TransferCard extends StatefulWidget {
  /// El ítem de transferencia a mostrar
  final TransferItem item;

  /// Callback opcional al presionar la tarjeta
  final VoidCallback? onTap;

  /// Callback opcional para cancelar la transferencia
  final VoidCallback? onCancel;

  const TransferCard({
    super.key,
    required this.item,
    this.onTap,
    this.onCancel,
  });

  @override
  State<TransferCard> createState() => _TransferCardState();
}

class _TransferCardState extends State<TransferCard>
    with SingleTickerProviderStateMixin {
  /// Controlador para la animación de progreso suave
  late AnimationController _animController;

  /// Animación del valor de progreso con interpolación suave
  late Animation<double> _progressAnimation;

  /// Último valor de progreso registrado para animar transiciones
  double _lastProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _lastProgress = _currentProgress;
    _progressAnimation = Tween<double>(
      begin: _lastProgress,
      end: _lastProgress,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void didUpdateWidget(covariant TransferCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Animar el cambio de progreso suavemente
    final newProgress = _currentProgress;
    if (newProgress != _lastProgress) {
      _progressAnimation = Tween<double>(
        begin: _lastProgress,
        end: newProgress,
      ).animate(CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ));
      _animController.forward(from: 0);
      _lastProgress = newProgress;
    }
  }

  /// Calcula el progreso actual (0.0 - 1.0)
  double get _currentProgress {
    if (widget.item.fileSize <= 0) return 0.0;
    return (widget.item.transferredBytes / widget.item.fileSize).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Obtiene el color correspondiente al estado de la transferencia
  Color _statusColor(TransferStatus status) {
    switch (status) {
      case TransferStatus.transferring:
        return widget.item.isIncoming
            ? AppColors.secondary
            : AppColors.primary;
      case TransferStatus.completed:
        return AppColors.success;
      case TransferStatus.failed:
        return AppColors.error;
      case TransferStatus.connecting:
        return AppColors.primary.withValues(alpha: 0.7);
      case TransferStatus.idle:
        return AppColors.textSecondary;
    }
  }

  /// Obtiene el icono correspondiente al estado
  IconData _statusIcon(TransferStatus status) {
    switch (status) {
      case TransferStatus.transferring:
        return Icons.sync_rounded;
      case TransferStatus.completed:
        return Icons.check_circle_rounded;
      case TransferStatus.failed:
        return Icons.error_rounded;
      case TransferStatus.connecting:
        return Icons.hourglass_top_rounded;
      case TransferStatus.idle:
        return Icons.schedule_rounded;
    }
  }

  /// Texto descriptivo del estado actual
  String _statusText(TransferStatus status) {
    switch (status) {
      case TransferStatus.transferring:
        return widget.item.isIncoming ? 'Descargando...' : 'Enviando...';
      case TransferStatus.completed:
        return 'Completado';
      case TransferStatus.failed:
        return 'Error';
      case TransferStatus.connecting:
        return 'Conectando...';
      case TransferStatus.idle:
        return 'En espera';
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final statusColor = _statusColor(item.status);
    final extension = item.fileName.split('.').last.toLowerCase();
    final fileIcon = getFileIcon(extension);
    final isActive = item.status == TransferStatus.transferring ||
        item.status == TransferStatus.connecting;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          // Efecto glassmorphism: fondo semi-transparente
          color: AppColors.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? statusColor.withValues(alpha: 0.4)
                : AppColors.border.withValues(alpha: 0.6),
            width: isActive ? 1.5 : 1,
          ),
          // Sombra sutil con el color del estado cuando está activo
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Fila principal: icono, info y estado ─────────
              Row(
                children: [
                  // Icono del archivo con fondo redondeado
                  _buildFileIcon(fileIcon, statusColor),
                  const SizedBox(width: 14),

                  // Nombre y tamaño del archivo
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Tamaño formateado
                            Text(
                              formatFileSize(item.fileSize),
                              style: GoogleFonts.inter(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Punto separador
                            Container(
                              width: 3,
                              height: 3,
                              decoration: const BoxDecoration(
                                color: AppColors.textSecondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Timestamp
                            Text(
                              _formatTimestamp(item.timestamp),
                              style: GoogleFonts.inter(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Flecha de dirección y estado
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Flecha de dirección (↑ enviar, ↓ recibir)
                      _buildDirectionBadge(item.isIncoming),
                      const SizedBox(height: 6),
                      // Indicador de estado
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _statusIcon(item.status),
                            color: statusColor,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _statusText(item.status),
                            style: GoogleFonts.inter(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),

              // ─── Barra de progreso animada ────────────────────
              if (isActive || item.status == TransferStatus.completed) ...[
                const SizedBox(height: 14),
                _buildProgressBar(statusColor, item),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Construye el icono del archivo con fondo decorado
  Widget _buildFileIcon(IconData icon, Color accentColor) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Icon(
        icon,
        color: accentColor,
        size: 24,
      ),
    );
  }

  /// Construye la insignia de dirección (subir/bajar)
  Widget _buildDirectionBadge(bool isIncoming) {
    final color = isIncoming ? AppColors.secondary : AppColors.primary;
    final icon = isIncoming
        ? Icons.arrow_downward_rounded
        : Icons.arrow_upward_rounded;
    final label = isIncoming ? 'IN' : 'OUT';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// Construye la barra de progreso animada con porcentaje
  Widget _buildProgressBar(Color color, TransferItem item) {
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, _) {
        final progress = _progressAnimation.value;
        final percent = (progress * 100).toStringAsFixed(0);
        final transferred = formatFileSize(item.transferredBytes);
        final total = formatFileSize(item.fileSize);

        return Column(
          children: [
            // Texto de progreso
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$transferred / $total',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$percent%',
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Barra de progreso personalizada
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.surfaceLight,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Formatea la marca de tiempo a formato legible
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 60) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    // Formato de fecha corto
    return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
