import 'package:xml/xml.dart';

/// A MusicXML lyric line. Keep the original element to retain elisions,
/// language, verse names and extension types when exporting.
class NoteLyric {
  const NoteLyric(this.xml);
  final String xml;
  factory NoteLyric.fromText(String number, String text) => NoteLyric(
    XmlElement(
      XmlName.parts('lyric'),
      [XmlAttribute(XmlName.parts('number'), number)],
      [
        XmlElement(XmlName.parts('text'), [], [XmlText(text)]),
      ],
    ).toXmlString(),
  );

  NoteLyric withText(String text) {
    if (text == this.text) return this;
    final updated = element.copy();
    final textElement =
        updated.getElement('text')?.copy() ?? XmlElement(XmlName.parts('text'));
    textElement.children
      ..clear()
      ..add(XmlText(text));
    final index = updated.children.indexWhere(
      (node) =>
          node is XmlElement &&
          (node.name.local == 'text' || node.name.local == 'elision'),
    );
    updated.children.removeWhere(
      (node) =>
          node is XmlElement &&
          (node.name.local == 'text' || node.name.local == 'elision'),
    );
    updated.children.insert(
      index < 0 ? updated.children.length : index,
      textElement,
    );
    return NoteLyric(updated.toXmlString());
  }

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
