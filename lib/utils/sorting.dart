int naturalCompare(String a, String b) {
  final numberRegex = RegExp(r'(\\d+)');

  final aMatch = numberRegex.firstMatch(a);
  final bMatch = numberRegex.firstMatch(b);

  if (aMatch != null && bMatch != null) {
    final prefixA = a.substring(0, aMatch.start);
    final prefixB = b.substring(0, bMatch.start);
    final numA = int.tryParse(aMatch.group(0)!) ?? 0;
    final numB = int.tryParse(bMatch.group(0)!) ?? 0;

    final prefixComparison = prefixA.compareTo(prefixB);
    if (prefixComparison != 0) return prefixComparison;

    return numA.compareTo(numB);
  }

  return a.compareTo(b);
}
