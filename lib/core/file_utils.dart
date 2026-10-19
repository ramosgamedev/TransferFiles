/// Utilidades para manejo de archivos en TransferFiles.
///
/// Proporciona funciones para obtener iconos según el tipo de archivo,
/// determinar tipos MIME, gestionar directorios de descarga y
/// listar archivos en un directorio.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

/// Retorna el icono de Material Design apropiado según la extensión del archivo.
///
/// Clasifica los archivos en categorías comunes y retorna un icono
/// representativo. Si la extensión no es reconocida, retorna un icono genérico.
IconData getFileIcon(String extension) {
  // Normalizar la extensión a minúsculas sin punto
  final ext = extension.toLowerCase().replaceAll('.', '');

  // Mapeo de extensiones a iconos por categoría
  // Imágenes
  if ({'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico'}
      .contains(ext)) {
    return Icons.image;
  }

  // Videos
  if ({'mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm', '3gp'}
      .contains(ext)) {
    return Icons.video_file;
  }

  // Audio
  if ({'mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a'}.contains(ext)) {
    return Icons.audio_file;
  }

  // Documentos de texto
  if ({'doc', 'docx', 'odt', 'rtf', 'txt', 'log'}.contains(ext)) {
    return Icons.description;
  }

  // Hojas de cálculo
  if ({'xls', 'xlsx', 'ods', 'csv'}.contains(ext)) {
    return Icons.table_chart;
  }

  // Presentaciones
  if ({'ppt', 'pptx', 'odp'}.contains(ext)) {
    return Icons.slideshow;
  }

  // PDF
  if (ext == 'pdf') {
    return Icons.picture_as_pdf;
  }

  // Archivos comprimidos
  if ({'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'}.contains(ext)) {
    return Icons.folder_zip;
  }

  // Código fuente
  if ({'dart', 'py', 'js', 'ts', 'java', 'kt', 'cpp', 'c', 'h', 'cs',
       'go', 'rs', 'swift', 'rb', 'php', 'html', 'css', 'xml', 'json',
       'yaml', 'yml', 'toml', 'sql', 'sh', 'bat', 'ps1'}
      .contains(ext)) {
    return Icons.code;
  }

  // APK / Instaladores
  if ({'apk', 'exe', 'msi', 'dmg', 'deb', 'rpm'}.contains(ext)) {
    return Icons.install_mobile;
  }

  // Fuentes
  if ({'ttf', 'otf', 'woff', 'woff2'}.contains(ext)) {
    return Icons.font_download;
  }

  // Bases de datos
  if ({'db', 'sqlite', 'sqlite3', 'mdb'}.contains(ext)) {
    return Icons.storage;
  }

  // Archivo genérico si no se reconoce la extensión
  return Icons.insert_drive_file;
}

/// Obtiene el tipo MIME de un archivo basándose en su ruta.
///
/// Utiliza el paquete `mime` para determinar el tipo MIME.
/// Si no se puede determinar, retorna 'application/octet-stream'.
String getMimeType(String filePath) {
  final mimeType = lookupMimeType(filePath);
  return mimeType ?? 'application/octet-stream';
}

/// Obtiene el directorio de descarga apropiado según la plataforma.
///
/// - Windows/Linux/macOS: Carpeta de Descargas del usuario + /TransferFiles
/// - Android: Directorio externo de la aplicación + /TransferFiles
///
/// Crea el directorio si no existe.
Future<String> getDownloadDirectory() async {
  try {
    String basePath;

    if (Platform.isAndroid) {
      // En Android/Quest, usar la carpeta Download pública para que
      // los archivos sean accesibles desde cualquier explorador.
      // Requiere MANAGE_EXTERNAL_STORAGE (solicitado en QuestHome).
      const publicDownload = '/storage/emulated/0/Download';
      final publicDir = Directory(publicDownload);
      if (await publicDir.exists()) {
        basePath = publicDownload;
      } else {
        // Respaldo: usar el directorio externo de la app
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          basePath = externalDir.path;
        } else {
          final appDir = await getApplicationDocumentsDirectory();
          basePath = appDir.path;
        }
      }
    } else if (Platform.isWindows) {
      // En Windows, usar la carpeta de Descargas del usuario
      final userHome = Platform.environment['USERPROFILE'] ?? '';
      basePath = '$userHome\\Downloads';
    } else if (Platform.isMacOS) {
      // En macOS, usar la carpeta de Descargas
      final userHome = Platform.environment['HOME'] ?? '';
      basePath = '$userHome/Downloads';
    } else {
      // Linux y otras plataformas
      final userHome = Platform.environment['HOME'] ?? '';
      basePath = '$userHome/Downloads';
    }

    // Crear el subdirectorio TransferFiles
    final separator = Platform.isWindows ? '\\' : '/';
    final transferDir = '$basePath${separator}TransferFiles';

    await ensureDirectoryExists(transferDir);
    return transferDir;
  } catch (e) {
    print('[FileUtils] Error obteniendo directorio de descarga: $e');
    // Respaldo: usar el directorio temporal
    final tempDir = await getTemporaryDirectory();
    final fallbackPath = '${tempDir.path}${Platform.pathSeparator}TransferFiles';
    await ensureDirectoryExists(fallbackPath);
    return fallbackPath;
  }
}

/// Lista todos los archivos en un directorio dado.
///
/// Retorna una lista vacía si el directorio no existe o si ocurre un error.
/// Solo incluye archivos (no subdirectorios).
Future<List<FileSystemEntity>> getFilesInDirectory(String dirPath) async {
  try {
    final directory = Directory(dirPath);

    // Verificar que el directorio exista
    if (!await directory.exists()) {
      print('[FileUtils] El directorio no existe: $dirPath');
      return [];
    }

    // Listar solo archivos, no subdirectorios
    final entities = await directory.list(followLinks: false).toList();
    final files = entities.whereType<File>().cast<FileSystemEntity>().toList();

    return files;
  } catch (e) {
    print('[FileUtils] Error listando archivos en $dirPath: $e');
    return [];
  }
}

/// Asegura que un directorio exista, creándolo si es necesario.
///
/// Crea todos los directorios padres que falten (recursivo).
/// Retorna el objeto Directory creado o existente.
Future<Directory> ensureDirectoryExists(String path) async {
  final directory = Directory(path);

  if (!await directory.exists()) {
    await directory.create(recursive: true);
    print('[FileUtils] Directorio creado: $path');
  }

  return directory;
}
