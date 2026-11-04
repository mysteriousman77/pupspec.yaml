import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

const api =
    'https://script.google.com/macros/s/AKfycbycxushyypYFF1FptMeQYXRcldkioUTsHXg6-l69LamTBvK_BPjP5w5NHa8XK3_Cuc/exec';
const tmdbKey = '9f660b069ce86b86c8b671b14338d3b2';

/* ===================== TEMA ===================== */
class Th {
  final String id, name;
  final Color ac, bg, card, g2, g3;
  final bool light, glow;
  const Th(this.id, this.name, this.ac, this.bg, this.card, this.g2, this.g3,
      {this.light = false, this.glow = true});
}

const themes = <Th>[
  Th('crimson', 'Merah', Color(0xFFFF2D46), Color(0xFF07070B),
      Color(0xFF16161B), Color(0xFF7846FF), Color(0xFF0096FF)),
  Th('teal', 'Teal', Color(0xFF19D3C5), Color(0xFF06090B), Color(0xFF0F1618),
      Color(0xFF2864FF), Color(0xFF00C88C)),
  Th('violet', 'Ungu', Color(0xFFA78BFA), Color(0xFF08070D),
      Color(0xFF15121D), Color(0xFFFF50AA), Color(0xFF3C78FF)),
  Th('blue', 'Biru', Color(0xFF38A3FF), Color(0xFF060A10), Color(0xFF0F1620),
      Color(0xFF785AFF), Color(0xFF00D2C8)),
  Th('green', 'Hijau', Color(0xFF34D399), Color(0xFF060B09),
      Color(0xFF0F1714), Color(0xFF00AAFF), Color(0xFFC8E63C)),
  Th('orange', 'Oranye', Color(0xFFFF8A3D), Color(0xFF0C0807),
      Color(0xFF1B1411), Color(0xFFFF3C5A), Color(0xFFFFC800)),
  Th('pink', 'Pink', Color(0xFFFF5FA2), Color(0xFF0D0710), Color(0xFF1C1320),
      Color(0xFFAA50FF), Color(0xFF50A0FF)),
  Th('amoled', 'AMOLED', Color(0xFFFF2D46), Color(0xFF000000),
      Color(0xFF0E0E0E), Color(0xFF000000), Color(0xFF000000),
      glow: false),
  Th('light', 'Terang', Color(0xFFE11D48), Color(0xFFF3F4F8),
      Color(0xFFFFFFFF), Color(0xFF7846FF), Color(0xFF0096FF),
      light: true),
];

Th curTh = themes[0];
final themeId = ValueNotifier<String>('crimson');

Color get accent => curTh.ac;
Color get bgc => curTh.bg;
Color get cardc => curTh.card;
bool get isLight => curTh.light;
Color get fg => isLight ? const Color(0xFF14151A) : Colors.white;
Color get mut => isLight ? const Color(0xFF5B5E6B) : Colors.white60;
Color get lineC => isLight ? Colors.black12 : Colors.white12;
Color get onAc => accent.computeLuminance() > .45 ? Colors.black : Colors.white;

void setTheme(String id) {
  curTh = themes.firstWhere((t) => t.id == id, orElse: () => themes[0]);
  Store.p.setString('theme', curTh.id);
  themeId.value = curTh.id;
}

ThemeData buildTheme() {
  final b = isLight ? Brightness.light : Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: bgc,
    colorScheme: ColorScheme(
      brightness: b,
      primary: accent,
      onPrimary: onAc,
      secondary: accent,
      onSecondary: onAc,
      error: const Color(0xFFE5484D),
      onError: Colors.white,
      surface: cardc,
      onSurface: fg,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor:
          isLight ? Colors.white : Color.lerp(bgc, Colors.black, .35),
      indicatorColor: accent.withOpacity(.25),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? accent : mut)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected) ? accent : mut)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent.withOpacity(.6)))),
    textButtonTheme:
        TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: accent)),
  );
}

/* ===================== UTIL ===================== */
String s(dynamic v) => v == null ? '' : v.toString().trim();
String cut(String v, int n) => v.length > n ? v.substring(0, n) : v;
double numOf(String e) =>
    double.tryParse(e.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

/// hash judul, sama persis dengan versi web (supaya statistik tetap nyambung)
String tkey(String t) {
  final x = t.toLowerCase().trim();
  int h = 5381;
  for (final c in x.codeUnits) {
    h = ((h << 5) + h + c) & 0xFFFFFFFF;
  }
  return 't${h.toRadixString(36)}';
}

String kind(String c) {
  if (RegExp('movie|film').hasMatch(c)) return 'movie';
  if (c.contains('donghua')) return 'donghua';
  if (RegExp('drama|drakor').hasMatch(c)) return 'drama';
  return 'anime';
}

String fv(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '')} jt'
    : n >= 1000
        ? '${(n / 1000).toStringAsFixed(1).replaceAll('.0', '')} rb'
        : '$n';

String fmtDur(int sec) {
  final t = (sec / 60).round();
  final h = t ~/ 60, m = t % 60;
  return h > 0 ? '$h jam $m mnt' : '$m mnt';
}

Future<void> openUrl(String u) async {
  try {
    await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(m),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating));
}

/* ----- judul dasar, season, kemiripan ----- */
final _noise = RegExp(
    r'\b(sub(title)?\s*indo(nesia)?|batch|complete|tamat|ongoing|season|musim|part|cour|bagian|final|the movie|ova|oad|special)\b');
String baseTitle(String t) {
  var x = t.toLowerCase();
  x = x
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
      .replaceAll(_noise, ' ')
      .replaceAll(RegExp(r'\b\d+(st|nd|rd|th)\b'), ' ')
      .replaceAll(RegExp(r'\bs\d+\b'), ' ');
  x = x
      .replaceAll(RegExp(r'[^\p{L}\p{N} ]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  x = x.replaceAll(RegExp(r'(\s(ii|iii|iv|vi|vii|viii|ix))+$'), '');
  while (RegExp(r'\s\d+$').hasMatch(x)) {
    x = x.replaceAll(RegExp(r'\s\d+$'), '');
  }
  return x.isEmpty ? t.toLowerCase().trim() : x;
}

int seasonNo(String t) {
  final m = RegExp(
          r'season\s*(\d+)|\bs(\d+)\b|(\d+)(?:st|nd|rd|th)\s*season|part\s*(\d+)|\s(\d+)\s*(?:\([^)]*\))?\s*$')
      .firstMatch(t.toLowerCase());
  if (m == null) return 1;
  for (var i = 1; i <= 5; i++) {
    final g = m.group(i);
    if (g != null) return int.tryParse(g) ?? 1;
  }
  return 1;
}

String cmpT(String x) => x.replaceAll(' ', '');
bool relB(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b || (cmpT(a) == cmpT(b) && cmpT(a).length >= 4)) return true;
  final sh = a.length <= b.length ? a : b;
  final lg = a.length <= b.length ? b : a;
  return sh.length >= 6 && lg.startsWith('$sh ');
}

int lev(String a, String b) {
  final m = a.length, n = b.length;
  if (m == 0) return n;
  if (n == 0) return m;
  var p = List<int>.generate(n + 1, (j) => j);
  for (var i = 1; i <= m; i++) {
    final c = <int>[i];
    for (var j = 1; j <= n; j++) {
      c.add(min(min(p[j] + 1, c[j - 1] + 1),
          p[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)));
    }
    p = c;
  }
  return p[n];
}

double simT(String a, String b) {
  a = cmpT(a);
  b = cmpT(b);
  final l = max(a.length, b.length);
  return l == 0 ? 0 : 1 - lev(a, b) / l;
}

/* ===================== LEVEL KULTIVASI ===================== */
class Realm {
  final String name, emoji;
  final Color c;
  const Realm(this.name, this.emoji, this.c);
}

const rlb = [
  Realm('Dou Zhe', '🥋', Color(0xFF9CA3AF)),
  Realm('Dou Shi', '🔥', Color(0xFFFB923C)),
  Realm('Da Dou Shi', '🌋', Color(0xFFF97316)),
  Realm('Dou Ling', '👻', Color(0xFFA78BFA)),
  Realm('Dou Wang', '👑', Color(0xFFFACC15)),
  Realm('Dou Huang', '🐲', Color(0xFFF43F5E)),
  Realm('Dou Zong', '🌀', Color(0xFF38BDF8)),
  Realm('Dou Zun', '⚡', Color(0xFF34D399)),
  Realm('Dou Sheng', '🌟', Color(0xFFE879F9)),
  Realm('Dou Di', '🏯', Color(0xFFFDE047)),
];
const rlt = [
  0, 15, 25, 45, 65, 90, 120, 155, 200, 250, 310, 390, 485, 600, 735, 900,
  1090, 1320, 1605, 1950, 2360, 2860, 3465, 4205, 5115, 6195, 7495, 9100
];
const rlMax = 13000;

class Stage {
  final String name, emoji;
  final Color c;
  final int h, r;
  const Stage(this.name, this.emoji, this.c, this.h, this.r);
}

final List<Stage> rlm = () {
  final l = <Stage>[Stage(rlb[0].name, rlb[0].emoji, rlb[0].c, rlt[0], 0)];
  for (var k = 1; k < rlb.length; k++) {
    final b = rlb[k];
    final t = 1 + (k - 1) * 3;
    l.add(Stage('Ban Bu ${b.name}', b.emoji, b.c, rlt[t], k));
    l.add(Stage(b.name, b.emoji, b.c, rlt[t + 1], k));
    l.add(Stage('Puncak ${b.name}', b.emoji, b.c, rlt[t + 2], k));
  }
  return l;
}();

class LvInfo {
  final int r, st, idx, left;
  final double p, h;
  final bool max, top;
  const LvInfo(this.r, this.st, this.idx, this.left, this.p, this.h, this.max,
      this.top);
}

LvInfo lvInfo(double sec) {
  final h = sec / 3600;
  var r = rlm.length - 1;
  while (r > 0 && h < rlm[r].h) {
    r--;
  }
  final lo = rlm[r].h.toDouble();
  final hi = r < rlm.length - 1 ? rlm[r + 1].h.toDouble() : rlMax.toDouble();
  final span = (hi - lo) / 9;
  final mx = h >= hi;
  var i = ((h - lo) / span).floor();
  if (i > 8) i = 8;
  if (i < 0) i = 0;
  final p = mx ? 1.0 : (((h - lo) - i * span) / span).clamp(0.0, 1.0);
  final left = mx ? 0 : ((lo + (i + 1) * span - h) * 3600).ceil();
  return LvInfo(r, i + 1, r * 9 + i, left < 0 ? 0 : left, p, h, mx,
      r == rlm.length - 1);
}

/* ===================== MODEL ===================== */
class Srv {
  final String name, url;
  final bool hls;
  const Srv(this.name, this.url, this.hls);
}

class Ep {
  final int id;
  final String? rid, direct;
  final String cat, title, eps, key, thumb, syn, gen, svn;
  final bool tipeHls;
  final List<Srv> extra;
  Ep({
    required this.id,
    required this.rid,
    required this.direct,
    required this.cat,
    required this.title,
    required this.eps,
    required this.key,
    required this.thumb,
    required this.syn,
    required this.gen,
    required this.svn,
    required this.tipeHls,
    required this.extra,
  });
}

class Group {
  final String title, cat;
  final int gi;
  String thumb = '', syn = '', gen = '';
  int lastId = 0;
  final List<Ep> eps = [];
  late final String base = baseTitle(title);
  Group(this.title, this.cat, this.gi);
}

/* ===================== DATA ===================== */
const tg = {
  28: 'Aksi',
  12: 'Petualangan',
  16: 'Animasi',
  35: 'Komedi',
  80: 'Kejahatan',
  99: 'Dokumenter',
  18: 'Drama',
  10751: 'Keluarga',
  14: 'Fantasi',
  36: 'Sejarah',
  27: 'Horor',
  10402: 'Musik',
  9648: 'Misteri',
  10749: 'Romantis',
  878: 'Fiksi Ilmiah',
  53: 'Thriller',
  10752: 'Perang',
  37: 'Western',
};

class Recs {
  final List<Group> rel, more;
  Recs(this.rel, this.more);
}

class App {
  static List<Ep> eps = [];
  static List<Group> groups = [];
  static Map<String, Group> gm = {};
  static Map<String, Ep> byKey = {};
  static Map<String, int> vc = {}, wk = {};
  static Map<String, List<int>> rt = {};
  static Map<String, String>? popup;
  static bool loaded = false, started = false, popDone = false;
  static String? error;
  static final refresh = ValueNotifier<int>(0);
  static final tab = ValueNotifier<int>(0);
  static final catReq = ValueNotifier<String>('');
  static final _recCache = <String, Recs>{};
  static final metaBusy = <String>{}, metaErr = <String>{};

  static void ingest(List raw) {
    final out = <Ep>[];
    Map<String, String>? pp;
    for (final it in raw) {
      if (it is! Map) continue;
      if (pp == null) {
        final u = s(it['popup']);
        if (RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) {
          final md = s(it['popup_tampil']).toLowerCase();
          pp = {
            'img': u,
            'link': s(it['popup_link']),
            'mode': md.isEmpty ? 'sekali' : md
          };
        }
      }
      final src = s(it['src']), rid = s(it['id']);
      if (src.isEmpty && rid.isEmpty) continue;
      final epr = s(it['eps']);
      final eps =
          (epr.isNotEmpty && double.tryParse(epr) != null) ? 'Eps $epr' : epr;
      final extra = <Srv>[];
      for (var n = 2; n <= 8; n++) {
        final u = s(it['src$n']);
        if (u.isEmpty) continue;
        final t = s(it['tipe$n']).toLowerCase();
        final nm = s(it['nama$n']);
        extra.add(Srv(
            nm.isEmpty ? 'Server $n' : nm,
            u,
            t == 'hls' ||
                t == 'm3u8' ||
                (t != 'embed' && t != 'iframe' && u.contains('.m3u8'))));
      }
      final tp = [s(it['tipe']), s(it['type']), s(it['format'])]
          .firstWhere((x) => x.isNotEmpty, orElse: () => '')
          .toLowerCase();
      out.add(Ep(
        id: out.length,
        rid: rid.isEmpty ? null : rid,
        direct: src.isEmpty ? null : src,
        cat: (s(it['kategori']).isEmpty ? 'anime' : s(it['kategori']))
            .toLowerCase(),
        title: s(it['judul']),
        eps: eps,
        key: rid.isNotEmpty ? 'id:$rid' : src,
        thumb: s(it['thumb']),
        syn: cut(
            s(it['sinopsis']).isNotEmpty ? s(it['sinopsis']) : s(it['synopsis']),
            2000),
        gen: cut(
            s(it['genre']).isNotEmpty ? s(it['genre']) : s(it['genres']), 200),
        svn: s(it['nama1']),
        tipeHls: tp == 'hls' || tp == 'm3u8',
        extra: extra,
      ));
    }
    final gm2 = <String, Group>{};
    final gl = <Group>[];
    for (final e in out) {
      var g = gm2[e.title];
      if (g == null) {
        g = Group(e.title, e.cat, gl.length);
        gm2[e.title] = g;
        gl.add(g);
      }
      if (g.thumb.isEmpty) g.thumb = e.thumb;
      if (g.syn.isEmpty) g.syn = e.syn;
      if (g.gen.isEmpty) g.gen = e.gen;
      if (e.id > g.lastId) g.lastId = e.id;
      g.eps.add(e);
    }
    for (final g in gl) {
      g.eps.sort((a, b) {
        final c = numOf(a.eps).compareTo(numOf(b.eps));
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    }
    eps = out;
    groups = gl;
    gm = gm2;
    byKey = {for (final e in out) e.key: e};
    popup = pp;
    _recCache.clear();
  }

  static Future<void> load() async {
    error = null;
    final c = Store.p.getString('cache');
    if (c != null && !loaded) {
      try {
        ingest(jsonDecode(c) as List);
        loaded = true;
        refresh.value++;
      } catch (_) {}
    }
    try {
      final r =
          await http.get(Uri.parse(api)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw 'x';
      final body = utf8.decode(r.bodyBytes);
      final d = jsonDecode(body);
      if (d is! List) throw 'x';
      ingest(d);
      loaded = true;
      Store.p.setString('cache', body);
    } catch (_) {
      if (!loaded) error = 'Gagal mengambil data. Periksa koneksi lalu coba lagi.';
    }
    refresh.value++;
    loadStats();
  }

  static Map<String, int> _ints(Map m) => {
        for (final e in m.entries)
          e.key.toString(): (e.value is num) ? (e.value as num).toInt() : 0
      };

  static Future<void> loadStats() async {
    try {
      final r = await http
          .get(Uri.parse('$api?stats=1'))
          .timeout(const Duration(seconds: 20));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map && d['v'] is Map) {
        vc = _ints(d['v'] as Map);
        wk = d['w'] is Map ? _ints(d['w'] as Map) : {};
        if (d['r'] is Map) {
          final m = <String, List<int>>{};
          (d['r'] as Map).forEach((k, v) {
            if (v is List && v.length >= 2) {
              m[k.toString()] = [
                (v[0] is num) ? (v[0] as num).toInt() : 0,
                (v[1] is num) ? (v[1] as num).toInt() : 0
              ];
            }
          });
          rt = m;
        }
        refresh.value++;
      }
    } catch (_) {}
  }

  static int views(String t) => vc[tkey(t)] ?? 0;

  static Future<String> resolveUrl(Ep e, int sv) async {
    if (sv > 0) return e.extra[sv - 1].url;
    if (e.direct != null) return e.direct!;
    final r = await http
        .get(Uri.parse('$api?id=${Uri.encodeComponent(e.rid!)}'))
        .timeout(const Duration(seconds: 15));
    final d = jsonDecode(utf8.decode(r.bodyBytes));
    final u = s(d is Map ? d['src'] : '');
    if (u.isEmpty) throw 'kosong';
    return u;
  }

  static void regView(String title) {
    final k = tkey(title);
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = Store.p.getInt('vw_$k') ?? 0;
    if (now - last < 1800000) return;
    Store.p.setInt('vw_$k', now);
    unawaited(http
        .get(Uri.parse('$api?view=${Uri.encodeComponent(k)}'))
        .then((_) {}, onError: (_) {}));
  }

  /* ----- suka / tidak suka ----- */
  static Future<void> vote(String title, String dir) async {
    final k = tkey(title);
    final m0 = Store.jm('votes');
    final m = Map<String, dynamic>.from(m0);
    final prev = (m0[k] as String?) ?? 'none';
    final nv = prev == dir ? 'none' : dir;
    final old = List<int>.from(rt[k] ?? [0, 0]);
    final cur = List<int>.from(old);
    if (prev == 'up') cur[0] = max(0, cur[0] - 1);
    if (prev == 'down') cur[1] = max(0, cur[1] - 1);
    if (nv == 'up') cur[0]++;
    if (nv == 'down') cur[1]++;
    rt[k] = cur;
    if (nv == 'none') {
      m.remove(k);
    } else {
      m[k] = nv;
    }
    Store.sj('votes', m);
    refresh.value++;
    try {
      final r = await http
          .get(Uri.parse('$api?vote=${Uri.encodeComponent(k)}&v=$nv&prev=$prev'))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map && d['ok'] == 1 && d['u'] is num && d['d'] is num) {
        rt[k] = [(d['u'] as num).toInt(), (d['d'] as num).toInt()];
      } else {
        throw 'x';
      }
    } catch (_) {
      rt[k] = old;
      Store.sj('votes', m0);
    }
    refresh.value++;
  }

  /// 1 = terkirim, 2 = sudah pernah, 0 = gagal
  static Future<int> report(Ep e, String reason, String note) async {
    final key = tkey('${e.title}|${e.eps}');
    final R = Store.jm('rep');
    final n = DateTime.now().millisecondsSinceEpoch;
    R.removeWhere((k, v) => v is! num || n - v > 86400000);
    if (R.containsKey(key)) return 2;
    final q =
        '?report=1&t=${Uri.encodeComponent(cut(e.title, 100))}&e=${Uri.encodeComponent(cut(e.eps, 40))}&r=${Uri.encodeComponent(reason)}&n=${Uri.encodeComponent(cut(note.trim(), 160))}';
    try {
      final r = await http.get(Uri.parse(api + q)).timeout(const Duration(seconds: 15));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map && d['ok'] == 1) {
        R[key] = n;
        Store.sj('rep', R);
        return 1;
      }
    } catch (_) {}
    return 0;
  }

  /* ----- rekomendasi: season/seri sama dulu ----- */
  static Recs recsFor(Group g) {
    final c = _recCache[g.title];
    if (c != null) return c;
    final rel = groups
        .where((x) => x.title != g.title && relB(g.base, x.base))
        .toList()
      ..sort((a, b) {
        final c = seasonNo(a.title).compareTo(seasonNo(b.title));
        return c != 0 ? c : a.title.compareTo(b.title);
      });
    final ids = rel.map((x) => x.title).toSet()..add(g.title);
    final pool =
        groups.where((x) => !ids.contains(x.title) && x.thumb.isNotEmpty).toList();
    final rnd = Random();
    final same = pool.where((x) => kind(x.cat) == kind(g.cat)).toList()
      ..shuffle(rnd);
    final other = pool.where((x) => kind(x.cat) != kind(g.cat)).toList()
      ..shuffle(rnd);
    return _recCache[g.title] =
        Recs(rel.take(12).toList(), [...same, ...other].take(12).toList());
  }

  /* ----- sinopsis & genre film dari TMDB ----- */
  static Map<String, dynamic> metaOf(String title) {
    final v = Store.jm('meta')[title];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  static String _unesc(String t) => t
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  static Future<String> trId(String t) async {
    final parts = RegExp(r'[^.!?]+[.!?]*\s*')
        .allMatches(t)
        .map((m) => m.group(0)!)
        .toList();
    final ch = <String>[];
    var c = '';
    for (final x in parts) {
      if (c.isNotEmpty && (c + x).length > 400) {
        ch.add(c);
        c = x;
      } else {
        c += x;
      }
    }
    if (c.isNotEmpty) ch.add(c);
    final q = <String>[];
    for (var x in ch) {
      while (x.length > 450) {
        q.add(x.substring(0, 450));
        x = x.substring(450);
      }
      q.add(x);
    }
    final out = <String>[];
    for (final x in q) {
      final r = await http
          .get(Uri.parse(
              'https://api.mymemory.translated.net/get?langpair=en|id&q=${Uri.encodeComponent(x.trim())}'))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      final tt = d is Map && d['responseData'] is Map
          ? s(d['responseData']['translatedText'])
          : '';
      if (d is! Map ||
          '${d['responseStatus']}' != '200' ||
          tt.isEmpty ||
          tt.contains('MYMEMORY WARNING')) {
        throw 'x';
      }
      out.add(_unesc(tt));
    }
    return out.join(' ').trim();
  }

  static Future<void> metaFetch(Group g) async {
    if (kind(g.cat) != 'movie' || metaBusy.contains(g.title)) return;
    final c = metaOf(g.title);
    final ts = (c['ts'] as num?)?.toInt() ?? 0;
    final ttl = (s(c['s']).isNotEmpty ? 30 : 1) * 86400000;
    if (c.isNotEmpty && DateTime.now().millisecondsSinceEpoch - ts < ttl) return;
    metaBusy.add(g.title);
    try {
      final b = g.base;
      final r = await http
          .get(Uri.parse(
              'https://api.themoviedb.org/3/search/movie?api_key=$tmdbKey&language=id-ID&query=${Uri.encodeComponent(b)}'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw 'x';
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      Map? best;
      var bs = 0.0;
      final results =
          (d is Map && d['results'] is List) ? d['results'] as List : <dynamic>[];
      for (final x in results) {
        if (x is! Map) continue;
        final names = [s(x['title']), s(x['original_title'])]
            .where((n) => n.isNotEmpty)
            .map(baseTitle);
        var sc = 0.0;
        for (final n in names) {
          final v = cmpT(n) == cmpT(b) ? 1.0 : (relB(b, n) ? .9 : simT(b, n));
          if (v > sc) sc = v;
        }
        if (sc > bs) {
          bs = sc;
          best = x;
        }
      }
      final o = <String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch,
        's': '',
        'g': <String>[],
        'r': 0.0,
        'src': 'TMDB'
      };
      if (best != null && bs >= .82) {
        final vcnt = (best['vote_count'] as num?)?.toInt() ?? 0;
        final va = (best['vote_average'] as num?)?.toDouble() ?? 0.0;
        o['r'] = (vcnt > 0 && va > 0) ? (va * 10).round() / 10 : 0.0;
        o['s'] = s(best['overview']);
        o['g'] = ((best['genre_ids'] as List?) ?? [])
            .map((i) => tg[i])
            .whereType<String>()
            .take(6)
            .toList();
        if (s(o['s']).isEmpty && g.syn.isEmpty) {
          try {
            final r2 = await http
                .get(Uri.parse(
                    'https://api.themoviedb.org/3/movie/${best['id']}?api_key=$tmdbKey&language=en-US'))
                .timeout(const Duration(seconds: 15));
            final m = jsonDecode(utf8.decode(r2.bodyBytes));
            final en = cut(s(m is Map ? m['overview'] : ''), 1200);
            if (en.isNotEmpty) {
              try {
                o['s'] = await trId(en);
                o['src'] = 'TMDB, diterjemahkan otomatis';
              } catch (_) {
                o['s'] = en;
                o['src'] = 'TMDB (bahasa Inggris)';
              }
            }
          } catch (_) {
            o['ts'] = DateTime.now().millisecondsSinceEpoch - 29 * 86400000;
          }
        }
      }
      final m = Store.jm('meta');
      m[g.title] = o;
      if (m.length > 300) {
        final ks = m.keys.toList()
          ..sort((a, b) => ((m[a]['ts'] as num?) ?? 0).compareTo((m[b]['ts'] as num?) ?? 0));
        for (final k in ks.take(m.length - 300)) {
          m.remove(k);
        }
      }
      Store.sj('meta', m);
    } catch (_) {
      metaErr.add(g.title);
    }
    metaBusy.remove(g.title);
    refresh.value++;
  }
}

/* ===================== PENYIMPANAN LOKAL ===================== */
class Store {
  static late SharedPreferences p;
  static Future<void> init() async {
    p = await SharedPreferences.getInstance();
  }

  static Map<String, dynamic> jm(String k) {
    try {
      return Map<String, dynamic>.from(jsonDecode(p.getString(k) ?? '{}'));
    } catch (_) {
      return {};
    }
  }

  static void sj(String k, Object v) => p.setString(k, jsonEncode(v));

  static List<String> get bms => List<String>.from(p.getStringList('bms') ?? []);
  static bool isBm(String t) => bms.contains(t);
  static void toggleBm(String t) {
    final l = bms;
    if (!l.remove(t)) l.add(t);
    p.setStringList('bms', l);
    App.refresh.value++;
  }

  static double posOf(String key) {
    final v = jm('pos')[key];
    if (v is Map) return (v['t'] as num?)?.toDouble() ?? 0.0;
    return 0.0;
  }

  static double progOf(String key) {
    final v = jm('pos')[key];
    if (v is Map) {
      final t = (v['t'] as num?)?.toDouble() ?? 0.0;
      final d = (v['d'] as num?)?.toDouble() ?? 0.0;
      return d > 0 ? (t / d).clamp(0.0, 1.0) : 0.0;
    }
    return 0.0;
  }

  static bool seen(String key) => jm('seen').containsKey(key);
  static void markSeen(String key) {
    final m = jm('seen');
    if (m.containsKey(key)) return;
    m[key] = 1;
    sj('seen', m);
  }

  static List<Map<String, dynamic>> get hist {
    try {
      return (jsonDecode(p.getString('hist') ?? '[]') as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void touchHist(Ep e) {
    final l = hist;
    l.removeWhere((h) => h['title'] == e.title);
    l.insert(0, {'title': e.title, 'key': e.key});
    sj('hist', l.take(20).toList());
    App.refresh.value++;
  }

  static void savePos(Ep e, double t, double d) {
    if (d <= 0 || t < 10) return;
    final pos = jm('pos');
    if (t / d > .9) markSeen(e.key);
    if (t / d > .95) {
      pos.remove(e.key);
      sj('pos', pos);
      return;
    }
    pos[e.key] = {'t': t, 'd': d};
    sj('pos', pos);
  }

  static void clearHist() {
    p.remove('hist');
    p.remove('pos');
    p.remove('seen');
    App.refresh.value++;
  }

  static int get watchSec => p.getInt('lvsec') ?? 0;
  static LvInfo? addWatch(int sec) {
    final t0 = watchSec;
    final a = lvInfo(t0.toDouble()).idx;
    p.setInt('lvsec', t0 + sec);
    final b = lvInfo((t0 + sec).toDouble());
    return b.idx > a ? b : null;
  }
}

/* ===================== UI UMUM ===================== */
Widget poster(String url, {double radius = 14}) => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? Container(color: cardc)
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: cardc),
              errorWidget: (_, __, ___) => Container(color: cardc),
            ),
    );

Widget pill(String t, {bool up = true}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: Colors.black54, borderRadius: BorderRadius.circular(6)),
      child: Text(up ? t.toUpperCase() : t,
          style: const TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
    );

Widget chipB(String label, bool sel, VoidCallback onTap, {IconData? icon}) =>
    GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
            color: sel ? accent : fg.withOpacity(.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sel ? accent : lineC)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: sel ? onAc : fg),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: TextStyle(
                  color: sel ? onAc : fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
        ]),
      ),
    );

Widget tagB(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
          color: accent.withOpacity(.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withOpacity(.6))),
      child: Text(t.isEmpty ? t : t[0].toUpperCase() + t.substring(1),
          style: TextStyle(fontSize: 13, color: fg)),
    );

BoxDecoration cardBox({double r = 16, Color? border}) => BoxDecoration(
    color: isLight ? Colors.white.withOpacity(.9) : fg.withOpacity(.06),
    borderRadius: BorderRadius.circular(r),
    border: Border.all(color: border ?? lineC));

void openDetail(BuildContext c, Group g) => Navigator.push(
        c, MaterialPageRoute(builder: (_) => DetailPage(g.title)))
    .then((_) => App.refresh.value++);

Future<void> playEp(BuildContext c, Ep e) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => PlayerPage(e)))
        .then((_) {
      App.refresh.value++;
    });

class GroupCard extends StatelessWidget {
  final Group g;
  final double? width;
  const GroupCard(this.g, {this.width, super.key});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => openDetail(context, g),
        child: SizedBox(
          width: width,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(fit: StackFit.expand, children: [
                poster(g.thumb),
                Positioned(top: 6, left: 6, child: pill(g.cat)),
                if (g.eps.length > 1)
                  Positioned(
                      left: 8,
                      bottom: 6,
                      child: Text('${g.eps.length} Eps',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(blurRadius: 6, color: Colors.black)
                              ]))),
              ]),
            ),
            const SizedBox(height: 6),
            Text(g.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.25)),
          ]),
        ),
      );
}

Widget section(String title, List<Widget> kids,
        {double h = 165, VoidCallback? more}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w500)),
                if (more != null)
                  GestureDetector(
                      onTap: more,
                      child: Text('Lihat Semua ›',
                          style: TextStyle(color: accent, fontSize: 13))),
              ]),
        ),
        SizedBox(
          height: h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kids.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => kids[i],
          ),
        ),
      ],
    );

Widget recSection(Group g) {
  final r = App.recsFor(g);
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (r.rel.isNotEmpty)
      section('Season & Seri Terkait',
          r.rel.map((x) => GroupCard(x, width: 190)).toList()),
    if (r.more.isNotEmpty)
      section('Rekomendasi Lainnya',
          r.more.map((x) => GroupCard(x, width: 190)).toList()),
  ]);
}

/// grid dengan tinggi sel pasti (poster 16:9 + judul 2 baris)
SliverGridDelegate gridD(double w) {
  final cols = w >= 700 ? 4 : (w >= 480 ? 3 : 2);
  final cw = (w - 12 * (cols - 1)) / cols;
  return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cols,
      crossAxisSpacing: 12,
      mainAxisSpacing: 14,
      mainAxisExtent: cw * 9 / 16 + 6 + 36);
}

void goCat(String c) {
  App.catReq.value = c;
  App.tab.value = 2;
}

Widget outlined(String t, double size) => Stack(children: [
      Text(t,
          style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w900,
              height: .8,
              letterSpacing: -6,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..color = accent)),
      Text(t,
          style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w900,
              height: .8,
              letterSpacing: -6,
              color: bgc)),
    ]);

Widget t10Item(BuildContext c, int i, Group g, int v) {
  final n = '${i + 1}';
  final two = n.length > 1;
  final nw = two ? 128.0 : 72.0;
  return GestureDetector(
    onTap: () => openDetail(c, g),
    child: SizedBox(
      width: nw + 126,
      height: 190,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 0, bottom: -4, child: outlined(n, two ? 112 : 150)),
        Positioned(
          left: nw,
          top: 0,
          width: 126,
          height: 188,
          child: Stack(fit: StackFit.expand, children: [
            poster(g.thumb, radius: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [Colors.black87, Colors.transparent]),
                ),
              ),
            ),
            Positioned(top: 7, right: 7, child: pill('👁 ${fv(v)}', up: false)),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Text(g.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.25)),
            ),
          ]),
        ),
      ]),
    ),
  );
}

/// latar dengan cahaya warna lembut seperti versi web
class GlowBg extends StatelessWidget {
  const GlowBg({super.key});
  Widget _g(Alignment a, Color c, double o) => Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
                center: a,
                radius: .95,
                colors: [c.withOpacity(o), Colors.transparent]),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) {
    if (!curTh.glow) return const SizedBox.shrink();
    final k = isLight ? .5 : 1.0;
    return IgnorePointer(
      child: Stack(children: [
        _g(const Alignment(-1, -1), accent, .28 * k),
        _g(const Alignment(1, -.3), curTh.g2, .22 * k),
        _g(const Alignment(-1, .8), curTh.g3, .18 * k),
      ]),
    );
  }
}

/* ===================== APLIKASI ===================== */
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  final sv = Store.p.getString('theme');
  curTh = themes.firstWhere((t) => t.id == sv, orElse: () => themes[0]);
  themeId.value = curTh.id;
  runApp(const LesehanApp());
}

class LesehanApp extends StatelessWidget {
  const LesehanApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: themeId,
        builder: (_, id, __) => MaterialApp(
          key: ValueKey(id),
          title: 'LesehanTV',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const Root(),
        ),
      );
}

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  int i = App.tab.value;
  void _tabL() {
    if (mounted) setState(() => i = App.tab.value);
  }

  @override
  void initState() {
    super.initState();
    App.tab.addListener(_tabL);
    if (!App.started) {
      App.started = true;
      App.load();
    }
  }

  @override
  void dispose() {
    App.tab.removeListener(_tabL);
    super.dispose();
  }

  Future<void> _popup() async {
    final pp = App.popup;
    if (pp == null || App.popDone) return;
    final img = pp['img']!, lk = pp['link']!, mode = pp['mode']!;
    final st = Store.jm('popup');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (mode != 'selalu' &&
        st['img'] == img &&
        (mode != 'harian' || st['d'] == today)) {
      return;
    }
    App.popDone = true;
    Store.sj('popup', {'img': img, 'd': today});
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final ok = RegExp(r'^https?://', caseSensitive: false).hasMatch(lk);
    showDialog(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: isLight ? Colors.white : const Color(0xFF121216),
        insetPadding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: GestureDetector(
                onTap: ok
                    ? () {
                        Navigator.pop(c);
                        openUrl(lk);
                      }
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedNetworkImage(
                    imageUrl: img,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const SizedBox(
                        height: 160,
                        child: Center(child: CircularProgressIndicator())),
                    errorWidget: (_, __, ___) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (c.mounted) Navigator.pop(c);
                      });
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Tutup'))),
              if (ok) ...[
                const SizedBox(width: 10),
                Expanded(
                    child: FilledButton(
                        onPressed: () {
                          Navigator.pop(c);
                          openUrl(lk);
                        },
                        child: const Text('Buka'))),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: App.refresh,
        builder: (_, __, ___) {
          Widget body;
          if (!App.loaded) {
            body = Center(
              child: App.error != null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(App.error!, textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      FilledButton(
                          onPressed: () {
                            App.error = null;
                            App.refresh.value++;
                            App.load();
                          },
                          child: const Text('Muat Ulang')),
                    ])
                  : const CircularProgressIndicator(),
            );
          } else {
            if (!App.popDone && App.popup != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _popup());
            }
            body = IndexedStack(index: i, children: [
              HomeTab(),
              PopularTab(),
              CatalogTab(),
              LibraryTab(),
              ProfileTab(),
            ]);
          }
          return Scaffold(
            body: Stack(children: [
              const Positioned.fill(child: GlowBg()),
              SafeArea(child: body),
            ]),
            bottomNavigationBar: NavigationBar(
              selectedIndex: i,
              onDestinationSelected: (v) => App.tab.value = v,
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Beranda'),
                NavigationDestination(
                    icon: Icon(Icons.star_outline),
                    selectedIcon: Icon(Icons.star),
                    label: 'Populer'),
                NavigationDestination(
                    icon: Icon(Icons.grid_view),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'Katalog'),
                NavigationDestination(
                    icon: Icon(Icons.bookmark_outline),
                    selectedIcon: Icon(Icons.bookmark),
                    label: 'Koleksi'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Profil'),
              ],
            ),
          );
        },
      );
}

/* ===================== BERANDA ===================== */
class HomeTab extends StatefulWidget {
  HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final pc = PageController();
  Timer? t;
  List<Group> hero = [];
  int heroI = 0;

  Widget top10() {
    List<MapEntry<Group, int>> by(Map<String, int> m) => App.groups
        .map((g) => MapEntry(g, m[tkey(g.title)] ?? 0))
        .where((x) => x.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    var l = by(App.wk);
    var week = true;
    if (l.length < 3) {
      l = by(App.vc);
      week = false;
    }
    if (l.length < 3) return const SizedBox.shrink();
    final top = l.take(10).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
        child: Text(week ? 'Top 10 Minggu Ini' : 'Top 10 Sepanjang Masa',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500)),
      ),
      SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: top.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => t10Item(context, i, top[i].key, top[i].value),
        ),
      ),
    ]);
  }

  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!pc.hasClients || hero.length < 2) return;
      final n = ((pc.page ?? 0).round() + 1) % hero.length;
      pc.animateToPage(n,
          duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    t?.cancel();
    pc.dispose();
    super.dispose();
  }

  List<Group> pick() {
    final l = App.groups.where((g) => g.thumb.isNotEmpty).toList()
      ..shuffle(Random());
    return l.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (hero.isEmpty && App.groups.isNotEmpty) hero = pick();
    final hs =
        Store.hist.map((h) => App.byKey[h['key']]).whereType<Ep>().toList();
    final latest = [...App.groups]..sort((a, b) => b.lastId.compareTo(a.lastId));
    final kinds = [
      ['anime', 'Anime'],
      ['donghua', 'Donghua'],
      ['drama', 'Drama'],
      ['movie', 'Film'],
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                boxShadow: [
                  BoxShadow(color: accent.withOpacity(.5), blurRadius: 14)
                ]),
            child: Icon(Icons.play_arrow_rounded, size: 28, color: onAc),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Welcome', style: TextStyle(fontSize: 11, color: mut)),
              const Text('LesehanTV',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(
              onPressed: () => App.tab.value = 2,
              icon: Icon(Icons.search, color: accent, size: 26)),
        ]),
        const SizedBox(height: 14),
        if (hero.isNotEmpty)
          SizedBox(
            height: 210,
            child: PageView(
              controller: pc,
              onPageChanged: (v) => setState(() => heroI = v),
              children: hero
                  .map((g) => GestureDetector(
                        onTap: () => openDetail(context, g),
                        child: Stack(fit: StackFit.expand, children: [
                          poster(g.thumb, radius: 20),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black87,
                                      Colors.transparent
                                    ]),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 14,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: accent,
                                        borderRadius: BorderRadius.circular(6)),
                                    child: Text(
                                        App.views(g.title) > 0
                                            ? '🔥 POPULER'
                                            : '✨ REKOMENDASI',
                                        style: TextStyle(
                                            color: onAc,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(g.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700)),
                                  Text('${g.cat} • ${g.eps.length} Eps',
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white70)),
                                ]),
                          ),
                        ]),
                      ))
                  .toList(),
            ),
          ),
        if (hero.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = 0; k < hero.length; k++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: k == heroI ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: k == heroI ? accent : fg.withOpacity(.2),
                      borderRadius: BorderRadius.circular(3)),
                ),
            ]),
          ),
        if (hs.isNotEmpty)
          section('Lanjutkan Nonton', hs.map((e) => ResumeCard(e)).toList(),
              more: () => App.tab.value = 3),
        top10(),
        section('Baru Ditambahkan',
            latest.take(12).map((g) => GroupCard(g, width: 190)).toList(),
            more: () => goCat('all')),
        for (final k in kinds)
          Builder(builder: (_) {
            final l = latest.where((g) => kind(g.cat) == k[0]).take(12).toList();
            if (l.isEmpty) return const SizedBox.shrink();
            return section(k[1], l.map((g) => GroupCard(g, width: 190)).toList(),
                more: () => goCat(k[0]));
          }),
      ],
    );
  }
}

class ResumeCard extends StatelessWidget {
  final Ep e;
  const ResumeCard(this.e, {super.key});
  @override
  Widget build(BuildContext context) {
    final g = App.gm[e.title];
    final pr = Store.progOf(e.key);
    return GestureDetector(
      onTap: () => playEp(context, e),
      child: SizedBox(
        width: 190,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              poster(g?.thumb ?? e.thumb),
              Positioned(
                  left: 8,
                  bottom: 8,
                  child: Text(e.eps,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 6, color: Colors.black)]))),
              if (pr > 0)
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                        value: pr,
                        minHeight: 3,
                        color: accent,
                        backgroundColor: Colors.white24)),
            ]),
          ),
          const SizedBox(height: 6),
          Text(e.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.25)),
        ]),
      ),
    );
  }
}

/* ===================== POPULER ===================== */
class PopularTab extends StatefulWidget {
  PopularTab({super.key});
  @override
  State<PopularTab> createState() => _PopularTabState();
}

class _PopularTabState extends State<PopularTab> {
  bool week = true;
  @override
  Widget build(BuildContext context) {
    final m = (week && App.wk.isNotEmpty) ? App.wk : App.vc;
    final l = App.groups
        .map((g) => MapEntry(g, m[tkey(g.title)] ?? 0))
        .where((x) => x.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = l.take(30).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: [
        const Text('🔥 Populer',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(children: [
          chipB('Minggu Ini', week, () => setState(() => week = true)),
          const SizedBox(width: 8),
          chipB('Sepanjang Masa', !week, () => setState(() => week = false)),
        ]),
        const SizedBox(height: 12),
        if (top.isEmpty)
          const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('Belum ada data penonton.')))
        else
          for (var i = 0; i < top.length; i++)
            GestureDetector(
              onTap: () => openDetail(context, top[i].key),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: cardBox(),
                child: Row(children: [
                  SizedBox(
                      width: 38,
                      child: Text('#${i + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: accent, fontWeight: FontWeight.w800))),
                  SizedBox(
                      width: 56,
                      height: 76,
                      child: poster(top[i].key.thumb, radius: 10)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(top[i].key.title,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(
                              '${top[i].key.cat} • ${top[i].key.eps.length} Eps • 👁 ${fv(top[i].value)}',
                              style: TextStyle(fontSize: 12, color: mut)),
                        ]),
                  ),
                ]),
              ),
            ),
      ],
    );
  }
}

/* ===================== KATALOG ===================== */
class CatalogTab extends StatefulWidget {
  CatalogTab({super.key});
  @override
  State<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<CatalogTab> {
  String q = '', cat = 'all';

  void _req() {
    final v = App.catReq.value;
    if (v.isEmpty) return;
    App.catReq.value = '';
    if (mounted) setState(() => cat = v);
  }

  @override
  void initState() {
    super.initState();
    App.catReq.addListener(_req);
  }

  @override
  void dispose() {
    App.catReq.removeListener(_req);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = App.groups
        .where((g) =>
            (cat == 'all' || kind(g.cat) == cat) &&
            (q.isEmpty || g.title.toLowerCase().contains(q)))
        .toList()
      ..sort((a, b) => b.lastId.compareTo(a.lastId));
    const cats = [
      ['all', 'Semua'],
      ['anime', 'Anime'],
      ['donghua', 'Donghua'],
      ['movie', 'Film'],
      ['drama', 'Drama'],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(children: [
        TextField(
          onChanged: (v) => setState(() => q = v.toLowerCase().trim()),
          decoration: InputDecoration(
            hintText: 'Cari judul...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: isLight ? Colors.white : fg.withOpacity(.07),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: cats
                .map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: chipB(c[1], cat == c[0],
                          () => setState(() => cat = c[0])),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: l.isEmpty
              ? const Center(child: Text('Tidak ada konten yang cocok.'))
              : LayoutBuilder(
                  builder: (_, c) => GridView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: l.length,
                    gridDelegate: gridD(c.maxWidth),
                    itemBuilder: (_, i) => GroupCard(l[i]),
                  ),
                ),
        ),
      ]),
    );
  }
}

/* ===================== KOLEKSI ===================== */
class LibraryTab extends StatelessWidget {
  LibraryTab({super.key});
  @override
  Widget build(BuildContext context) {
    final bm = Store.bms.map((t) => App.gm[t]).whereType<Group>().toList();
    final hs =
        Store.hist.map((h) => App.byKey[h['key']]).whereType<Ep>().toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: [
        const Text('Bookmark',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (bm.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Belum ada yang di-bookmark.')))
        else
          LayoutBuilder(
            builder: (_, c) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bm.length,
              gridDelegate: gridD(c.maxWidth),
              itemBuilder: (_, i) => GroupCard(bm[i]),
            ),
          ),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Riwayat Tonton',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          if (hs.isNotEmpty)
            TextButton(
                onPressed: Store.clearHist, child: const Text('Hapus Semua')),
        ]),
        const SizedBox(height: 10),
        if (hs.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Belum ada riwayat.')))
        else
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: hs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => ResumeCard(hs[i]),
            ),
          ),
      ],
    );
  }
}

/* ===================== PROFIL ===================== */
class ProfileTab extends StatelessWidget {
  ProfileTab({super.key});

  Widget _lv() {
    final t = Store.watchSec;
    final i = lvInfo(t.toDouble());
    final R = rlm[i.r];
    final stars = '★' * i.st + '☆' * (9 - i.st);
    final nxt = i.max
        ? 'Puncak Dou Di tercapai 🏯 Level maksimal, waktu nonton tetap dihitung'
        : (i.st == 9 && !i.top
            ? 'Menuju ranah ${rlm[i.r + 1].name}'
            : 'Menuju bintang ${i.st + 1}');
    final left = i.max ? '' : ' · sisa ${fmtDur(i.left)}';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: cardBox(border: R.r >= 9 ? R.c : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🔥 Level Kultivasi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Waktu nonton jadi Dou Qi-mu. Dicatat otomatis di perangkat ini, tanpa akun.',
            style: TextStyle(color: mut, fontSize: 12, height: 1.5)),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: R.c.withOpacity(.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: R.c)),
            child: Text(R.emoji, style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(R.name,
                  style: TextStyle(
                      color: R.c, fontSize: 20, fontWeight: FontWeight.w800)),
              Text(stars,
                  style: TextStyle(color: R.c, fontSize: 15, letterSpacing: 1)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
              value: i.p,
              minHeight: 9,
              color: R.c,
              backgroundColor: fg.withOpacity(.1)),
        ),
        const SizedBox(height: 6),
        Text('$nxt$left', style: TextStyle(color: mut, fontSize: 12)),
        Text('Total nonton ${fmtDur(t)}',
            style: TextStyle(color: mut, fontSize: 12)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: .78,
          children: [
            for (var k = 0; k < rlb.length; k++)
              Opacity(
                opacity: k < R.r ? .85 : (k == R.r ? 1 : .45),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                      color: k == R.r
                          ? rlb[k].c.withOpacity(.18)
                          : fg.withOpacity(.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: k == R.r ? rlb[k].c : lineC)),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(rlb[k].emoji, style: const TextStyle(fontSize: 18)),
                        Text(rlb[k].name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9, height: 1.2)),
                        Text('${rlm.firstWhere((e) => e.r == k).h} jam',
                            style: TextStyle(fontSize: 8, color: mut)),
                      ]),
                ),
              ),
          ],
        ),
      ]),
    );
  }

  Widget _theme() => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: cardBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tema Tampilan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Pilih warna yang paling nyaman di matamu.',
              style: TextStyle(color: mut, fontSize: 12)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.4,
            children: [
              for (final t in themes)
                GestureDetector(
                  onTap: () => setTheme(t.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                        color: fg.withOpacity(.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: t.id == curTh.id ? accent : lineC,
                            width: t.id == curTh.id ? 1.6 : 1)),
                    child: Row(children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: lineC),
                            gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [t.bg, t.bg, t.ac, t.ac],
                                stops: const [0, .5, .5, 1])),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13))),
                    ]),
                  ),
                ),
            ],
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 24),
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent, curTh.g2]),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(.45), blurRadius: 26)
                  ]),
              child: const Icon(Icons.play_arrow_rounded,
                  size: 76, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
              child: Text('LesehanTV',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
          Center(
              child: Text('Streaming santai di mana saja',
                  style: TextStyle(color: mut, fontSize: 13))),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => openUrl('https://saweria.co/AKUINGINTERKENAL'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFAAE2B), Color(0xFFD35400)])),
              child: const Text('❤ Dukung LesehanTV via Saweria',
                  style: TextStyle(
                      color: Color(0xFF12181F),
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
          ),
          const SizedBox(height: 8),
          _lv(),
          _theme(),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => openUrl('https://t.me/+U0ocipINk6MzYmE1'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                      colors: [Color(0xFF229ED9), Color(0xFF1778AB)])),
              child: const Text('Join Komunitas Telegram',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
          ),
        ],
      );
}

/* ===================== SUKA / TIDAK SUKA ===================== */
class VoteRow extends StatelessWidget {
  final String title;
  const VoteRow(this.title, {super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: App.refresh,
        builder: (_, __, ___) {
          final k = tkey(title);
          final r = App.rt[k] ?? [0, 0];
          final my = Store.jm('votes')[k];
          return Row(children: [
            chipB('👍 ${fv(r[0])}', my == 'up', () => App.vote(title, 'up')),
            const SizedBox(width: 8),
            chipB('👎 ${fv(r[1])}', my == 'down', () => App.vote(title, 'down')),
          ]);
        },
      );
}

/* ===================== DETAIL ===================== */
class DetailPage extends StatefulWidget {
  final String title;
  const DetailPage(this.title, {super.key});
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  bool desc = true, more = false;
  String dq = '';

  @override
  void initState() {
    super.initState();
    final g = App.gm[widget.title];
    if (g != null) App.metaFetch(g);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: App.refresh,
        builder: (_, __, ___) => _body(context),
      );

  Widget _body(BuildContext context) {
    final g = App.gm[widget.title];
    if (g == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Judul tidak ditemukan.')));
    }
    final hist = Store.hist.where((h) => h['title'] == g.title);
    final last = hist.isEmpty ? null : App.byKey[hist.first['key']];
    final first = last ?? g.eps.first;
    final meta = App.metaOf(g.title);
    final syn = g.syn.isNotEmpty ? g.syn : s(meta['s']);
    final auto = g.syn.isEmpty && s(meta['s']).isNotEmpty;
    final rating = (meta['r'] as num?)?.toDouble() ?? 0.0;
    var genres = g.gen
        .split(RegExp(r'[,;|]'))
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList();
    if (genres.isEmpty) {
      genres = ((meta['g'] as List?) ?? []).map((x) => x.toString()).toList();
    }
    var list = desc ? g.eps.reversed.toList() : [...g.eps];
    final qq = dq.trim().toLowerCase();
    if (qq.isNotEmpty) {
      list = list.where((e) => e.eps.toLowerCase().contains(qq)).toList();
    }
    final bm = Store.isBm(g.title);
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 300,
          backgroundColor: bgc,
          automaticallyImplyLeading: false,
          leading: Padding(
            padding: const EdgeInsets.all(6),
            child: IconButton(
              style: IconButton.styleFrom(backgroundColor: Colors.black45),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              poster(g.thumb, radius: 0),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: const Alignment(0, -.15),
                      colors: [bgc, bgc.withOpacity(0)]),
                ),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.cat,
                  style: TextStyle(
                      color: accent, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(g.title,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                tagB(kind(g.cat)),
                tagB('${g.eps.length} Eps'),
                if (rating > 0) tagB('⭐ ${rating.toStringAsFixed(1)}/10'),
                for (final x in genres) tagB(x),
              ]),
              const SizedBox(height: 14),
              VoteRow(g.title),
              if (syn.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(syn,
                    maxLines: more ? null : 4,
                    overflow: more ? null : TextOverflow.ellipsis,
                    style: TextStyle(color: mut, height: 1.6, fontSize: 14)),
                if (syn.length > 220)
                  GestureDetector(
                    onTap: () => setState(() => more = !more),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(more ? 'Tutup ▴' : 'Selengkapnya ▾',
                          style: TextStyle(color: accent, fontSize: 13)),
                    ),
                  ),
                if (auto)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Sinopsis dari ${s(meta['src']).isEmpty ? 'TMDB' : s(meta['src'])}',
                        style: TextStyle(
                            color: mut.withOpacity(.7), fontSize: 11)),
                  ),
              ] else if (App.metaBusy.contains(g.title))
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('Memuat sinopsis...',
                      style: TextStyle(color: mut, fontSize: 12)),
                ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  flex: 6,
                  child: FilledButton.icon(
                    onPressed: () => playEp(context, first),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(last != null ? 'Lanjut Nonton' : 'Tonton Sekarang'),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: OutlinedButton.icon(
                    onPressed: () => Store.toggleBm(g.title),
                    icon: Icon(bm ? Icons.bookmark : Icons.bookmark_add_outlined),
                    label: Text(bm ? 'Tersimpan' : 'Bookmark'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${g.eps.length} Episode',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w500)),
                TextButton(
                    onPressed: () => setState(() => desc = !desc),
                    child: Text(desc ? '↓ Terbaru' : '↑ Terlama')),
              ]),
              if (g.eps.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  child: TextField(
                    onChanged: (v) => setState(() => dq = v),
                    decoration: InputDecoration(
                      hintText: 'Cari episode...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: isLight ? Colors.white : fg.withOpacity(.07),
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        if (list.isEmpty)
          const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('Episode tidak ditemukan.'))))
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                final e = list[i];
                final seen = Store.seen(e.key);
                final pr = Store.progOf(e.key);
                final isLast = last != null && last.key == e.key;
                final isNew = e.id >= App.eps.length - 10;
                return GestureDetector(
                  onTap: () => playEp(context, e),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    decoration: cardBox(border: isLast ? accent : null),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          child: Row(children: [
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isLast
                                      ? accent
                                      : accent.withOpacity(.14)),
                              child: Icon(Icons.play_arrow_rounded,
                                  size: 20, color: isLast ? onAc : accent),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Opacity(
                                opacity: seen ? .55 : 1,
                                child: Row(children: [
                                  Flexible(
                                    child: Text(
                                        e.eps.isEmpty ? 'Putar Video' : e.eps,
                                        style: const TextStyle(fontSize: 15)),
                                  ),
                                  if (isNew)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFE50914),
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: const Text('NEW',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w800)),
                                    ),
                                ]),
                              ),
                            ),
                            if (seen)
                              Icon(Icons.check_circle, size: 20, color: accent),
                          ]),
                        ),
                        if (!seen && pr > 0)
                          Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                  value: pr,
                                  minHeight: 3,
                                  color: accent,
                                  backgroundColor: Colors.transparent)),
                      ]),
                    ),
                  ),
                );
              },
              childCount: list.length,
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
            child: recSection(g),
          ),
        ),
      ]),
    );
  }
}

/* ===================== PEMUTAR ===================== */
const reportReasons = [
  'Video tidak bisa diputar',
  'Video putus-putus atau buffering',
  'Subtitle salah atau tidak ada',
  'Audio bermasalah',
  'Episode salah atau tertukar',
  'Lainnya',
];

class PlayerPage extends StatefulWidget {
  final Ep ep;
  const PlayerPage(this.ep, {super.key});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late Ep ep;
  int sv = 0, _tok = 0, _last = 0;
  bool loading = true, _ended = false, _resumed = true;
  String? err;
  VideoPlayerController? vc;
  ChewieController? cc;
  WebViewController? wc;
  Timer? _wt;

  @override
  void initState() {
    super.initState();
    ep = widget.ep;
    WidgetsBinding.instance.addObserver(this);
    _wt = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_resumed || loading || err != null) return;
      final playing = vc != null ? vc!.value.isPlaying : wc != null;
      if (!playing) return;
      final up = Store.addWatch(5);
      if (up != null) {
        final R = rlm[up.r];
        toast(
            context,
            up.st == 1
                ? '🎉 Naik ranah! ${R.emoji} ${R.name} ★1'
                : '✨ ${R.name} naik ke bintang ${up.st}');
      }
    });
    start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
  }

  void _release() {
    final v = vc;
    if (v != null) {
      try {
        Store.savePos(ep, v.value.position.inSeconds.toDouble(),
            v.value.duration.inSeconds.toDouble());
      } catch (_) {}
      v.removeListener(_onTick);
    }
    cc?.dispose();
    vc?.dispose();
    cc = null;
    vc = null;
    wc = null;
  }

  Future<void> start() async {
    final tk = ++_tok;
    _release();
    _ended = false;
    setState(() {
      loading = true;
      err = null;
    });
    App.regView(ep.title);
    try {
      final url = await App.resolveUrl(ep, sv);
      if (tk != _tok || !mounted) return;
      if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
        throw 'link tidak valid';
      }
      final hls = sv == 0
          ? (ep.tipeHls || url.contains('.m3u8'))
          : ep.extra[sv - 1].hls;
      if (hls) {
        final c = VideoPlayerController.networkUrl(Uri.parse(url));
        await c.initialize();
        if (tk != _tok || !mounted) {
          c.dispose();
          return;
        }
        final st = Store.posOf(ep.key);
        if (st > 0) await c.seekTo(Duration(seconds: st.toInt()));
        c.addListener(_onTick);
        vc = c;
        cc = ChewieController(
          videoPlayerController: c,
          autoPlay: true,
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          allowedScreenSleep: false,
          deviceOrientationsOnEnterFullScreen: [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight
          ],
          deviceOrientationsAfterFullScreen: [DeviceOrientation.portraitUp],
          materialProgressColors: ChewieProgressColors(
              playedColor: accent,
              handleColor: accent,
              bufferedColor: Colors.white30,
              backgroundColor: Colors.white12),
        );
      } else {
        final host = Uri.parse(url).host;
        wc = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (r) {
            // blokir popup/pengalihan iklan: hanya halaman utama server yang boleh
            if (!r.isMainFrame) return NavigationDecision.navigate;
            final h = Uri.tryParse(r.url)?.host ?? '';
            return (h == host || r.url == url)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          }))
          ..loadRequest(Uri.parse(url));
        Store.markSeen(ep.key);
      }
      Store.touchHist(ep);
    } catch (_) {
      if (tk == _tok) err = 'Video gagal diputar';
    }
    if (tk == _tok && mounted) setState(() => loading = false);
  }

  void _onTick() {
    final v = vc?.value;
    if (v == null || !v.isInitialized) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _last > 5000 && v.isPlaying) {
      _last = now;
      Store.savePos(ep, v.position.inSeconds.toDouble(),
          v.duration.inSeconds.toDouble());
    }
    if (!_ended &&
        v.duration.inSeconds > 0 &&
        v.position >= v.duration - const Duration(milliseconds: 500)) {
      _ended = true;
      Store.markSeen(ep.key);
      _next();
    }
  }

  void _next() {
    final g = App.gm[ep.title];
    if (g == null) return;
    final i = g.eps.indexWhere((e) => e.id == ep.id);
    if (i >= 0 && i < g.eps.length - 1) _go(g.eps[i + 1]);
  }

  void _go(Ep e) {
    ep = e;
    sv = 0;
    start();
  }

  @override
  void dispose() {
    _wt?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tok++;
    _release();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _report() {
    var reason = reportReasons[0];
    final note = TextEditingController();
    var busy = false;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('⚠ Lapor video rusak'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${ep.title}${ep.eps.isEmpty ? '' : ' - ${ep.eps}'}',
                style: TextStyle(color: mut, fontSize: 13)),
            const SizedBox(height: 12),
            DropdownButton<String>(
              isExpanded: true,
              value: reason,
              items: reportReasons
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) => set(() => reason = v ?? reason),
            ),
            TextField(
              controller: note,
              maxLength: 160,
              maxLines: 2,
              decoration:
                  const InputDecoration(hintText: 'Keterangan tambahan (opsional)'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      set(() => busy = true);
                      final r = await App.report(ep, reason, note.text);
                      if (c.mounted) Navigator.pop(c);
                      if (mounted) {
                        toast(
                            context,
                            r == 1
                                ? 'Laporan terkirim, terima kasih'
                                : r == 2
                                    ? 'Laporan untuk video ini sudah terkirim, terima kasih'
                                    : 'Gagal mengirim laporan, coba lagi');
                      }
                    },
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _video() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (err != null) {
      final n = 1 + ep.extra.length;
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('⚠️ $err', style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(onPressed: start, child: const Text('Coba Lagi')),
            if (n > 1) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: () {
                    sv = (sv + 1) % n;
                    start();
                  },
                  child: const Text('Ganti Server')),
            ],
          ]),
        ]),
      );
    }
    if (cc != null) return Chewie(controller: cc!);
    if (wc != null) return WebViewWidget(controller: wc!);
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final g = App.gm[ep.title];
    final all = g?.eps ?? [ep];
    final names = [
      ep.svn.isEmpty ? 'Server 1' : ep.svn,
      ...ep.extra.map((x) => x.name)
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Row(children: [
            IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context)),
            Expanded(
                child: Text(
                    '${ep.title}${ep.eps.isEmpty ? '' : ' - ${ep.eps}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13))),
          ]),
          AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(color: Colors.black, child: _video())),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(14), children: [
              Row(children: [
                Container(
                  width: 54,
                  height: 54,
                  margin: const EdgeInsets.only(right: 12),
                  child: ClipOval(child: poster(g?.thumb ?? ep.thumb, radius: 0)),
                ),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ep.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                            '${ep.eps}${ep.eps.isEmpty ? '' : '  •  '}👁 ${fv(App.views(ep.title))} penonton',
                            style: TextStyle(color: mut, fontSize: 12)),
                      ]),
                ),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                VoteRow(ep.title),
                GestureDetector(
                  onTap: _report,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                        color: fg.withOpacity(.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: lineC)),
                    child: const Text('⚠ Lapor video rusak',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
              ]),
              if (names.length > 1) ...[
                const SizedBox(height: 16),
                const Text('🖥 Pilih Server'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: names.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => chipB(names[i], sv == i, () {
                      if (sv == i) return;
                      sv = i;
                      start();
                    }),
                  ),
                ),
              ],
              if (all.length > 1) ...[
                const SizedBox(height: 16),
                const Text('Episode List',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: all.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final e = all[i];
                      final lb = e.eps.replaceFirst(
                          RegExp(r'^Eps\s*', caseSensitive: false), '');
                      return chipB(lb.isEmpty ? '▶' : lb, e.id == ep.id, () {
                        if (e.id != ep.id) _go(e);
                      }, icon: Store.seen(e.key) ? Icons.check : null);
                    },
                  ),
                ),
              ],
              if (g != null) recSection(g),
            ]),
          ),
        ]),
      ),
    );
  }
}
