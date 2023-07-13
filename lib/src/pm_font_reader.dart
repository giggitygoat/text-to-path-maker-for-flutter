import 'dart:typed_data';
import 'dart:io';
import 'dart:collection';

import './pm_font.dart';
import './pm_contour_point.dart';
import './pm_font_table.dart';

/**
* Text to Path Maker
* Copyright Ashraff Hathibelagal 2019
*/

/// This class is used for individual kerning pairs found in format0 kerning tables
class KerningPair {
  KerningPair({
    required this.leftCharacter,
    required this.rightCharacter,
  });
  final int leftCharacter;
  final int rightCharacter;

  @override
  int get hashCode => Object.hash(leftCharacter, rightCharacter);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KerningPair &&
          leftCharacter == other.leftCharacter &&
          rightCharacter == other.rightCharacter;
}

/// This class contains all the code required to read the contents of
/// a .ttf file.
class PMFontReader {
  var fontData;
  var font = PMFont();

  /// Use this method to convert a .ttf file into a PMFont object.
  /// It expects you to pass the path of the .ttf file as its only argument.
  Future<PMFont> parseTTF(path) {
    return File(path).readAsBytes().then((data) {
      fontData = ByteData.view(data.buffer);
      return _parseTTF();
    });
  }

  /// Use this method to convert a .ttf file you have in your assets folder into
  /// a PMFont object.
  PMFont parseTTFAsset(ByteData data) {
    fontData = data;
    return _parseTTF();
  }

  /// This method is responsible for calling a bunch of methods that parse
  /// the tables in the font file. It returns a PMFont object.
  PMFont _parseTTF() {
    var offset = _initializeOffsetTable();
    _initializeTables(offset);
    _readHead();
    _readKernTable();
    _setNumGlyphs();
    _createGlyphs();
    _getCharacterMappings();

    return font;
  }

  /// Initializes the offset table in the .ttf file
  int _initializeOffsetTable() {
    var offset = 0;
    font.sfntVersion = fontData.getUint32(offset);
    offset += 4;
    font.numTables = fontData.getUint16(offset);
    offset += 2;
    font.searchRange = fontData.getUint16(offset);
    offset += 2;
    font.entrySelector = fontData.getUint16(offset);
    offset += 2;
    font.rangeShift = fontData.getUint16(offset);
    offset += 2;
    return offset;
  }

  /// Initializes objects for all the tables in the .ttf file
  void _initializeTables(offset) {
    font.tables = HashMap<String, PMFontTable>();
    for (var i = 0; i < font.numTables; i++) {
      var table = new PMFontTable();
      table.tag = _getTag(fontData, offset);
      offset += 4;
      table.checkSum = fontData.getUint32(offset);
      offset += 4;
      table.offset = fontData.getUint32(offset);
      offset += 4;
      table.length = fontData.getUint32(offset);
      offset += 4;
      font.tables[table.tag] = table;
    }
  }

  /// Each table has a tag, which is composed of 4 characters. This
  /// method reads all the four characters and concatenates them into
  /// a string.
  String _getTag(ByteData fontData, int offset) {
    var charCodes = <int>[];
    charCodes.add(fontData.getUint8(offset));
    charCodes.add(fontData.getUint8(offset + 1));
    charCodes.add(fontData.getUint8(offset + 2));
    charCodes.add(fontData.getUint8(offset + 3));

    return String.fromCharCodes(charCodes);
  }

  /// The kerning table is optional in a .ttf therefore it first checks
  /// whether it is present.
  void _readKernTable() {
    PMFontTable? kernTable = font.tables['kern'];
    if (kernTable != null) {
      int startOffset = kernTable.offset;
      int version = fontData.getUint16(startOffset);
      int nTables = fontData.getUint16(startOffset + 2);
      kernTable.data = {
        'version': version,
        "nTables": nTables,
        "subtables": _getSubtables(nTables, startOffset + 4)
      };
    }
  }

  /// A kerning table can hold multiple subtables
  List _getSubtables(int nTables, int offset) {
    List subtables = [];
    for (int i = 0; i < nTables; i++) {
      int currentOffset = offset + (i * 6);

      int version = fontData.getUint16(currentOffset);
      currentOffset = currentOffset + 2;
      int length = fontData.getUint16(currentOffset);
      currentOffset = currentOffset + 2;
      Map<String, int> coverage =
          _getCoverage(fontData.getUint16(currentOffset));
      currentOffset = currentOffset + 2;
      late Map data;
      if (coverage["format"] == 0) {
        data = _readKernFormat0(currentOffset);
      } else {
        throw Exception("Cannot read format 2 kerning table");
      }
      subtables.add({
        "version": version,
        "length": length,
        "coverage": coverage,
        "data": data
      });
    }
    return subtables;
  }

  /// First it takes the first byte of the uint16,
  /// afterwards it shifts it places and assigns format
  /// to the second byte.
  Map<String, int> _getCoverage(int uint16) {
    int firstByte = uint16 % 0xff;
    return {
      "horizontal": _getBit(firstByte, 0),
      "minimum": _getBit(firstByte, 1),
      "crossStream": _getBit(firstByte, 2),
      "override": _getBit(firstByte, 3), // TODO: Handle case where this is 1
      "reserved1": (firstByte & 0xf0), // nibble 4-7
      "format": firstByte >> 8
    };
  }

  /// Gets individual bit
  int _getBit(int uint16, int bitNr) => ((uint16 & (0x0001 << bitNr)) >> bitNr);

  /// Reads the format0 subtable
  Map<String, dynamic> _readKernFormat0(int offset) {
    int nPairs = fontData.getUint16(offset);
    offset = offset + 2;
    int searchRange = fontData.getUint16(offset);
    offset = offset + 2;
    int entrySelector = fontData.getUint16(offset);
    offset = offset + 2;
    int rangeShift = fontData.getUint16(offset);
    offset = offset + 2;
    HashMap<KerningPair, int> kerningPairs = HashMap();
    for (var i = 0; i < nPairs; i++) {
      int firstCharacter = fontData.getUint16(offset);
      offset = offset + 2;
      int secondCharacter = fontData.getUint16(offset);
      offset = offset + 2;
      int value = fontData.getInt16(offset);
      offset = offset + 2;
      kerningPairs[KerningPair(
        leftCharacter: firstCharacter,
        rightCharacter: secondCharacter,
      )] = value;
    }
    return {
      "nPairs": nPairs,
      "searchRange": searchRange,
      "entrySelector": entrySelector,
      "rangeShift": rangeShift,
      "kerningPairs": kerningPairs
    };
  }

  /// Reads the glyf and loca tables to determine a bunch of coordinates that
  /// can be used to form a glyph.
  void _createGlyphs() {
    var startGlyfOffset = font.tables['glyf'].offset;
    var startLocaOffset = font.tables['loca'].offset;

    var data = {'glyphs': []};
    font.tables['glyf'].data = data;

    for (var i = 0; i < font.numGlyphs + 1; i++) {
      var glyphOffset = startGlyfOffset;

      if (font.tables['head'].data['indexToLocFormat'] == 0) {
        glyphOffset += fontData.getUint16(startLocaOffset) * 2;
        startLocaOffset += 2;
      } else {
        glyphOffset += fontData.getUint32(startLocaOffset);
        startLocaOffset += 4;
      }

      var glyphData = {};
      if (data['glyphs'] == null) {
        // TODO: SET COULD EXCEPTION
        throw Exception("Thrown error: data['glyphs'] was null");
      }

      data['glyphs']?.add(glyphData);

      glyphData['id'] = i;
      glyphData['nContours'] = fontData.getInt16(glyphOffset);
      glyphOffset += 2;
      glyphData['xMin'] = fontData.getInt16(glyphOffset);
      glyphOffset += 2;
      glyphData['yMin'] = fontData.getInt16(glyphOffset);
      glyphOffset += 2;
      glyphData['xMax'] = fontData.getInt16(glyphOffset);
      glyphOffset += 2;
      glyphData['yMax'] = fontData.getInt16(glyphOffset);
      glyphOffset += 2;
      if (glyphData['nContours'] > 0) {
        var contourData = {};
        glyphData['contourData'] = contourData;
        var endIndicesOfContours = [];
        glyphData['endIndices'] = endIndicesOfContours;
        for (var j = 0; j < glyphData['nContours']; j++) {
          endIndicesOfContours.add(fontData.getUint16(glyphOffset));
          glyphOffset += 2;
        }

        contourData['instructionLength'] = fontData.getUint16(glyphOffset);
        glyphOffset += 2;

        contourData['instructions'] = [];
        if (contourData['instructionLength'] > 0) {
          for (var j = 0; j < contourData['instructionLength']; j++) {
            contourData['instructions'].add(fontData.getUint8(glyphOffset));
            glyphOffset += 1;
          }
        }

        contourData['nCoords'] = 0;
        if (endIndicesOfContours.length > 0) {
          contourData['nCoords'] =
              endIndicesOfContours[endIndicesOfContours.length - 1] + 1;
        }

        var flags = [];
        for (var j = 0; j < contourData['nCoords']; j++) {
          var flag = fontData.getUint8(glyphOffset);
          glyphOffset += 1;
          flags.add(flag);

          if ((flag & 0x08) == 0x08) {
            var times = fontData.getUint8(glyphOffset);
            glyphOffset += 1;
            for (var k = 0; k < times; k++) {
              flags.add(flag);
              j += 1;
            }
          }
        }

        contourData['points'] = [];
        for (var j = 0; j < flags.length; j++) {
          var flag = flags[j];
          var point = PMContourPoint();
          point.flag = flag;
          if ((flag & 0x01) == 0x01) {
            point.isOnCurve = true;
          } else {
            point.isOnCurve = false;
          }
          contourData['points'].add(point);
        }

        // load X coordinates
        var prevX = 0;
        for (var j = 0; j < contourData['points'].length; j++) {
          var point = contourData['points'][j];
          var curX = 0;
          if ((point.flag & 0x02) == 0x02) {
            curX = fontData.getUint8(glyphOffset);
            glyphOffset += 1;
            if ((point.flag & 0x10) == 0) {
              curX *= -1;
            }
            point.x = prevX + curX;
          } else {
            if ((point.flag & 0x10) == 0x10)
              point.x = prevX;
            else {
              point.x = prevX + fontData.getInt16(glyphOffset);
              glyphOffset += 2;
            }
          }
          prevX = point.x;
        }

        // load Y coordinates
        var prevY = 0;
        for (var j = 0; j < contourData['points'].length; j++) {
          var point = contourData['points'][j];
          var curY = 0;
          if ((point.flag & 0x04) == 0x04) {
            curY = fontData.getUint8(glyphOffset);
            glyphOffset += 1;
            if ((point.flag & 0x20) == 0) {
              curY *= -1;
            }
            point.y = prevY + curY;
          } else {
            if ((point.flag & 0x20) == 0x20)
              point.y = prevY;
            else {
              point.y = prevY + fontData.getInt16(glyphOffset);
              glyphOffset += 2;
            }
          }
          prevY = point.y;
        }
      }
    }
  }

  /// Reads the head table.
  void _readHead() {
    int startOffset = font.tables['head'].offset;
    var data = {
      'magicNumber': fontData.getUint32(startOffset + 12),
      'flags': fontData.getUint16(startOffset + 16),
      'unitsPerEm': fontData.getUint16(startOffset + 18),
      'indexToLocFormat': fontData.getUint16(startOffset + 50)
    };
    font.tables['head'].data = data;
  }

  /// Reads the maxp table to determine the number of glyphs present
  /// in the .ttf file.
  void _setNumGlyphs() {
    int startOffset = font.tables['maxp'].offset;
    font.numGlyphs = fontData.getUint16(startOffset + 4);
    font.tables['maxp'].data = {'numGlyphs': font.numGlyphs};
  }

  /// Reads the cmap table to map glyph IDs to character codes.
  void _getCharacterMappings() {
    int cmapOffset = font.tables['cmap'].offset;
    var data = {};
    font.tables['cmap'].data = data;

    data['version'] = fontData.getUint16(cmapOffset);
    var glyphIdToCharacterCodes = {};
    data['characterMap'] = glyphIdToCharacterCodes;
    cmapOffset += 2;

    var numTables = fontData.getUint16(cmapOffset);
    cmapOffset += 2;

    var offset = -1;
    for (var i = 0; i < numTables; i++) {
      var platformID = fontData.getUint16(cmapOffset);
      cmapOffset += 2;
      var encodingID = fontData.getUint16(cmapOffset);
      cmapOffset += 2;
      offset = fontData.getUint32(cmapOffset);
      cmapOffset += 4;
      if (platformID == 3 &&
          (encodingID == 1 || encodingID == 0 || encodingID == 10)) {
        _readFormat4Table(data, offset, glyphIdToCharacterCodes);
      }
    }

    if (offset == -1) {
      print("Font not supported.");
      return;
    }
  }

  /// Reads the Format4 subtable in the cmap table
  void _readFormat4Table(data, offset, glyphIdToCharacterCodes) {
    offset = offset + font.tables['cmap'].offset;

    int format = fontData.getUint16(offset);
    offset += 2;

    if (format != 4) {
      if (format == 12) {
        _readFormat12Table(data, offset, glyphIdToCharacterCodes);
        return;
      } else {
        print("Font not supported yet.");
        return;
      }
    }

    int length = fontData.getUint16(offset);
    offset += 2;
    int language = fontData.getUint16(offset);
    offset += 2;
    int nSegments = (fontData.getUint16(offset) / 2).round();
    offset += 2;
    int searchRange = fontData.getUint16(offset);
    offset += 2;
    int entrySelector = fontData.getUint16(offset);
    offset += 2;
    int rangeShift = fontData.getUint16(offset);
    offset += 2;

    var endCodes = <int>[];
    for (int i = 0; i < nSegments; i++) {
      endCodes.add(fontData.getUint16(offset));
      offset += 2;
    }
    int reservedPad = fontData.getUint16(offset);
    offset += 2;
    if (reservedPad != 0 && endCodes.last != 65535) {
      throw FormatException("Error in TTF");
    }

    var startCodes = <int>[];
    for (int i = 0; i < nSegments; i++) {
      startCodes.add(fontData.getUint16(offset));
      offset += 2;
    }

    var idDeltas = <int>[];
    for (int i = 0; i < nSegments; i++) {
      idDeltas.add(fontData.getInt16(offset));
      offset += 2;
    }

    var idRangeOffsets = <int>[];
    var idRangeOffsetAdresses = <int>[];
    for (int i = 0; i < nSegments; i++) {
      idRangeOffsets.add(fontData.getUint16(offset));
      idRangeOffsetAdresses.add(offset);
      offset += 2;
    }

    for (var i = 0; i < nSegments; i++) {
      int start = startCodes[i];
      int end = endCodes[i];
      int idDelta = idDeltas[i];
      int idRangeOffset = idRangeOffsets[i];
      int idRangeOffsetAdress = idRangeOffsetAdresses[i];
      int glyphIndex;
      for (int j = start; j <= end; j++) {
        if (idRangeOffset == 0) {
          glyphIndex = (j + idDelta) % 65536;
          glyphIdToCharacterCodes[glyphIndex] = j;
        } else {
          if (idRangeOffset == 0) {
            glyphIndex = (idDelta + j) % 65536;
          } else {
            int glyphIndexAddress =
                idRangeOffset + 2 * (j - start) + idRangeOffsetAdress;
            glyphIndex = fontData.getUint16(glyphIndexAddress);
          }
          glyphIdToCharacterCodes[glyphIndex] = j;
        }
      }
    }
  }

  /// Reads the Format12 subtable in the cmap table
  void _readFormat12Table(data, offset, glyphIdToCharacterCodes) {
    offset += 2; // Step over reserved

    // var subtableLength = fontData.getUint32(offset);
    offset += 4;

    offset += 4; // skip language

    var numGroups = fontData.getUint32(offset);
    offset += 4;

    for (var i = 0; i < numGroups; i++) {
      var startCode = fontData.getUint32(offset);
      offset += 4;
      var endCode = fontData.getUint32(offset);
      offset += 4;
      var startGlyphId = fontData.getUint32(offset);
      offset += 4;
      for (var j = startCode; j <= endCode; j++) {
        glyphIdToCharacterCodes[startGlyphId] = j;
        startGlyphId += 1;
      }
    }
  }
}
