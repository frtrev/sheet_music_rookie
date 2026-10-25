import 'package:xml/xml.dart';

/// A MusicXML lyric line. Keep the original element to retain elisions,
/// language, verse names and extension types when exporting.
class NoteLyric {
  const NoteLyric(this.xml);
  final String xml;
  static final _elements = Expando<XmlElement>();
  XmlElement get element =>
      _elements[this] ??= XmlDocument.parse(xml).rootElement;
  String get number => element.getAttribute('number') ?? '1';
  String get text => element.children
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'text' || e.name.local == 'elision')
      .map((e) => e.innerText)
      .join();
  String? get syllabic => element.getElement('syllabic')?.innerText;
  bool get extendsNote => element.getElement('extend') != null;
}
