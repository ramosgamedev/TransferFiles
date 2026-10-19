import 'dart:convert';

void main() {
  final boundary = 'TransferFiles12345';
  final fileName = 'test.txt';
  
  final headerStr =
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'
      'Content-Type: application/octet-stream\r\n'
      '\r\n';
  final footerStr = '\r\n--$boundary--\r\n';
  
  final headerBytes = utf8.encode(headerStr);
  final fileBytesData = utf8.encode('Hello World!');
  final footerBytes = utf8.encode(footerStr);
  
  final allBytes = <int>[...headerBytes, ...fileBytesData, ...footerBytes];
  
  final boundaryBytes = utf8.encode('--$boundary');
  
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
  
  print('Found boundaries: ${boundaryPositions.length}');
  
  for (int i = 0; i < boundaryPositions.length - 1; i++) {
    final partStart = boundaryPositions[i] + boundaryBytes.length;
    final partEnd = boundaryPositions[i + 1];

    int dataStart = partStart;
    if (dataStart < allBytes.length && allBytes[dataStart] == 0x0D) dataStart++;
    if (dataStart < allBytes.length && allBytes[dataStart] == 0x0A) dataStart++;

    int headerEnd = -1;
    for (int j = dataStart; j < partEnd - 3; j++) {
      if (allBytes[j] == 0x0D && allBytes[j + 1] == 0x0A &&
          allBytes[j + 2] == 0x0D && allBytes[j + 3] == 0x0A) {
        headerEnd = j;
        break;
      }
    }

    if (headerEnd == -1) {
      print('headerEnd == -1');
      continue;
    }

    final bodyStart = headerEnd + 4;
    int bodyEnd = partEnd;
    if (bodyEnd >= 2 && allBytes[bodyEnd - 1] == 0x0A && allBytes[bodyEnd - 2] == 0x0D) {
      bodyEnd -= 2;
    }

    if (bodyStart >= bodyEnd) {
      print('bodyStart >= bodyEnd');
      continue;
    }
    
    final fileBytes = allBytes.sublist(bodyStart, bodyEnd);
    print('SUCCESS! extracted bytes: ${utf8.decode(fileBytes)}');
  }
}
