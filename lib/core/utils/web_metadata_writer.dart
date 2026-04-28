import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/models.dart';

/// A specialized utility to inject basic metadata into audio files for the web.
class WebMetadataWriter {
  static Future<Uint8List> injectMetadata(Uint8List bytes, Track track, Dio dio) async {
    print('[WebMetadata] Processing metadata for: ${track.title}');
    
    // Detect format via magic bytes
    if (bytes.length > 8 && bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) {
      return _injectFlacMetadata(bytes, track, dio);
    } else if (bytes.length > 8 && _isMp4(bytes)) {
      return _injectMp4Metadata(bytes, track, dio);
    }

    print('[WebMetadata] Unsupported format for metadata injection, skipping');
    return bytes;
  }

  static bool _isMp4(Uint8List bytes) {
    return bytes.length > 8 && 
           bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70;
  }

  // ── FLAC ENGINE ─────────────────────────────────────────────────────────────

  static Future<Uint8List> _injectFlacMetadata(Uint8List bytes, Track track, Dio dio) async {
    try {
      final blocks = <_MetadataBlock>[];
      int offset = 4;
      bool isLast = false;

      while (!isLast && offset + 4 <= bytes.length) {
        final headerByte = bytes[offset];
        isLast = (headerByte & 0x80) != 0;
        final type = headerByte & 0x7F;
        final length = (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
        offset += 4;
        if (offset + length > bytes.length) break;
        final data = bytes.sublist(offset, offset + length);
        if (type != 4 && type != 6) blocks.add(_MetadataBlock(type: type, data: data));
        offset += length;
      }

      final audioData = bytes.sublist(offset);
      blocks.add(_MetadataBlock(type: 4, data: _createVorbisCommentBlock(track)));
      if (track.albumCover != null && track.albumCover!.isNotEmpty) {
        final pic = await _createPictureBlock(track.albumCover!, dio);
        if (pic != null) blocks.add(_MetadataBlock(type: 6, data: pic));
      }

      final b = BytesBuilder(copy: false);
      b.add(Uint8List.fromList([0x66, 0x4C, 0x61, 0x43]));
      for (int i = 0; i < blocks.length; i++) {
        final blk = blocks[i];
        final h = Uint8List(4);
        h[0] = ((i == blocks.length - 1) ? 0x80 : 0x00) | (blk.type & 0x7F);
        h[1] = (blk.data.length >> 16) & 0xFF;
        h[2] = (blk.data.length >> 8) & 0xFF;
        h[3] = blk.data.length & 0xFF;
        b.add(h); b.add(blk.data);
      }
      b.add(audioData);
      return b.takeBytes();
    } catch (e) { return bytes; }
  }

  // ── MP4 ENGINE (M4A/AAC) ─────────────────────────────────────────────────────

  static Future<Uint8List> _injectMp4Metadata(Uint8List bytes, Track track, Dio dio) async {
    try {
      print('[WebMetadata] Walking MP4 atoms...');
      
      Uint8List? cover = (track.albumCover != null) ? await _fetchImage(track.albumCover!, dio) : null;
      final ilst = BytesBuilder(copy: false);
      _addMp4Tag(ilst, '\u00a9nam', track.title);
      _addMp4Tag(ilst, '\u00a9ART', track.artist);
      _addMp4Tag(ilst, '\u00a9alb', track.albumTitle ?? '');
      if (cover != null) {
        ilst.add(_buildAtom('covr', [
          _buildAtom('data', [Uint8List.fromList([0,0,0,13,0,0,0,0]), cover])
        ]));
      }

      final udta = _buildAtom('udta', [
        _buildAtom('meta', [
          Uint8List(4),
          _buildAtom('hdlr', [Uint8List(8), Uint8List.fromList('mdirappl'.codeUnits), Uint8List(8), Uint8List.fromList('BeatBoss\u0000'.codeUnits)]),
          _buildAtom('ilst', [ilst.takeBytes()])
        ])
      ]);

      // Find moov
      int moovOff = -1, moovSize = 0, offset = 0;
      while (offset + 8 <= bytes.length) {
        final size = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
        final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
        if (type == 'moov') { moovOff = offset; moovSize = size; break; }
        if (size < 8) break; offset += size;
      }

      if (moovOff == -1) return bytes;

      // Extract and clean moov
      final moovBody = bytes.sublist(moovOff + 8, moovOff + moovSize);
      final cleanMoov = BytesBuilder(copy: false);
      int sub = 0;
      while (sub + 8 <= moovBody.length) {
        final s = ByteData.sublistView(moovBody, sub, sub + 4).getUint32(0);
        final t = String.fromCharCodes(moovBody.sublist(sub + 4, sub + 8));
        if (t != 'udta' && s >= 8) cleanMoov.add(moovBody.sublist(sub, sub + s));
        sub += s;
      }
      cleanMoov.add(udta);
      
      final newBody = cleanMoov.takeBytes();
      final shift = (newBody.length + 8) - moovSize;

      // CRITICAL: If moov is at the start, we MUST shift stco/co64 offsets
      // if the music data (mdat) comes after the moov.
      int mdatOff = -1;
      int scan = 0;
      while (scan + 8 <= bytes.length) {
        final s = ByteData.sublistView(bytes, scan, scan + 4).getUint32(0);
        final t = String.fromCharCodes(bytes.sublist(scan + 4, scan + 8));
        if (t == 'mdat') { mdatOff = scan; break; }
        if (s < 8) break; scan += s;
      }

      if (moovOff < mdatOff && shift != 0) {
        print('[WebMetadata] Shifting stco offsets by $shift bytes...');
        _shiftOffsets(newBody, shift);
      }

      final moovAtom = _buildAtom('moov', [newBody]);
      final res = BytesBuilder(copy: false);
      res.add(bytes.sublist(0, moovOff));
      res.add(moovAtom);
      res.add(bytes.sublist(moovOff + moovSize));
      return res.takeBytes();
    } catch (e) { return bytes; }
  }

  static void _shiftOffsets(Uint8List data, int shift) {
    int i = 0;
    while (i + 8 <= data.length) {
      final size = ByteData.sublistView(data, i, i + 4).getUint32(0);
      final type = String.fromCharCodes(data.sublist(i + 4, i + 8));
      
      if (type == 'stco') {
        final count = ByteData.sublistView(data, i + 12, i + 16).getUint32(0);
        for (int c = 0; c < count; c++) {
          final offPos = i + 16 + (c * 4);
          if (offPos + 4 <= data.length) {
            final old = ByteData.sublistView(data, offPos, offPos + 4).getUint32(0);
            ByteData.view(data.buffer).setUint32(data.offsetInBytes + offPos, old + shift);
          }
        }
      } else if (type == 'co64') {
        final count = ByteData.sublistView(data, i + 12, i + 16).getUint32(0);
        for (int c = 0; c < count; c++) {
          final offPos = i + 16 + (c * 8);
          if (offPos + 8 <= data.length) {
            final old = ByteData.sublistView(data, offPos, offPos + 8).getUint64(0);
            ByteData.view(data.buffer).setUint64(data.offsetInBytes + offPos, old + shift);
          }
        }
      } else if (['trak', 'mdia', 'minf', 'stbl'].contains(type)) {
        // Recurse into container atoms
        _shiftOffsets(Uint8List.view(data.buffer, data.offsetInBytes + i + 8, size - 8), shift);
      }
      if (size < 8) break;
      i += size;
    }
  }

  static void _addMp4Tag(BytesBuilder b, String n, String v) {
    if (v.isEmpty) return;
    b.add(_buildAtom(n, [_buildAtom('data', [Uint8List.fromList([0,0,0,1,0,0,0,0]), Uint8List.fromList(v.codeUnits)])]));
  }

  static Uint8List _buildAtom(String n, List<Uint8List> p) {
    final b = BytesBuilder(copy: false);
    for (var x in p) b.add(x);
    final d = b.takeBytes();
    final h = Uint8List(8);
    ByteData.view(h.buffer).setUint32(0, d.length + 8);
    h.setRange(4, 8, n.codeUnits);
    return Uint8List.fromList([...h, ...d]);
  }

  static Future<Uint8List?> _fetchImage(String url, Dio dio) async {
    try {
      final r = await dio.get(url, options: Options(responseType: ResponseType.bytes));
      final d = r.data;
      return d is Uint8List ? d : Uint8List.fromList((d as List).cast<int>());
    } catch (_) {
      try {
        final p = 'https://webdownloadproxy.thevolecitor.workers.dev/?url=${Uri.encodeComponent(url)}';
        final r = await dio.get(p, options: Options(responseType: ResponseType.bytes));
        final d = r.data;
        return d is Uint8List ? d : Uint8List.fromList((d as List).cast<int>());
      } catch (_) { return null; }
    }
  }

  static Uint8List _createVorbisCommentBlock(Track t) {
    final c = {'TITLE': t.title, 'ARTIST': t.artist, 'ALBUM': t.albumTitle ?? ''};
    final b = BytesBuilder(copy: false);
    b.add(Uint8List(4)..buffer.asByteData().setUint32(0, 8, Endian.little)); b.add(Uint8List.fromList('BeatBoss'.codeUnits));
    b.add(Uint8List(4)..buffer.asByteData().setUint32(0, c.length, Endian.little));
    for (var e in c.entries) {
      final s = '${e.key}=${e.value}';
      b.add(Uint8List(4)..buffer.asByteData().setUint32(0, s.length, Endian.little));
      b.add(Uint8List.fromList(s.codeUnits));
    }
    return b.takeBytes();
  }

  static Future<Uint8List?> _createPictureBlock(String u, Dio d) async {
    final i = await _fetchImage(u, d); if (i == null) return null;
    final b = BytesBuilder(copy: false);
    b.add(Uint8List(4)..buffer.asByteData().setUint32(0, 3, Endian.big));
    const m = 'image/jpeg'; b.add(Uint8List(4)..buffer.asByteData().setUint32(0, m.length, Endian.big)); b.add(Uint8List.fromList(m.codeUnits));
    b.add(Uint8List(20)); b.add(Uint8List(4)..buffer.asByteData().setUint32(0, i.length, Endian.big)); b.add(i);
    return b.takeBytes();
  }
}

class _MetadataBlock {
  final int type;
  final Uint8List data;
  _MetadataBlock({required this.type, required this.data});
}
