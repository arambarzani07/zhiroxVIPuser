class KurdishReshaper {
  static final Map<int, List<int>> _glpyhs = {
    // Standard Arabic
    0x0627: [0xFE8D, 0xFE8E, 0xFE8D, 0xFE8E], // Alef
    0x0628: [0xFE8F, 0xFE90, 0xFE91, 0xFE92], // Beh
    0x062A: [0xFE95, 0xFE96, 0xFE97, 0xFE98], // Teh
    0x062B: [0xFE99, 0xFE9A, 0xFE9B, 0xFE9C], // Theh
    0x062C: [0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0], // Jeem
    0x062D: [0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4], // Hah
    0x062E: [0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8], // Khah
    0x062F: [0xFEA9, 0xFEAA, 0xFEA9, 0xFEAA], // Dal
    0x0630: [0xFEAB, 0xFEAC, 0xFEAB, 0xFEAC], // Thal
    0x0631: [0xFEAD, 0xFEAE, 0xFEAD, 0xFEAE], // Reh
    0x0632: [0xFEAF, 0xFEB0, 0xFEAF, 0xFEB0], // Zain
    0x0633: [0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4], // Seen
    0x0634: [0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8], // Sheen
    0x0635: [0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC], // Sad
    0x0636: [0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0], // Dad
    0x0637: [0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4], // Tah
    0x0638: [0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8], // Zah
    0x0639: [0xFEC9, 0xFECA, 0xFECB, 0xFECC], // Ain
    0x063A: [0xFECD, 0xFECE, 0xFECF, 0xFED0], // Ghain
    0x0641: [0xFED1, 0xFED2, 0xFED3, 0xFED4], // Feh
    0x0642: [0xFED5, 0xFED6, 0xFED7, 0xFED8], // Qaf
    0x0643: [0xFED9, 0xFEDA, 0xFEDB, 0xFEDC], // Kaf
    0x0644: [0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0], // Lam
    0x0645: [0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4], // Meem
    0x0646: [0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8], // Noon
    0x0647: [0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC], // Heh
    0x0648: [0xFEED, 0xFEEE, 0xFEED, 0xFEEE], // Waw
    0x0649: [0xFEEF, 0xFEF0, 0xFEEF, 0xFEF0], // Alef Maksura (YAA ending)
    0x064A: [0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4], // Yeh
    // Kurdish / Persian Specifics
    0x067E: [0xFB56, 0xFB57, 0xFB58, 0xFB59], // Peh
    0x0686: [0xFB7A, 0xFB7B, 0xFB7C, 0xFB7D], // Tcheh (Che)
    0x0698: [0xFB8A, 0xFB8B, 0xFB8A, 0xFB8B], // Jeh (Zhai)
    0x06AF: [0xFB92, 0xFB93, 0xFB94, 0xFB95], // Gaf
    0x06CC: [0xFBFC, 0xFBFD, 0xFBFE, 0xFBFF], // Farsi B. Yeh
    // Yeh with Small V (Ê) - NO standard forms. We handle manually in loop.
    // 0x06CE: ...
  };

  static final Set<int> _rightJoining = {
    0x0627, 0x0623, 0x0625, 0x0622, // Alefs
    0x062F, 0x0630, // Dal, Thal
    0x0631, 0x0632, // Reh, Zain
    0x0648, // Waw
    0x0698, // Jeh
    0x0695, // Reh + V
    0x06C6, // Waw + V
    0x06A4, // Veh
    0x0676, 0x0677, 0x06C7, 0x06C4, 0x06C5, // Other Waws/Rehs
    0x0624, // Waw with Hamza
  };

  static String convert(String text) {
    if (text.isEmpty) return "";
    List<int> chars = text.codeUnits;
    List<int> result = [];

    for (int i = 0; i < chars.length; i++) {
      int current = chars[i];
      int baseChar = current;
      bool appendV = false;

      // Special Handling for Kurdish Chars without Presentation Forms
      // ێ (06CE) -> Base: Farsi Yeh (06CC) + Small V (065A)
      if (current == 0x06CE) {
        baseChar = 0x06CC; // Farsi Yeh
        appendV = true;
      }
      // ڵ (06B5) -> Base: Lam (0644) + Small V (065A)
      else if (current == 0x06B5) {
        baseChar = 0x0644; // Lam
        appendV = true;
      }

      // Skip non-Arabic chars (or keep as is)
      if (baseChar < 0x0600 || baseChar > 0x06FF) {
        result.add(current);
        continue;
      }

      // Determine joining type using original `chars` context to maintain correct connectivity
      // Check previous char (i-1) in original string
      bool prevJoins = i > 0 && _joinsRight(chars[i - 1]);
      // Check next char (i+1) in original string
      bool nextJoins = i < chars.length - 1 && _joinsLeft(chars[i + 1]);

      int form = 0; // 0: Isolated, 1: Final, 2: Initial, 3: Medial

      if (prevJoins && nextJoins) {
        form = 3; // Medial
      } else if (prevJoins) {
        form = 1; // Final
      } else if (nextJoins) {
        form = 2; // Initial
      } else {
        form = 0; // Isolated
      }

      // Get Presentation Form of Base Char
      if (_glpyhs.containsKey(baseChar) && _glpyhs[baseChar] != null) {
        result.add(_glpyhs[baseChar]![form]);
      } else {
        result.add(baseChar);
      }

      // Append Small V if needed
      if (appendV) {
        result.add(0x065A);
      }
    }

    return String.fromCharCodes(result);
  }

  static bool _joinsRight(int c) {
    // Current char accepts connection from Right?
    // All Arabic letters join Right, except maybe specials?
    // Actually all letters we care about join right.
    // Non-joining chars: Spaces, etc.
    if (c < 0x0600 || c > 0x06FF) return false;
    return true;
  }

  static bool _joinsLeft(int c) {
    // Current char accepts connection to Left? (i.e. is it Dual Joining?)
    if (c < 0x0600 || c > 0x06FF) return false;
    // If it's in the Right-Joining set, it does NOT join left.
    if (_rightJoining.contains(c)) return false;
    return true;
  }
}
