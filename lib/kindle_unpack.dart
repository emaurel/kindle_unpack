/// A pure-Dart library for reading Amazon Kindle ebook files
/// (MOBI / AZW / AZW3 / KF8).
///
/// This is the public entry point; everything else lives in `src/`.
library;

export 'src/decompress/book_text.dart';
export 'src/decompress/huff_cdic.dart';
export 'src/decompress/palmdoc.dart';
export 'src/decompress/trailing_data.dart';
export 'src/headers/exth.dart';
export 'src/headers/header_exception.dart';
export 'src/headers/mobi_header.dart';
export 'src/headers/palmdoc_header.dart';
export 'src/images.dart';
export 'src/pdb.dart';
