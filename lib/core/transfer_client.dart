/// Cliente HTTP para enviar archivos a dispositivos remotos en TransferFiles.
///
/// Utiliza dart:io HttpClient para enviar archivos mediante HTTP POST
/// a otro dispositivo que ejecuta TransferServer en la red local.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'transfer_model.dart';

/// Cliente HTTP para enviar archivos y comunicarse con un TransferServer remoto.
class TransferClient {
  final HttpClient _client = HttpClient();
  String? _lastError;

  /// Último mensaje de error del cliente (útil para mostrar al usuario)
  String? get lastError => _lastError;

  TransferClient() {
    // Timeout de conexión de 5 segundos
    _client.connectionTimeout = const Duration(seconds: 5);
  }

  /// Hace ping al servidor remoto para verificar que está activo.
  ///
  /// Retorna un [DeviceInfo] con la información del servidor si está
  /// disponible, o null si no se puede conectar.
  Future<DeviceInfo?> ping(String host, int port) async {
    try {
      final request = await _client.get(host, port, '/ping');
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        return DeviceInfo(
          name: json['name'] as String? ?? 'Desconocido',
          ip: host,
          port: port,
          platform: json['platform'] as String? ?? 'unknown',
        );
      }
      return null;
    } catch (e) {
      debugPrint('[Client] Error haciendo ping a $host:$port: $e');
      return null;
    }
  }

  /// Solicita autorización al servidor remoto para iniciar transferencias enviando el PIN configurado.
  /// Retorna la DeviceInfo del servidor remoto si fue aceptada, o null si fue denegada.
  Future<DeviceInfo?> requestConnection(
    String host,
    int port,
    DeviceInfo localDevice, {
    String? pin,
  }) async {
    try {
      final request = await _client.post(host, port, '/connect_request');
      request.headers.set('Content-Type', 'application/json');
      final payload = {
        ...localDevice.toJson(),
        if (pin != null && pin.isNotEmpty) 'pin': pin.trim(),
      };
      final body = jsonEncode(payload);
      request.add(utf8.encode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        _lastError = null;
        try {
          final json = jsonDecode(responseBody) as Map<String, dynamic>;
          final token = json['token'] as String?;
          final deviceJson = json['device'] as Map<String, dynamic>?;
          if (deviceJson != null) {
            final dev = DeviceInfo.fromJson(deviceJson);
            if (token != null && dev.sessionToken == null) {
              return dev.copyWith(sessionToken: token);
            }
            return dev;
          }
        } catch (e) {
          debugPrint('[Client] Error parseando response de connect_request: $e');
        }
        // Si no viene device en la respuesta, usar ping fallback
        return await ping(host, port);
      } else {
        try {
          final json = jsonDecode(responseBody) as Map<String, dynamic>;
          _lastError = json['error'] as String? ?? 'Conexión denegada (${response.statusCode})';
        } catch (_) {
          _lastError = 'Conexión denegada (${response.statusCode})';
        }
        debugPrint('[Client] Conexión denegada por $host:$port - ${response.statusCode}: $_lastError');
        return null;
      }
    } catch (e) {
      debugPrint('[Client] Error en requestConnection a $host:$port: $e');
      _lastError = 'No se pudo conectar a $host:$port';
      return null;
    }
  }

  /// Envía una notificación de desconexión al servidor remoto.
  Future<void> disconnect(String host, int port, {String? sessionToken}) async {
    try {
      final tokenQuery = sessionToken != null ? '?token=${Uri.encodeComponent(sessionToken)}' : '';
      final request = await _client.post(host, port, '/disconnect$tokenQuery');
      if (sessionToken != null) {
        request.headers.set('X-Session-Token', sessionToken);
      }
      final response = await request.close();
      await response.drain();
      debugPrint('[Client] Notificación de desconexión enviada a $host:$port (${response.statusCode})');
    } catch (e) {
      debugPrint('[Client] Error enviando desconexión a $host:$port: $e');
    }
  }

  /// Envía un archivo al servidor remoto.
  ///
  /// [host] y [port] identifican al servidor destino.
  /// [filePath] es la ruta completa del archivo a enviar.
  /// [sessionToken] es el token de sesión para autorizar la subida en el servidor remoto.
  /// [onProgress] callback opcional para reportar progreso (bytes enviados, total).
  ///
  /// Retorna true si el envío fue exitoso.
  Future<bool> sendFile(
    String host,
    int port,
    String filePath, {
    String? sessionToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[Client] Archivo no encontrado: $filePath');
        return false;
      }

      final fileSize = await file.length();
      final fileName = file.uri.pathSegments.last;

      final encodedName = Uri.encodeComponent(fileName);
      final tokenQuery = sessionToken != null ? '&token=${Uri.encodeComponent(sessionToken)}' : '';

      // Crear la solicitud a /upload?filename=...&token=...
      final request = await _client.post(host, port, '/upload?filename=$encodedName$tokenQuery');
      request.headers.set('Content-Type', 'application/octet-stream');
      request.headers.set('Content-Length', fileSize.toString());
      if (sessionToken != null) {
        request.headers.set('X-Session-Token', sessionToken);
      }

      int bytesSent = 0;
      onProgress?.call(bytesSent, fileSize);

      // Enviar el archivo como stream
      final fileStream = file.openRead();
      await for (final chunk in fileStream) {
        request.add(chunk);
        bytesSent += chunk.length;
        onProgress?.call(bytesSent, fileSize);
      }

      // Obtener la respuesta
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        debugPrint('[Client] Archivo enviado exitosamente: $fileName');
        _lastError = null;
        return true;
      } else {
        final msg = '[Client] Error al enviar: ${response.statusCode} - $responseBody';
        debugPrint(msg);
        _lastError = responseBody.isNotEmpty ? responseBody : 'Error ${response.statusCode}';
        return false;
      }
    } catch (e) {
      final msg = '[Client] Error enviando archivo: $e';
      debugPrint(msg);
      _lastError = e.toString();
      return false;
    }
  }

  /// Envía múltiples archivos secuencialmente.
  ///
  /// [sessionToken] es el token de sesión para autorizar el envío.
  /// [onProgress] reporta el índice del archivo actual, bytes enviados y total.
  /// Retorna una lista de booleanos indicando el éxito de cada envío.
  Future<List<bool>> sendMultipleFiles(
    String host,
    int port,
    List<String> filePaths, {
    String? sessionToken,
    void Function(int fileIndex, int sent, int total)? onProgress,
  }) async {
    final results = <bool>[];

    for (int i = 0; i < filePaths.length; i++) {
      final success = await sendFile(
        host,
        port,
        filePaths[i],
        sessionToken: sessionToken,
        onProgress: (sent, total) {
          onProgress?.call(i, sent, total);
        },
      );
      results.add(success);
    }

    return results;
  }

  /// Obtiene la lista de archivos disponibles en el servidor remoto.
  ///
  /// Retorna una lista de mapas con información de cada archivo
  /// (name, size, modified).
  Future<List<Map<String, dynamic>>> getRemoteFiles(String host, int port) async {
    try {
      final request = await _client.get(host, port, '/files');
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final list = jsonDecode(body) as List;
        return list.cast<Map<String, dynamic>>();
      }

      return [];
    } catch (e) {
      debugPrint('[Client] Error obteniendo archivos remotos: $e');
      return [];
    }
  }

  /// Descarga un archivo del servidor remoto.
  ///
  /// [fileName] es el nombre del archivo en el servidor.
  /// [savePath] es la ruta completa donde guardar el archivo descargado.
  /// [onProgress] callback para reportar progreso de descarga.
  ///
  /// Retorna true si la descarga fue exitosa.
  Future<bool> downloadFile(
    String host,
    int port,
    String fileName,
    String savePath, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final encodedName = Uri.encodeComponent(fileName);
      final request = await _client.get(host, port, '/download?file=$encodedName');
      final response = await request.close();

      if (response.statusCode != 200) {
        debugPrint('[Client] Error descargando: ${response.statusCode}');
        return false;
      }

      final contentLength = response.contentLength;
      final file = File(savePath);
      final sink = file.openWrite();

      int received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, contentLength);
      }

      await sink.flush();
      await sink.close();

      debugPrint('[Client] Archivo descargado: $fileName → $savePath');
      return true;
    } catch (e) {
      debugPrint('[Client] Error descargando archivo: $e');
      return false;
    }
  }

  /// Cierra el cliente y libera recursos.
  void dispose() {
    _client.close();
  }
}
