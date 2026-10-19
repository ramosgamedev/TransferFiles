import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:transfer_files/core/network_utils.dart';
import 'package:transfer_files/ui/shared/app_theme.dart';

/// Overlay semi-transparente que muestra el progreso de una transferencia.
/// Aparece con animación de fade y muestra porcentaje, velocidad y
/// un botón para cancelar la operación.
class ProgressOverlay extends StatefulWidget {
  /// Nombre del archivo en transferencia
  final String fileName;

  /// Progreso actual (0.0 - 1.0)
  final double progress;

  /// Velocidad de transferencia en texto formateado
  final String speed;

  /// Bytes transferidos hasta el momento
  final int transferredBytes;

  /// Tamaño total del archivo en bytes
  final int totalBytes;

  /// Indica si la transferencia es una subida (true) o bajada (false)
  final bool isUpload;

  /// Callback para cancelar la transferencia
  final VoidCallback onCancel;

  /// Controla la visibilidad del overlay
  final bool isVisible;

  const ProgressOverlay({
    super.key,
    required this.fileName,
    required this.progress,
    required this.speed,
    required this.transferredBytes,
    required this.totalBytes,
    required this.isUpload,
    required this.onCancel,
    this.isVisible = true,
  });

  @override
  State<ProgressOverlay> createState() => _ProgressOverlayState();
}

class _ProgressOverlayState extends State<ProgressOverlay>
    with SingleTickerProviderStateMixin {
  /// Controlador para la animación de fade del overlay
  late AnimationController _fadeController;

  /// Animación de opacidad
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Iniciar animación si es visible al crear
    if (widget.isVisible) {
      _fadeController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant ProgressOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Animar entrada/salida según visibilidad
    if (widget.isVisible && !oldWidget.isVisible) {
      _fadeController.forward();
    } else if (!widget.isVisible && oldWidget.isVisible) {
      _fadeController.reverse();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.transparent,
        child: Container(
          // Fondo oscuro semi-transparente
          color: AppColors.background.withValues(alpha: 0.88),
          width: double.infinity,
          height: double.infinity,
          child: Center(
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  /// Contenido principal del overlay
  Widget _buildContent() {
    final percent = (widget.progress * 100).clamp(0.0, 100.0);
    final accentColor = widget.isUpload ? AppColors.primary : AppColors.secondary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.15),
            blurRadius: 40,
            spreadRadius: -8,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Indicador circular de progreso ────────────────
          _buildCircularProgress(percent, accentColor),

          const SizedBox(height: 28),

          // ─── Icono de dirección ────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isUpload
                      ? Icons.cloud_upload_rounded
                      : Icons.cloud_download_rounded,
                  color: accentColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.isUpload ? 'Enviando' : 'Recibiendo',
                  style: GoogleFonts.inter(
                    color: accentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Nombre del archivo ────────────────────────────
          Text(
            widget.fileName,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 8),

          // ─── Bytes transferidos / total ─────────────────────
          Text(
            '${formatFileSize(widget.transferredBytes)} / ${formatFileSize(widget.totalBytes)}',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),

          const SizedBox(height: 6),

          // ─── Velocidad de transferencia ─────────────────────
          if (widget.speed.isNotEmpty)
            Text(
              widget.speed,
              style: GoogleFonts.inter(
                color: accentColor.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),

          const SizedBox(height: 28),

          // ─── Barra de progreso lineal ───────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: widget.progress.clamp(0.0, 1.0),
                backgroundColor: AppColors.surfaceLight,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ─── Botón de cancelar ──────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(
                'Cancelar',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(
                  color: AppColors.error,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Construye el indicador circular con porcentaje centrado
  Widget _buildCircularProgress(double percent, Color accentColor) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anillo de progreso
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: widget.progress.clamp(0.0, 1.0),
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              backgroundColor: AppColors.surfaceLight,
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          // Brillo exterior sutil
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          // Texto del porcentaje
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${percent.toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              Text(
                '%',
                style: GoogleFonts.inter(
                  color: accentColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
