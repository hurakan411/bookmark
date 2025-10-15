import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'dart:convert';
import 'package:charset_converter/charset_converter.dart';

Future<String?> fetchWebPageTitle(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      // 1. Content-Typeヘッダーからcharsetを判定
      String? charset;
      final contentType = response.headers['content-type'];
      if (contentType != null) {
        final charsetMatch = RegExp(r'charset=([\w-]+)', caseSensitive: false).firstMatch(contentType);
        if (charsetMatch != null) {
          charset = charsetMatch.group(1)?.toLowerCase();
        }
      }

      // 2. charsetが不明な場合、HTMLの先頭からmetaタグを探す
      if (charset == null) {
        final htmlPreview = String.fromCharCodes(response.bodyBytes.take(1024));
        // シンプルな文字列検索でcharsetを探す
        if (htmlPreview.contains('charset=')) {
          final charsetIndex = htmlPreview.indexOf('charset=');
          final charsetStart = charsetIndex + 8;
          final charsetEnd = htmlPreview.indexOf('"', charsetStart);
          if (charsetEnd > charsetStart) {
            charset = htmlPreview.substring(charsetStart, charsetEnd).trim().toLowerCase();
          }
        }
      }

      // デフォルトはUTF-8
      charset ??= 'utf-8';

      // 3. charsetに応じてデコード
      String htmlText;
      if (charset == 'shift_jis' || charset == 'shift-jis' || charset == 'sjis') {
        htmlText = await CharsetConverter.decode('SHIFT_JIS', response.bodyBytes);
      } else if (charset == 'euc-jp' || charset == 'eucjp') {
        htmlText = await CharsetConverter.decode('EUC-JP', response.bodyBytes);
      } else {
        htmlText = utf8.decode(response.bodyBytes, allowMalformed: true);
      }

      final document = html_parser.parse(htmlText);
      final title = document.querySelector('title')?.text ?? '';
      return title.trim();
    }
  } catch (e) {
    // ignore errors
  }
  return '';
}
