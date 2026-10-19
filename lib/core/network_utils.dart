/// Utilidades de red para TransferFiles.
///
/// Proporciona funciones auxiliares para obtener la IP local,
/// formatear tamaños de archivo y velocidades, y validar direcciones IP.
library;

import 'dart:io';

/// Puerto por defecto utilizado por el servidor de transferencias.
const int defaultPort = 8080;

/// Obtiene la dirección IP local del dispositivo en la red WiFi.
///
/// Filtra las interfaces de red para encontrar una dirección IPv4
/// que no sea loopback (127.0.0.1). Retorna '0.0.0.0' si no se
/// encuentra ninguna dirección válida.
Future<String> getLocalIpAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    // Buscar la primera interfaz con una dirección IPv4 válida
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        // Ignorar direcciones de loopback y link-local
        if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
          return address.address;
        }
      }
    }

    // Si no se encontró ninguna, intentar con todas las interfaces
    final allInterfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );

    for (final interface in allInterfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) {
          return address.address;
        }
      }
    }

    return '0.0.0.0';
  } catch (e) {
    // Error al obtener las interfaces de red
    return '0.0.0.0';
  }
}

/// Obtiene todas las direcciones IP locales del dispositivo.
Future<List<String>> getAllLocalIpAddresses() async {
  try {
    final ips = <String>[];
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
          ips.add(address.address);
        }
      }
    }

    if (ips.isEmpty) {
      ips.add('0.0.0.0');
    }
    
    // Sort to prioritize typical local network prefixes (192.168.x.x) over VPNs (10.x.x.x) if multiple exist
    ips.sort((a, b) {
      if (a.startsWith('192.168.') && !b.startsWith('192.168.')) return -1;
      if (!a.startsWith('192.168.') && b.startsWith('192.168.')) return 1;
      return a.compareTo(b);
    });

    return ips;
  } catch (e) {
    return ['0.0.0.0'];
  }
}


/// Formatea un tamaño en bytes a una cadena legible.
///
/// Ejemplos:
///   - 512 → "512 B"
///   - 1024 → "1.0 KB"
///   - 1048576 → "1.0 MB"
///   - 1073741824 → "1.0 GB"
String formatFileSize(int bytes) {
  if (bytes < 0) return '0 B';

  const int kb = 1024;
  const int mb = kb * 1024;
  const int gb = mb * 1024;

  if (bytes >= gb) {
    return '${(bytes / gb).toStringAsFixed(2)} GB';
  } else if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(2)} MB';
  } else if (bytes >= kb) {
    return '${(bytes / kb).toStringAsFixed(2)} KB';
  } else {
    return '$bytes B';
  }
}

/// Formatea una velocidad de transferencia en bytes por segundo.
///
/// Retorna una cadena legible como "1.5 MB/s" o "256 KB/s".
String formatTransferSpeed(int bytesPerSecond) {
  if (bytesPerSecond < 0) return '0 B/s';

  const int kb = 1024;
  const int mb = kb * 1024;
  const int gb = mb * 1024;

  if (bytesPerSecond >= gb) {
    return '${(bytesPerSecond / gb).toStringAsFixed(2)} GB/s';
  } else if (bytesPerSecond >= mb) {
    return '${(bytesPerSecond / mb).toStringAsFixed(2)} MB/s';
  } else if (bytesPerSecond >= kb) {
    return '${(bytesPerSecond / kb).toStringAsFixed(2)} KB/s';
  } else {
    return '$bytesPerSecond B/s';
  }
}

/// Valida si una cadena es una dirección IPv4 válida.
///
/// Verifica que tenga el formato correcto: cuatro octetos numéricos
/// separados por puntos, cada uno entre 0 y 255.
bool isValidIp(String ip) {
  if (ip.isEmpty) return false;

  final parts = ip.split('.');
  if (parts.length != 4) return false;

  for (final part in parts) {
    // Cada parte debe ser un número
    final value = int.tryParse(part);
    if (value == null) return false;

    // Cada octeto debe estar entre 0 y 255
    if (value < 0 || value > 255) return false;

    // No permitir ceros a la izquierda (excepto "0" solo)
    if (part.length > 1 && part.startsWith('0')) return false;
  }

  return true;
}
