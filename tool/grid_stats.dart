// Measures word counts, points, and dead letters on random boards, then the
// cost of dealing boards with the filter in lib/logic/grid_rules.dart.
// Run: dart run tool/grid_stats.dart [boardsPerSetting] [outDir]
import 'dart:io';
import 'dart:math';

import 'package:michis_word_game/logic/dice.dart';
import 'package:michis_word_game/logic/models.dart' show wordPoints;
import 'package:michis_word_game/logic/solver.dart';
import 'package:michis_word_game/logic/word_list.dart';

class Dist {
  Dist(List<num> xs) : v = List.of(xs)..sort();
  final List<num> v;
  num pct(double p) => v[(p * (v.length - 1)).round()];
  double get mean => v.fold<num>(0, (a, b) => a + b) / v.length;
  double get sd {
    final m = mean;
    return sqrt(v.fold<double>(0, (a, b) => a + (b - m) * (b - m)) / v.length);
  }
}

void main(List<String> args) {
  final n = args.isEmpty ? 2000 : int.parse(args[0]);
  final out = args.length > 1 ? args[1] : '.';
  final dict = dictionaryFromAssets(
    File('assets/dict/words.txt.gz').readAsBytesSync(),
    File('assets/dict/blocklist.txt').readAsStringSync(),
  );
  final rng = Random(42);
  final csv = StringBuffer(
      'grid,min_len,boards,words_mean,words_sd,words_median,words_min,words_p5,words_p10,words_p25,words_p75,words_p90,words_max,'
      'points_mean,points_sd,points_median,points_min,points_p5,points_p10,points_p25,'
      'pct_dead_letter,pct_dead_letter_2plus,ms_per_solve,chosen_min,pct_pass_filter,avg_rolls,max_rolls,pct_capped,avg_gen_ms,worst_gen_ms,dealt_words_median,dealt_words_min\n');
  for (final size in [4, 5, 6]) {
    for (final minLen in [3, 4, 5]) {
      final counts = <int>[], points = <int>[];
      var dead = 0, dead2 = 0, pass = 0;
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        final a = analyzeBoard(rollBoard(size, rng), dict, minWordLength: minLen);
        counts.add(a.wordCount);
        points.add(a.words.keys.fold(0, (s, w) => s + wordPoints(w)));
        if (a.deadTiles.isNotEmpty) dead++;
        if (a.deadTiles.length >= 2) dead2++;
        if (isGoodBoard(a, size, minLen)) pass++;
      }
      final solveMs = sw.elapsedMicroseconds / n / 1000;
      var rolls = 0, maxRolls = 0, capped = 0;
      final dealt = <int>[];
      final sw2 = Stopwatch()..start();
      var worst = 0.0;
      for (var i = 0; i < n; i++) {
        final t0 = sw2.elapsedMicroseconds;
        var t = 0;
        final b = generateGoodBoard(
            size: size, minWordLength: minLen, dictionary: dict, random: rng, onDone: (x) => t = x);
        worst = max(worst, (sw2.elapsedMicroseconds - t0) / 1000);
        rolls += t;
        maxRolls = max(maxRolls, t);
        if (t >= maxBoardRolls) capped++;
        dealt.add(solveBoard(b, dict, minWordLength: minLen).length);
      }
      final genMs = sw2.elapsedMicroseconds / n / 1000;
      final w = Dist(counts), p = Dist(points), d = Dist(dealt);
      String f(num x) => x is int ? '$x' : x.toStringAsFixed(1);
      final cells = [
        '${size}x$size', '$minLen', '$n',
        f(w.mean), f(w.sd), f(w.pct(.5)), f(w.v.first), f(w.pct(.05)), f(w.pct(.10)), f(w.pct(.25)), f(w.pct(.75)), f(w.pct(.90)), f(w.v.last),
        f(p.mean), f(p.sd), f(p.pct(.5)), f(p.v.first), f(p.pct(.05)), f(p.pct(.10)), f(p.pct(.25)),
        f(100 * dead / n), f(100 * dead2 / n), solveMs.toStringAsFixed(2), '${minWordsFor(size, minLen)}',
        f(100 * pass / n), (rolls / n).toStringAsFixed(1), '$maxRolls', f(100 * capped / n),
        genMs.toStringAsFixed(1), worst.toStringAsFixed(1), f(d.pct(.5)), f(d.v.first),
      ];
      csv.writeln(cells.join(','));
      stdout.writeln(cells.join(' | '));
    }
  }
  File('$out/grid_stats.csv').writeAsStringSync(csv.toString());
  stdout.writeln('wrote $out/grid_stats.csv');
}
