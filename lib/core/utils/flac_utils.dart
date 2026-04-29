import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

/// Pure-Dart FLAC metadata injector.
///
/// Strategy (matches the web downloader's approach):
/// 1. Read the raw bytes.
/// 2. Parse all existing metadata blocks.
/// 3. Strip any existing VORBIS_COMMENT and PICTURE blocks (type 4 & 6).
/// 4. Build a new VORBIS_COMMENT block with title/artist/album/cover.
/// 5. Rebuild: magic + STREAMINFO (with total_samples=0) + new tags + remaining
///    blocks + raw audio — all in Dart, zero TagLib/AudioTags involved.
class FlacUtils {
  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Injects FLAC Vorbis Comment tags into [file] and patches STREAMINFO so
  /// that every low-level player (mpv, Android codec) plays the full file.
  static Future<void> injectMetadataAndFix(
    File file, {
    String? title,
    String? artist,
    String? album,
    Uint8List? coverBytes,
    String coverMimeType = 'image/jpeg',
    int? durationSeconds,
  }) async {
    print('[FlacUtils] Injecting metadata into: ${file.path}');
    try {
      final bytes = await file.readAsBytes();

      // 1. Validate magic
      if (bytes.length < 42 ||
          bytes[0] != 0x66 ||
          bytes[1] != 0x4C ||
          bytes[2] != 0x61 ||
          bytes[3] != 0x43) {
        print('[FlacUtils] Not a valid FLAC file, skipping');
        return;
      }

      // 2. Parse existing metadata blocks
      final analysis = _analyzeMetadata(bytes);
      if (analysis == null) {
        print('[FlacUtils] Failed to parse metadata blocks');
        return;
      }

      final audioStart = analysis.declaredEnd;
      print(
          '[FlacUtils] Audio payload starts at byte $audioStart (${bytes.length - audioStart} bytes)');

      // 3. Build new metadata block list:
      //    - Keep STREAMINFO (type 0), SEEKTABLE (3), CUESHEET (5)
      //    - Replace VORBIS_COMMENT (4) and PICTURE (6) with our own
      //    - Drop PADDING (1) to save space
      final List<_MetadataBlock> keepBlocks = [];
      for (final block in analysis.blocks) {
        if (block.type == 0 || block.type == 3 || block.type == 5) {
          keepBlocks.add(block);
        }
      }

      // 4. Build Vorbis Comment block
      final vcBlock = _buildVorbisComment(
        title: title,
        artist: artist,
        album: album,
      );
      keepBlocks.add(vcBlock);

      // 5. Optionally add PICTURE block for cover art
      if (coverBytes != null && coverBytes.isNotEmpty) {
        final picBlock = _buildPictureBlock(coverBytes, coverMimeType);
        keepBlocks.add(picBlock);
      }

      // 6. Patch STREAMINFO: calculate total_samples if duration provided so players see seek bar
      final patchedBlocks = keepBlocks.map((b) {
        if (b.type != 0) return b;
        final d = Uint8List.fromList(b.data);
        // Bits 108-143 of STREAMINFO = bytes 13-17 of the data payload.
        if (d.length >= 18) {
          // Extract sample rate: bits 80-99 (Bytes 10, 11, and bits [7:4] of Byte 12)
          int sampleRate = (d[10] << 12) | (d[11] << 4) | ((d[12] & 0xF0) >> 4);
          if (sampleRate == 0) sampleRate = 44100; // Fallback

          int totalSamples = 0;
          if (durationSeconds != null && durationSeconds > 0) {
            totalSamples = durationSeconds * sampleRate;
          }

          d[13] = (d[13] & 0xF0) | ((totalSamples >> 32) & 0x0F);
          d[14] = (totalSamples >> 24) & 0xFF;
          d[15] = (totalSamples >> 16) & 0xFF;
          d[16] = (totalSamples >> 8) & 0xFF;
          d[17] = totalSamples & 0xFF;
        }
        return _MetadataBlock(type: 0, data: d, offset: b.offset);
      }).toList();

      // 7. Reassemble: magic + blocks + audio
      final output = BytesBuilder(copy: false);
      output.add([0x66, 0x4C, 0x61, 0x43]); // fLaC

      for (int i = 0; i < patchedBlocks.length; i++) {
        final block = patchedBlocks[i];
        final isLast = (i == patchedBlocks.length - 1);
        final header = Uint8List(4);
        header[0] = (isLast ? 0x80 : 0x00) | (block.type & 0x7F);
        header[1] = (block.data.length >> 16) & 0xFF;
        header[2] = (block.data.length >> 8) & 0xFF;
        header[3] = block.data.length & 0xFF;
        output.add(header);
        output.add(block.data);
      }

      // Append the raw audio payload untouched
      output.add(bytes.sublist(audioStart));

      final rebuilt = output.takeBytes();
      print(
          '[FlacUtils] Rebuilt ${rebuilt.length} bytes (original: ${bytes.length})');

      // 8. Write via temp file to avoid partial-write corruption
      final tempFile = File('${file.path}.flactmp');
      await tempFile.writeAsBytes(rebuilt);
      if (await file.exists()) await file.delete();
      await tempFile.rename(file.path);

      print('[FlacUtils] Metadata injected successfully.');
    } catch (e) {
      print('[FlacUtils] injectMetadataAndFix failed: $e');
    }
  }

  /// Legacy no-op shim so no other call-sites break.
  static Future<void> cleanupFlacStructure(File file) async {
    // Nothing — callers should now use injectMetadataAndFix.
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Builds a FLAC VORBIS_COMMENT block (type 4) from track info.
  ///
  /// Format: little-endian 32-bit vendor length + vendor string +
  ///         32-bit comment count + for each: 32-bit length + "KEY=VALUE"
  static _MetadataBlock _buildVorbisComment({
    String? title,
    String? artist,
    String? album,
  }) {
    final comments = <String>[];
    if (title != null && title.isNotEmpty) comments.add('TITLE=$title');
    if (artist != null && artist.isNotEmpty) comments.add('ARTIST=$artist');
    if (album != null && album.isNotEmpty) comments.add('ALBUM=$album');

    const vendor = 'BeatBoss';
    final vendorBytes = utf8.encode(vendor);

    final builder = BytesBuilder();

    // Vendor string
    _writeUint32LE(builder, vendorBytes.length);
    builder.add(vendorBytes);

    // Comment count
    _writeUint32LE(builder, comments.length);

    for (final comment in comments) {
      final commentBytes = utf8.encode(comment);
      _writeUint32LE(builder, commentBytes.length);
      builder.add(commentBytes);
    }

    return _MetadataBlock(type: 4, data: builder.takeBytes(), offset: 0);
  }

  /// Builds a FLAC PICTURE block (type 6) for cover art.
  ///
  /// Spec: https://xiph.org/flac/format.html#metadata_block_picture
  static _MetadataBlock _buildPictureBlock(
      Uint8List imageBytes, String mimeType) {
    final mimeBytes = utf8.encode(mimeType);
    final descBytes = utf8.encode(''); // empty description

    final builder = BytesBuilder();
    _writeUint32BE(builder, 3); // picture type: Cover (front)
    _writeUint32BE(builder, mimeBytes.length); // MIME length
    builder.add(mimeBytes);
    _writeUint32BE(builder, descBytes.length); // description length
    builder.add(descBytes);
    _writeUint32BE(builder, 0); // width (unknown)
    _writeUint32BE(builder, 0); // height (unknown)
    _writeUint32BE(builder, 0); // color depth (unknown)
    _writeUint32BE(builder, 0); // indexed color count
    _writeUint32BE(builder, imageBytes.length);
    builder.add(imageBytes);

    return _MetadataBlock(type: 6, data: builder.takeBytes(), offset: 0);
  }

  static void _writeUint32LE(BytesBuilder b, int v) {
    b.addByte(v & 0xFF);
    b.addByte((v >> 8) & 0xFF);
    b.addByte((v >> 16) & 0xFF);
    b.addByte((v >> 24) & 0xFF);
  }

  static void _writeUint32BE(BytesBuilder b, int v) {
    b.addByte((v >> 24) & 0xFF);
    b.addByte((v >> 16) & 0xFF);
    b.addByte((v >> 8) & 0xFF);
    b.addByte(v & 0xFF);
  }

  /// Parse all metadata blocks from a raw FLAC byte array.
  static _MetadataAnalysis? _analyzeMetadata(Uint8List bytes) {
    final blocks = <_MetadataBlock>[];
    int offset = 4; // skip 'fLaC'
    bool isLast = false;

    while (!isLast && offset + 4 <= bytes.length) {
      final headerByte = bytes[offset];
      isLast = (headerByte & 0x80) != 0;
      final type = headerByte & 0x7F;

      final length = (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];

      offset += 4;

      if (offset + length > bytes.length) {
        print(
            '[FlacUtils] Truncated block at offset $offset (type $type, length $length)');
        return null;
      }

      final data = Uint8List.fromList(bytes.sublist(offset, offset + length));
      blocks.add(_MetadataBlock(type: type, data: data, offset: offset - 4));
      print(
          '[FlacUtils] Block type=${_blockTypeName(type)} len=$length isLast=$isLast');

      offset += length;
    }

    return _MetadataAnalysis(blocks: blocks, declaredEnd: offset);
  }

  static String _blockTypeName(int type) {
    switch (type) {
      case 0:
        return 'STREAMINFO';
      case 1:
        return 'PADDING';
      case 2:
        return 'APPLICATION';
      case 3:
        return 'SEEKTABLE';
      case 4:
        return 'VORBIS_COMMENT';
      case 5:
        return 'CUESHEET';
      case 6:
        return 'PICTURE';
      default:
        return 'UNKNOWN($type)';
    }
  }
}

class _MetadataBlock {
  final int type;
  final Uint8List data;
  final int offset;
  _MetadataBlock(
      {required this.type, required this.data, required this.offset});
}

class _MetadataAnalysis {
  final List<_MetadataBlock> blocks;
  final int declaredEnd;
  _MetadataAnalysis({required this.blocks, required this.declaredEnd});
}
