import 'package:xml/xml.dart';

enum MeasureEdge { left, right }

/// Edits repeat and ending marks without discarding imported barline metadata.
class MeasureMarks {
  const MeasureMarks(this.barlines);
  final List<String> barlines;

  bool _atEdge(XmlElement bar, MeasureEdge edge) =>
      (bar.getAttribute('location') ?? 'right') == edge.name;

  bool _matches(XmlElement element, MeasureEdge edge, bool volta) => volta
      ? element.name.local == 'ending' &&
            (edge == MeasureEdge.left
                ? element.getAttribute('type') == 'start'
                : const {
                    'stop',
                    'discontinue',
                  }.contains(element.getAttribute('type')))
      : element.name.local == 'repeat' &&
            element.getAttribute('direction') ==
                (edge == MeasureEdge.left ? 'forward' : 'backward');

  XmlElement? _mark(MeasureEdge edge, bool volta) {
    for (final xml in barlines) {
      final bar = XmlDocument.parse(xml).rootElement;
      if (!_atEdge(bar, edge)) continue;
      for (final child in bar.childElements) {
        if (_matches(child, edge, volta)) return child;
      }
    }
    return null;
  }

  bool hasRepeat(MeasureEdge edge) => _mark(edge, false) != null;
  String? voltaNumber(MeasureEdge edge) =>
      _mark(edge, true)?.getAttribute('number');

  List<String> toggleRepeat(MeasureEdge edge) =>
      _update(edge, false, hasRepeat(edge) ? null : '');

  List<String> cycleVolta(MeasureEdge edge) {
    final current = int.tryParse(voltaNumber(edge) ?? '') ?? 0;
    final next = current >= 1 && current < 3
        ? current + 1
        : current == 3
        ? 0
        : 1;
    return _update(edge, true, next == 0 ? null : '$next');
  }

  List<String> _update(MeasureEdge edge, bool volta, String? number) {
    final result = <String>[];
    var added = false;
    for (final xml in barlines) {
      final bar = XmlDocument.parse(xml).rootElement;
      if (!_atEdge(bar, edge)) {
        result.add(xml);
        continue;
      }
      final previous = bar.childElements
          .where((e) => _matches(e, edge, volta))
          .firstOrNull;
      final replacement =
          previous?.copy() ??
          XmlElement(XmlName.parts(volta ? 'ending' : 'repeat'));
      bar.children.removeWhere(
        (e) => e is XmlElement && _matches(e, edge, volta),
      );
      if (number != null && !added) {
        if (volta) {
          replacement.setAttribute('number', number);
          replacement.setAttribute(
            'type',
            edge == MeasureEdge.left ? 'start' : 'stop',
          );
          final repeatIndex = bar.children.indexWhere(
            (e) => e is XmlElement && e.name.local == 'repeat',
          );
          bar.children.insert(
            repeatIndex < 0 ? bar.children.length : repeatIndex,
            replacement,
          );
        } else {
          replacement.setAttribute(
            'direction',
            edge == MeasureEdge.left ? 'forward' : 'backward',
          );
          bar.children.add(replacement);
        }
        added = true;
      }
      if (bar.childElements.isNotEmpty ||
          bar.attributes.any((a) => a.name.local != 'location')) {
        result.add(bar.toXmlString());
      }
    }
    if (number != null && !added) {
      final mark = volta
          ? '<ending number="$number" type="${edge == MeasureEdge.left ? 'start' : 'stop'}"/>'
          : '<repeat direction="${edge == MeasureEdge.left ? 'forward' : 'backward'}"/>';
      final bar = '<barline location="${edge.name}">$mark</barline>';
      edge == MeasureEdge.left ? result.insert(0, bar) : result.add(bar);
    }
    return result;
  }
}
