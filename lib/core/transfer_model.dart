/// Modelos de datos principales para la aplicación TransferFiles.
///
/// Contiene las clases y enumeraciones que representan el estado
/// de las transferencias, la información de los dispositivos y
/// el estado de las conexiones.
library;

/// Estado actual de una transferencia de archivo.
enum TransferStatus {
  /// Sin actividad, esperando acción del usuario.
  idle,

  /// Estableciendo conexión con el dispositivo remoto.
  connecting,

  /// Transferencia de datos en progreso.
  transferring,

  /// Transferencia completada exitosamente.
  completed,

  /// La transferencia falló por algún error.
  failed,
}

/// Representa un archivo en proceso de transferencia o ya transferido.
///
/// Contiene toda la información necesaria para rastrear el progreso
/// y el estado de una transferencia individual.
class TransferItem {
  /// Identificador único de la transferencia.
  final String id;

  /// Nombre del archivo que se está transfiriendo.
  final String fileName;

  /// Ruta completa del archivo en el sistema de archivos local.
  final String filePath;

  /// Tamaño total del archivo en bytes.
  final int fileSize;

  /// Bytes transferidos hasta el momento.
  int transferredBytes;

  /// Estado actual de esta transferencia.
  TransferStatus status;

  /// Marca de tiempo de cuando se inició la transferencia.
  final DateTime timestamp;

  /// Indica si el archivo se está recibiendo (true) o enviando (false).
  final bool isIncoming;

  TransferItem({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    this.transferredBytes = 0,
    this.status = TransferStatus.idle,
    DateTime? timestamp,
    required this.isIncoming,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Calcula el porcentaje de progreso de la transferencia (0.0 a 1.0).
  double get progress {
    if (fileSize <= 0) return 0.0;
    return (transferredBytes / fileSize).clamp(0.0, 1.0);
  }

  /// Porcentaje de progreso formateado como cadena (ej: "75%").
  String get progressPercentage => '${(progress * 100).toStringAsFixed(1)}%';

  /// Indica si la transferencia está activa (conectando o transfiriendo).
  bool get isActive =>
      status == TransferStatus.connecting ||
      status == TransferStatus.transferring;

  /// Crea una copia del item con los campos modificados.
  TransferItem copyWith({
    String? id,
    String? fileName,
    String? filePath,
    int? fileSize,
    int? transferredBytes,
    TransferStatus? status,
    DateTime? timestamp,
    bool? isIncoming,
  }) {
    return TransferItem(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      isIncoming: isIncoming ?? this.isIncoming,
    );
  }

  /// Convierte el item a un mapa JSON serializable.
  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'filePath': filePath,
        'fileSize': fileSize,
        'transferredBytes': transferredBytes,
        'status': status.name,
        'timestamp': timestamp.toIso8601String(),
        'isIncoming': isIncoming,
      };

  /// Crea un TransferItem a partir de un mapa JSON.
  factory TransferItem.fromJson(Map<String, dynamic> json) {
    return TransferItem(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      fileSize: json['fileSize'] as int,
      transferredBytes: (json['transferredBytes'] as int?) ?? 0,
      status: TransferStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TransferStatus.idle,
      ),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      isIncoming: json['isIncoming'] as bool,
    );
  }

  @override
  String toString() =>
      'TransferItem(id: $id, fileName: $fileName, status: ${status.name}, '
      'progress: $progressPercentage)';
}

/// Información sobre un dispositivo en la red.
///
/// Almacena los datos necesarios para identificar y conectarse
/// a otro dispositivo que ejecuta TransferFiles.
class DeviceInfo {
  /// Nombre visible del dispositivo (ej: "Mi PC", "Quest 3").
  final String name;

  /// Dirección IP del dispositivo en la red local.
  final String ip;

  /// Puerto en el que el servidor está escuchando.
  final int port;

  /// Plataforma del dispositivo (ej: "windows", "android", "linux").
  final String platform;

  /// Token de sesión para autorizar transferencias seguras (independiente de IP/NAT).
  final String? sessionToken;

  const DeviceInfo({
    required this.name,
    required this.ip,
    required this.port,
    required this.platform,
    this.sessionToken,
  });

  /// Dirección completa del dispositivo (IP:puerto).
  String get fullAddress => '$ip:$port';

  /// Crea una copia de DeviceInfo con los campos especificados modificados.
  DeviceInfo copyWith({
    String? name,
    String? ip,
    int? port,
    String? platform,
    String? sessionToken,
  }) {
    return DeviceInfo(
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      platform: platform ?? this.platform,
      sessionToken: sessionToken ?? this.sessionToken,
    );
  }

  /// Convierte la información del dispositivo a un mapa JSON.
  Map<String, dynamic> toJson() => {
        'name': name,
        'ip': ip,
        'port': port,
        'platform': platform,
        if (sessionToken != null) 'sessionToken': sessionToken,
      };

  /// Crea un DeviceInfo a partir de un mapa JSON.
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      name: json['name'] as String? ?? 'Desconocido',
      ip: json['ip'] as String? ?? '',
      port: json['port'] as int? ?? 8080,
      platform: json['platform'] as String? ?? 'desconocido',
      sessionToken: json['sessionToken'] as String?,
    );
  }

  @override
  String toString() => 'DeviceInfo(name: $name, ip: $ip:$port, '
      'platform: $platform, hasToken: ${sessionToken != null})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceInfo &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port;

  @override
  int get hashCode => ip.hashCode ^ port.hashCode;
}

/// Estado de la conexión con un dispositivo remoto.
enum ConnectionState {
  /// No hay conexión activa.
  disconnected,

  /// Intentando establecer conexión.
  connecting,

  /// Conexión establecida y activa.
  connected,
}
