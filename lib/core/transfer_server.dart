/// Servidor HTTP local para recibir archivos en TransferFiles.
///
/// Utiliza dart:io HttpServer para crear un servidor HTTP que escucha
/// en la red local y permite recibir archivos desde otros dispositivos.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'file_utils.dart';
import 'network_utils.dart';
import 'transfer_model.dart';

/// Servidor HTTP para recibir archivos y responder a pings.
///
/// Endpoints disponibles:
/// - GET /ping → Verificar que el servidor está activo
/// - POST /upload → Recibir un archivo
/// - GET /files → Listar archivos disponibles para descarga
/// - GET /download?file=nombre → Descargar un archivo
class TransferServer {
  HttpServer? _server;
  String _downloadDir = '';
  bool _isRunning = false;

  /// Nombre del dispositivo para identificación.
  String deviceName;

  /// Plataforma del dispositivo.
  String devicePlatform;

  /// Lista de archivos recibidos.
  final List<TransferItem> receivedFiles = [];

  /// IPs autorizadas para subir archivos (autorización por IP simplificada).
  final Set<String> _authorizedIps = <String>{};

  /// Token de sesión activo para validar conexiones y transferencias de forma segura.
  String? _sessionToken;

  /// Establece o actualiza el token de sesión.
  void setSessionToken(String? token) {
    _sessionToken = token;
    debugPrint('[Server] Token de sesión actualizado: $token');
  }

  /// Retorna el token de sesión activo.
  String? get sessionToken => _sessionToken;

  /// PIN de 4 dígitos configurado para autorizar conexiones automáticamente.
  String pin = '1234';

  /// Establece un nuevo PIN.
  void setPin(String newPin) {
    pin = newPin;
    debugPrint('[Server] PIN actualizado: $pin');
  }

  /// Callback cuando se recibe un archivo completo.
  void Function(TransferItem item)? onFileReceived;

  /// Callback para progreso de recepción.
  void Function(String fileName, int received, int total)? onProgress;

  /// Callback cuando ocurre un error.
  void Function(String error)? onError;

  /// Callback cuando cambia el estado del servidor.
  void Function(bool isRunning)? onStatusChanged;

  /// Callback cuando un dispositivo solicita conexión. Debe retornar true si se aprueba.
  /// La UI debe mostrar un modal y devolver la decisión.
  Future<bool> Function(DeviceInfo requester)? onConnectionRequest;

  /// Callback cuando un peer queda autorizado/conectado.
  void Function(DeviceInfo peer)? onPeerConnected;

  /// Callback cuando el peer remoto notifica que se ha desconectado.
  void Function()? onPeerDisconnected;

  TransferServer({
    this.deviceName = 'Dispositivo',
    this.devicePlatform = 'unknown',
  });

  /// Autoriza manualmente una IP remota (ej. cuando nosotros iniciamos la conexión).
  void authorizeIp(String ip) {
    if (ip.isNotEmpty) {
      _authorizedIps.add(ip);
      debugPrint('[Server] IP autorizada manualmente: $ip');
    }
  }

  /// Indica si el servidor está corriendo.
  bool get isRunning => _isRunning;

  /// Puerto actual del servidor.
  int get port => _server?.port ?? 0;

  String _listenAddress = '';

  /// Inicia el servidor HTTP en la dirección y puerto especificados.
  Future<bool> start(String address, int port) async {
    try {
      // Obtener el directorio de descargas
      _downloadDir = await getDownloadDirectory();
      await ensureDirectoryExists(_downloadDir);

      // Iniciar el servidor
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );

      // Save the listen address provided by the caller so we can report it to clients
      _listenAddress = address;

      _isRunning = true;
      onStatusChanged?.call(true);

      debugPrint('[Server] Servidor iniciado en $address:$port');
      debugPrint('[Server] Directorio de descargas: $_downloadDir');

      // Manejar las solicitudes entrantes
      _server!.listen(
        _handleRequest,
        onError: (error) {
          debugPrint('[Server] Error en conexión: $error');
          onError?.call('Error en conexión: $error');
        },
        onDone: () {
          debugPrint('[Server] Servidor detenido');
          _isRunning = false;
          onStatusChanged?.call(false);
        },
      );

      return true;
    } catch (e) {
      debugPrint('[Server] Error al iniciar servidor: $e');
      onError?.call('Error al iniciar servidor: $e');
      _isRunning = false;
      onStatusChanged?.call(false);
      return false;
    }
  }

  /// Detiene el servidor HTTP.
  Future<void> stop() async {
    try {
      await _server?.close(force: true);
      _server = null;
      _isRunning = false;
      onStatusChanged?.call(false);
      debugPrint('[Server] Servidor detenido correctamente');
    } catch (e) {
      debugPrint('[Server] Error al detener servidor: $e');
    }
  }

  /// Maneja cada solicitud HTTP entrante.
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    debugPrint('[Server] $method $path');

    // Agregar headers CORS para compatibilidad
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    try {
      switch (path) {
        case '/ping':
          await _handlePing(request);
          break;
        case '/connect_request':
          await _handleConnectRequest(request);
          break;
        case '/disconnect':
          await _handleDisconnect(request);
          break;
        case '/upload':
          await _handleUpload(request);
          break;
        case '/files':
          await _handleListFiles(request);
          break;
        case '/download':
          await _handleDownload(request);
          break;
        default:
          request.response.statusCode = 404;
          request.response.write(jsonEncode({'error': 'Ruta no encontrada'}));
          await request.response.close();
      }
    } catch (e) {
      debugPrint('[Server] Error manejando $method $path: $e');
      try {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': 'Error interno: $e'}));
        await request.response.close();
      } catch (_) {
        // La respuesta puede ya estar cerrada
      }
    }
  }

  /// Maneja una solicitud de conexión entrante desde otro dispositivo.
  /// POST /connect_request — Body JSON con {name, platform, port}.
  /// La IP remota se obtiene del socket y la UI puede aprobar/denegar mediante onConnectionRequest.
  Future<void> _handleConnectRequest(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response.statusCode = 405;
      request.response.write(jsonEncode({'error': 'Método no permitido'}));
      await request.response.close();
      return;
    }

    try {
      final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';

      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final requester = DeviceInfo(
        name: data['name'] as String? ?? 'Desconocido',
        ip: remoteIp,
        port: data['port'] as int? ?? defaultPort,
        platform: data['platform'] as String? ?? 'desconocido',
      );

      debugPrint('[Server] Connect request from ${requester.fullAddress} (${requester.name})');

      // Generar o reusar un token de sesión
      final token = _sessionToken ?? '${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecondsSinceEpoch % 9000))}';
      _sessionToken = token;
      final requesterWithToken = requester.copyWith(sessionToken: token);

      // Obtener la IP a la que se conectó el cliente a través de la cabecera Host para evitar devolver 0.0.0.0
      String ipToReturn = '0.0.0.0';
      final hostHeader = request.headers.host; // e.g. "192.168.0.107:8080" o "192.168.0.107"
      if (hostHeader != null && hostHeader.isNotEmpty) {
        final colonIndex = hostHeader.indexOf(':');
        ipToReturn = colonIndex != -1 ? hostHeader.substring(0, colonIndex) : hostHeader;
        if (ipToReturn.startsWith('[') && ipToReturn.endsWith(']')) {
          ipToReturn = ipToReturn.substring(1, ipToReturn.length - 1);
        }
        if (ipToReturn == '0.0.0.0' || ipToReturn == '::' || ipToReturn == 'localhost') {
          ipToReturn = _listenAddress.isNotEmpty ? _listenAddress : '0.0.0.0';
        }
      } else {
        ipToReturn = _listenAddress.isNotEmpty ? _listenAddress : '0.0.0.0';
      }

      final remotePin = (data['pin'] as String?)?.trim() ?? '';

      // Si el PIN coincide, autorizar inmediatamente sin requerir diálogo
      if (remotePin == pin) {
        _authorizedIps.add(remoteIp);
        // Notify UI of connected peer
        try {
          onPeerConnected?.call(requesterWithToken);
        } catch (e) {
          debugPrint('[Server] Error al notificar onPeerConnected: $e');
        }

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        final serverDevice = {
          'name': deviceName,
          'ip': ipToReturn,
          'port': port,
          'platform': devicePlatform,
          'sessionToken': token,
        };
        request.response.write(jsonEncode({
          'status': 'accepted',
          'token': token,
          'device': serverDevice,
        }));
        await request.response.close();
        debugPrint('[Server] Dispositivo autorizado automáticamente con PIN: $remoteIp con token: $token, localIp devuelto: $ipToReturn');
        return;
      } else {
        request.response.statusCode = 403;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'status': 'denied',
          'error': 'PIN incorrecto',
        }));
        await request.response.close();
        debugPrint('[Server] Conexión denegada para $remoteIp: PIN incorrecto (recibido "$remotePin", esperado "$pin")');
        return;
      }
    } catch (e, st) {
      debugPrint('[Server] Error manejando connect_request: $e');
      debugPrint('[Server] Stack: $st');
      try {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': 'Error interno: $e'}));
        await request.response.close();
      } catch (_) {}
    }
  }

  /// POST /disconnect — Notificación de desconexión enviada por el peer remoto.
  Future<void> _handleDisconnect(HttpRequest request) async {
    try {
      _sessionToken = null;
      _authorizedIps.clear();
      onPeerDisconnected?.call();

      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'disconnected'}));
      await request.response.close();
      debugPrint('[Server] Peer remoto notificó desconexión');
    } catch (e) {
      debugPrint('[Server] Error manejando disconnect: $e');
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// GET /ping — Verificar que el servidor está activo.
  Future<void> _handlePing(HttpRequest request) async {
    final response = {
      'status': 'ok',
      'name': deviceName,
      'platform': devicePlatform,
      'port': port,
    };

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  }

  /// POST /upload — Recibir un archivo enviado por multipart/form-data.
  ///
  /// Estrategia: leemos todos los bytes crudos del request, luego
  /// extraemos el contenido del archivo directamente de los bytes
  /// sin convertir a UTF-8 (lo que corrompería datos binarios).
  Future<void> _handleUpload(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response.statusCode = 405;
      request.response.write(jsonEncode({'error': 'Método no permitido'}));
      await request.response.close();
      return;
    }

    // Verificar autorización por Token de Sesión (primario) o IP (secundario/fallback)
    final headerToken = request.headers.value('X-Session-Token');
    final queryToken = request.uri.queryParameters['token'];
    final requestToken = headerToken ?? queryToken;

    bool isTokenValid = _sessionToken != null && requestToken == _sessionToken;
    
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';
    final normalizedIp = remoteIp.startsWith('::ffff:') ? remoteIp.substring(7) : remoteIp;
    
    bool isAuthorized = isTokenValid || _authorizedIps.contains(remoteIp) || _authorizedIps.contains(normalizedIp);
    
    debugPrint('[Server] Upload attempt from $remoteIp (normalized: $normalizedIp) tokenValid: $isTokenValid to ${request.uri.path}');
    
    if (!isAuthorized) {
      if (_sessionToken != null && !isTokenValid) {
        debugPrint('[Server] Rechazando upload: token de sesión inválido o ausente (recibido: $requestToken)');
        request.response.statusCode = 403;
        request.response.write(jsonEncode({'error': 'Remoto no autorizado (Token inválido o ausente)'}));
        await request.response.close();
        return;
      }
      
      if (_authorizedIps.isEmpty) {
        debugPrint('[Server] Rechazando upload desde $remoteIp: no hay dispositivos autorizados');
        request.response.statusCode = 403;
        request.response.write(jsonEncode({'error': 'Remoto no autorizado (Requiere emparejamiento previo)'}));
        await request.response.close();
        return;
      }
    }

    try {
      final contentType = request.headers.contentType;

      debugPrint('[Server] Upload headers from $remoteIp: ${request.headers}');

      // Si no es multipart, intentar como binario directo
      if (contentType == null || contentType.primaryType != 'multipart') {
        await _handleBinaryUpload(request);
        return;
      }

      final boundary = contentType.parameters['boundary'];
      if (boundary == null) {
        request.response.statusCode = 400;
        request.response.write(jsonEncode({'error': 'Boundary no encontrado'}));
        await request.response.close();
        return;
      }

      // Recopilar todos los bytes crudos del body
      final builder = BytesBuilder(copy: false);
      await for (final chunk in request) {
        builder.add(chunk);
      }
      final allBytes = builder.toBytes();

      debugPrint('[Server] Recibidos ${allBytes.length} bytes del upload');

      // Parsear el multipart directamente sobre bytes crudos
      final boundaryBytes = utf8.encode('--$boundary');

      // Encontrar todas las posiciones del boundary
      final boundaryPositions = <int>[];
      for (int i = 0; i <= allBytes.length - boundaryBytes.length; i++) {
        bool match = true;
        for (int j = 0; j < boundaryBytes.length; j++) {
          if (allBytes[i + j] != boundaryBytes[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          boundaryPositions.add(i);
        }
      }

      debugPrint('[Server] Encontrados ${boundaryPositions.length} boundaries');

      if (boundaryPositions.length < 2) {
        // No hay suficientes boundaries para una parte válida
        debugPrint('[Server] No se encontraron partes válidas en el multipart');
        request.response.statusCode = 400;
        request.response.write(jsonEncode({'error': 'Formato multipart inválido'}));
        await request.response.close();
        return;
      }

      // Procesar cada parte (entre boundaries consecutivos)
      for (int i = 0; i < boundaryPositions.length - 1; i++) {
        final partStart = boundaryPositions[i] + boundaryBytes.length;
        final partEnd = boundaryPositions[i + 1];

        // Saltar los \r\n después del boundary
        int dataStart = partStart;
        if (dataStart < allBytes.length && allBytes[dataStart] == 0x0D) dataStart++; // \r
        if (dataStart < allBytes.length && allBytes[dataStart] == 0x0A) dataStart++; // \n

        // Encontrar el fin de los headers (doble \r\n)
        int headerEnd = -1;
        for (int j = dataStart; j < partEnd - 3; j++) {
          if (allBytes[j] == 0x0D && allBytes[j + 1] == 0x0A &&
              allBytes[j + 2] == 0x0D && allBytes[j + 3] == 0x0A) {
            headerEnd = j;
            break;
          }
        }

        if (headerEnd == -1) continue; // No se encontró fin de headers

        // Leer los headers como texto (los headers sí son texto ASCII)
        final headerBytes = allBytes.sublist(dataStart, headerEnd);
        final headerStr = utf8.decode(headerBytes, allowMalformed: true);

        // Extraer el nombre del archivo
        final filenameMatch = RegExp(r'filename="([^"]*)"').firstMatch(headerStr);
        final fileName = filenameMatch?.group(1) ??
            'archivo_${DateTime.now().millisecondsSinceEpoch}';

        // Los datos del archivo comienzan después del doble \r\n
        final bodyStart = headerEnd + 4;

        // El body termina antes del \r\n que precede al siguiente boundary
        int bodyEnd = partEnd;
        if (bodyEnd >= 2 && allBytes[bodyEnd - 1] == 0x0A && allBytes[bodyEnd - 2] == 0x0D) {
          bodyEnd -= 2; // Quitar \r\n antes del boundary
        }

        if (bodyStart >= bodyEnd) {
          debugPrint('[Server] Parte vacía, saltando');
          continue;
        }

        // Extraer los bytes del archivo directamente (SIN conversión UTF-8)
        final fileBytes = allBytes.sublist(bodyStart, bodyEnd);

        // Guardar el archivo
        final filePath = '$_downloadDir${Platform.pathSeparator}$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes, flush: true);

        final totalBytes = fileBytes.length;

        // Registrar el archivo recibido
        final item = TransferItem(
          id: 'recv_${DateTime.now().millisecondsSinceEpoch}',
          fileName: fileName,
          filePath: filePath,
          fileSize: totalBytes,
          transferredBytes: totalBytes,
          status: TransferStatus.completed,
          isIncoming: true,
        );

        receivedFiles.insert(0, item);
        onFileReceived?.call(item);

        debugPrint('[Server] Archivo recibido: $fileName ($totalBytes bytes) → $filePath');
      }

      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'ok', 'message': 'Archivo recibido'}));
      await request.response.close();
    } catch (e, st) {
      debugPrint('[Server] Error al recibir archivo: $e');
      debugPrint('[Server] Stack trace: $st');
      onError?.call('Error al recibir archivo: $e');
      try {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': 'Error al recibir: $e'}));
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Maneja upload binario directo (sin multipart).
  Future<void> _handleBinaryUpload(HttpRequest request) async {
    // Verificar autorización por Token de Sesión (primario) o IP (secundario/fallback)
    final headerToken = request.headers.value('X-Session-Token');
    final queryToken = request.uri.queryParameters['token'];
    final requestToken = headerToken ?? queryToken;

    bool isTokenValid = _sessionToken != null && requestToken == _sessionToken;
    
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';
    final normalizedIp = remoteIp.startsWith('::ffff:') ? remoteIp.substring(7) : remoteIp;
    
    bool isAuthorized = isTokenValid || _authorizedIps.contains(remoteIp) || _authorizedIps.contains(normalizedIp);
    
    debugPrint('[Server] Binary upload headers from $remoteIp tokenValid: $isTokenValid');
    
    if (!isAuthorized) {
      if (_sessionToken != null && !isTokenValid) {
        debugPrint('[Server] Rechazando upload binario: token de sesión inválido o ausente (recibido: $requestToken)');
        request.response.statusCode = 403;
        request.response.write(jsonEncode({'error': 'Remoto no autorizado (Token inválido o ausente)'}));
        await request.response.close();
        return;
      }
      
      if (_authorizedIps.isEmpty) {
        debugPrint('[Server] Rechazando upload binario desde $remoteIp: no hay dispositivos autorizados');
        request.response.statusCode = 403;
        request.response.write(jsonEncode({'error': 'Remoto no autorizado (Requiere emparejamiento)'}));
        await request.response.close();
        return;
      }
    }

    final fileName = request.uri.queryParameters['filename'] ??
        'archivo_${DateTime.now().millisecondsSinceEpoch}';
    final fileSize = request.contentLength;

    final filePath = '$_downloadDir${Platform.pathSeparator}$fileName';
    final file = File(filePath);
    final sink = file.openWrite();

    int totalBytes = 0;

    await for (final chunk in request) {
      sink.add(chunk);
      totalBytes += chunk.length;
      onProgress?.call(fileName, totalBytes, fileSize);
    }

    await sink.flush();
    await sink.close();

    final item = TransferItem(
      id: 'recv_${DateTime.now().millisecondsSinceEpoch}',
      fileName: fileName,
      filePath: filePath,
      fileSize: totalBytes,
      transferredBytes: totalBytes,
      status: TransferStatus.completed,
      isIncoming: true,
    );

    receivedFiles.insert(0, item);
    onFileReceived?.call(item);

    debugPrint('[Server] Archivo recibido (binario): $fileName ($totalBytes bytes)');

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok', 'message': 'Archivo recibido'}));
    await request.response.close();
  }

  /// GET /files — Listar archivos disponibles para descarga.
  Future<void> _handleListFiles(HttpRequest request) async {
    try {
      final files = await getFilesInDirectory(_downloadDir);
      final fileList = <Map<String, dynamic>>[];

      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          fileList.add({
            'name': entity.uri.pathSegments.last,
            'size': stat.size,
            'modified': stat.modified.toIso8601String(),
          });
        }
      }

      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(fileList));
      await request.response.close();
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write(jsonEncode({'error': 'Error listando archivos: $e'}));
      await request.response.close();
    }
  }

  /// GET /download?file=nombre — Descargar un archivo específico.
  Future<void> _handleDownload(HttpRequest request) async {
    final fileName = request.uri.queryParameters['file'];
    if (fileName == null || fileName.isEmpty) {
      request.response.statusCode = 400;
      request.response.write(jsonEncode({'error': 'Parámetro file requerido'}));
      await request.response.close();
      return;
    }

    // Prevenir path traversal
    if (fileName.contains('..') || fileName.contains('/') || fileName.contains('\\')) {
      request.response.statusCode = 403;
      request.response.write(jsonEncode({'error': 'Nombre de archivo inválido'}));
      await request.response.close();
      return;
    }

    final filePath = '$_downloadDir${Platform.pathSeparator}$fileName';
    final file = File(filePath);

    if (!await file.exists()) {
      request.response.statusCode = 404;
      request.response.write(jsonEncode({'error': 'Archivo no encontrado'}));
      await request.response.close();
      return;
    }

    try {
      final stat = await file.stat();
      final mimeType = getMimeType(filePath);

      request.response.statusCode = 200;
      request.response.headers.set('Content-Type', mimeType);
      request.response.headers.set('Content-Length', stat.size.toString());
      request.response.headers.set(
        'Content-Disposition',
        'attachment; filename="$fileName"',
      );

      // Enviar el archivo como stream
      await file.openRead().pipe(request.response);
    } catch (e) {
      debugPrint('[Server] Error al enviar archivo: $e');
      try {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'error': 'Error al enviar: $e'}));
        await request.response.close();
      } catch (_) {}
    }
  }
}
