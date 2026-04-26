import 'dart:convert';
import 'dart:typed_data';

import 'header_exception.dart';
import 'palmdoc_header.dart';

/// The variable-length MOBI header that follows the 16-byte PalmDOC header.
///
/// Field offsets are quoted relative to the start of the MOBI signature
/// (i.e. record-0 offset [PalmDocHeader.byteSize]). The header's declared
/// [headerLength] determines which fields are present; trailing fields
/// missing from a short header are reported as `null` rather than read from
/// whatever happens to follow (often EXTH bytes).
class MobiHeader {
  const MobiHeader({
    required this.headerLength,
    required this.mobiType,
    required this.textEncoding,
    required this.uniqueId,
    required this.fileVersion,
    required this.firstNonBookIndex,
    required this.fullNameOffset,
    required this.fullNameLength,
    required this.locale,
    required this.inputLanguage,
    required this.outputLanguage,
    required this.minVersion,
    required this.firstImageIndex,
    required this.huffmanRecordOffset,
    required this.huffmanRecordCount,
    required this.huffmanTableOffset,
    required this.huffmanTableLength,
    required this.exthFlags,
    required this.drmOffset,
    required this.drmCount,
    required this.drmSize,
    required this.drmFlags,
  });

  /// 4-byte signature at the start of the MOBI header.
  static const String signature = 'MOBI';

  /// Sentinel meaning "field unset" in 32-bit MOBI fields.
  static const int unset = 0xFFFFFFFF;

  /// Length of the MOBI header in bytes (including the 4-byte signature
  /// and this field itself).
  final int headerLength;

  /// Mobi document type. 2 = Mobipocket book, 3 = PalmDOC book, 257 = News,
  /// etc. We store the raw int — downstream code can decide what to allow.
  final int mobiType;

  /// Codepage of textual fields in this header and of the book text:
  /// 1252 = Windows-1252, 65001 = UTF-8.
  final int textEncoding;

  final int uniqueId;
  final int fileVersion;

  /// Record index of the first non-book record (indexes, etc.).
  final int firstNonBookIndex;

  /// Byte offset of the human-readable book title within record 0.
  final int fullNameOffset;
  final int fullNameLength;

  /// Numeric locale code. 9 = English, etc. See MobiPerl docs.
  final int locale;
  final int inputLanguage;
  final int outputLanguage;
  final int minVersion;

  /// Record index of the first image record (or [unset]).
  final int firstImageIndex;

  /// HUFF/CDIC compression: index of the first HUFF record and count of
  /// HUFF/CDIC records that follow it.
  final int huffmanRecordOffset;
  final int huffmanRecordCount;
  final int huffmanTableOffset;
  final int huffmanTableLength;

  /// Bitfield: bit 0x40 set means an EXTH header follows the MOBI header.
  final int exthFlags;

  /// DRM section. All four fields are absent in old / short MOBI headers,
  /// and in newer ones [drmOffset] = [unset] means "no DRM".
  final int? drmOffset;
  final int? drmCount;
  final int? drmSize;
  final int? drmFlags;

  /// True if an EXTH header sits immediately after this MOBI header.
  bool get hasExth => (exthFlags & 0x40) != 0;

  /// True if the MOBI header advertises a DRM section with at least one
  /// entry. This signals the file is encrypted; this library cannot parse
  /// the text body.
  bool get hasDrm {
    final off = drmOffset;
    final count = drmCount;
    if (off == null || count == null) return false;
    if (off == unset || count == unset) return false;
    return count > 0;
  }

  /// Byte offset within record 0 where the EXTH header begins (whether or
  /// not [hasExth] is true).
  int get exthOffset => PalmDocHeader.byteSize + headerLength;

  /// Best-effort decode of the book's full title from record 0. Uses UTF-8
  /// when [textEncoding] is 65001, otherwise latin1 (a close-enough stand-in
  /// for Windows-1252; a strict decoder can be added later).
  String fullName(Uint8List record0) {
    if (fullNameLength == 0) return '';
    final end = fullNameOffset + fullNameLength;
    if (end > record0.length) {
      throw HeaderException(
        'full name [$fullNameOffset, $end) extends past record 0 '
        '(${record0.length})',
      );
    }
    final slice = Uint8List.sublistView(record0, fullNameOffset, end);
    return textEncoding == 65001
        ? utf8.decode(slice, allowMalformed: true)
        : latin1.decode(slice);
  }

  static MobiHeader parse(Uint8List record0) {
    const sigOffset = PalmDocHeader.byteSize;
    if (record0.length < sigOffset + 8) {
      throw HeaderException(
        'record 0 too short for MOBI signature + length: ${record0.length}',
      );
    }
    final view = ByteData.sublistView(record0);

    final sig = latin1.decode(
      Uint8List.sublistView(record0, sigOffset, sigOffset + 4),
    );
    if (sig != signature) {
      throw HeaderException('expected "$signature" signature, got "$sig"');
    }

    final headerLength = view.getUint32(sigOffset + 4);
    if (headerLength < 24) {
      throw HeaderException(
        'MOBI header length too small: $headerLength (need >= 24)',
      );
    }
    if (sigOffset + headerLength > record0.length) {
      throw HeaderException(
        'MOBI header (length $headerLength) extends past record 0 '
        '(${record0.length})',
      );
    }

    /// Read a uint32 at [relOffset] inside the MOBI header. Returns null
    /// when the declared [headerLength] doesn't reach this field — those
    /// bytes belong to whatever follows (typically EXTH) and are not ours
    /// to interpret.
    int? readU32(int relOffset) {
      if (relOffset + 4 > headerLength) return null;
      return view.getUint32(sigOffset + relOffset);
    }

    return MobiHeader(
      headerLength: headerLength,
      mobiType: readU32(8) ?? 0,
      textEncoding: readU32(12) ?? 0,
      uniqueId: readU32(16) ?? 0,
      fileVersion: readU32(20) ?? 0,
      firstNonBookIndex: readU32(80) ?? unset,
      fullNameOffset: readU32(84) ?? 0,
      fullNameLength: readU32(88) ?? 0,
      locale: readU32(92) ?? 0,
      inputLanguage: readU32(96) ?? 0,
      outputLanguage: readU32(100) ?? 0,
      minVersion: readU32(104) ?? 0,
      firstImageIndex: readU32(108) ?? unset,
      huffmanRecordOffset: readU32(112) ?? 0,
      huffmanRecordCount: readU32(116) ?? 0,
      huffmanTableOffset: readU32(120) ?? 0,
      huffmanTableLength: readU32(124) ?? 0,
      exthFlags: readU32(128) ?? 0,
      drmOffset: readU32(164),
      drmCount: readU32(168),
      drmSize: readU32(172),
      drmFlags: readU32(176),
    );
  }
}
