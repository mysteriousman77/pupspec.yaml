import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'dart:io' show Directory, File, gzip;
import 'dart:math';
import 'dart:ui' show ImageByteFormat, ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const api =
    'https://script.google.com/macros/s/AKfycbycxushyypYFF1FptMeQYXRcldkioUTsHXg6-l69LamTBvK_BPjP5w5NHa8XK3_Cuc/exec';
const tmdbKey = '9f660b069ce86b86c8b671b14338d3b2';

/* ===================== TOKEN API (anti scraping) ===================== */
// kunci disamarkan (XOR) agar tidak terbaca langsung dari string di APK
const _akb = [57, 98, 62, 59, 60, 109, 63, 108, 62, 107, 62, 63, 108, 59, 107, 99, 62, 109, 60, 63, 60, 105, 109, 63, 57, 106, 106, 63, 60, 98, 98, 60, 62, 105, 106, 60, 57, 63, 98, 57, 59, 110, 109, 106, 57, 106, 104, 108];
final List<int> _ak = [for (final c in _akb) c ^ 0x5A];

/// nomor build (diisi otomatis oleh GitHub Actions lewat --dart-define=BUILD=...)
const int kBuild = int.fromEnvironment('BUILD', defaultValue: 0);

/// bangun URL API bertanda waktu + tanda tangan HMAC; server menolak permintaan tanpa token valid
String apiQ(String q) {
  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final act = q.isEmpty ? 'list' : q.split('=').first.split('&').first;
  final sig = Hmac(sha256, _ak)
      .convert(utf8.encode('$ts|$act'))
      .toString()
      .substring(0, 20);
  return '$api${q.isEmpty ? '?' : '?$q&'}k=$ts.$sig';
}

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

/// efek kaca & animasi penuh selalu aktif
bool get ultra => true;

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

/// kunci unik per episode (judul+eps+id/src), dijamin tidak bentrok
/// urutan terbaru: tiap sheet kategori punya "baris terakhir" sendiri,
/// jadi yang terbaru dari setiap sheet tampil berdampingan
int newer(Group a, Group b) {
  final c = a.rk.compareTo(b.rk);
  return c != 0 ? c : b.lastId.compareTo(a.lastId);
}

String ukey(String title, String eps, String idOrSrc, Set<String> used) {
  var k = 'e${tkey('$title|$eps|$idOrSrc')}';
  var n = 1;
  while (!used.add(k)) {
    k = 'e${tkey('$title|$eps|$idOrSrc|${n++}')}';
  }
  return k;
}

/// iklan HilltopAds (tidak dipakai lagi): dibuka di browser luar saat pengguna pindah server, jeda 10 menit
const hilltopUrl = 'https://idealistic-revenue.com/VFz14e';
void hilltopAd() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final last = Store.p.getInt('ht_last') ?? 0;
  if (now - last < 600000) return;
  Store.p.setInt('ht_last', now);
  openUrl(hilltopUrl);
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
      .replaceAll(RegExp(r'\b[rs]\d+\b'), ' ');
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
          r'season\s*(\d+)|\bs(\d+)\b|(\d+)(?:st|nd|rd|th)\s*season|part\s*(\d+)|\s(\d+)\s*(?:\([^)]*\))?\s*$|\br(\d+)\b')
      .firstMatch(t.toLowerCase());
  if (m == null) return 1;
  for (var i = 1; i <= 6; i++) {
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
  if (sh.length >= 6 && lg.startsWith('$sh ')) return true;
  // judul seri sama dengan subjudul berbeda: minimal 3 kata awal sama & panjang >= 14
  final wa = a.split(' '), wb = b.split(' ');
  var n = 0;
  while (n < wa.length && n < wb.length && wa[n] == wb[n]) {
    n++;
  }
  final pre = wa.take(n).join(' ');
  return n >= 3 && pre.length >= 14;
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
  int rk; // urutan dari bawah di sheet asalnya (0 = baris terakhir)
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
    this.rk = 0,
  });
}

class Group {
  final String title, cat;
  final int gi;
  String thumb = '', syn = '', gen = '';
  int lastId = 0;
  int rk = 1 << 30;
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
    final usedK = <String>{};
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
        key: ukey(s(it['judul']), eps, rid.isNotEmpty ? rid : src, usedK),
        thumb: s(it['thumb']),
        syn: cut(
            s(it['sinopsis']).isNotEmpty ? s(it['sinopsis']) : s(it['synopsis']),
            2000),
        gen: cut(
            s(it['genre']).isNotEmpty ? s(it['genre']) : s(it['genres']), 200),
        svn: s(it['nama1']),
        tipeHls: tp == 'hls' || tp == 'm3u8',
        extra: extra,
        rk: int.tryParse(s(it['_r'])) ?? 0,
      ));
    }
    // cadangan: kalau server tidak mengirim _r, hitung urutan terbaru per kategori dari urutan baris
    if (out.isNotEmpty && out.every((e) => e.rk == 0)) {
      final tot = <String, int>{}, seen = <String, int>{};
      for (final e in out) {
        tot[e.cat] = (tot[e.cat] ?? 0) + 1;
      }
      for (final e in out) {
        seen[e.cat] = (seen[e.cat] ?? 0) + 1;
        e.rk = tot[e.cat]! - seen[e.cat]!;
      }
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
      if (e.rk < g.rk) g.rk = e.rk;
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

  static bool statsOk = false, _sb = false;
  static int _sl = 0;
  static List<Map<String, String>> info = [];
  static Map<String, dynamic>? upd; // {min, url, msg, force} dari sheet Update
  static bool updShown = false;
  static Timer? _poll;

  static Future<void> load() async {
    error = null;
    // statistik & pengumuman dari cache dulu, lalu diambil paralel
    try {
      final sc = Store.p.getString('stats');
      if (sc != null) applyStats(jsonDecode(sc) as Map);
      final ic = Store.p.getString('info');
      if (ic != null) applyInfo(jsonDecode(ic));
    } catch (_) {}
    loadStats(force: true);
    loadInfo();
    startPoll();
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
          await http.get(Uri.parse(apiQ(''))).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw 'x';
      final body = utf8.decode(r.bodyBytes);
      final d = jsonDecode(body);
      if (d is! List) throw 'x';
      ingest(d);
      loaded = true;
      Store.p.setString('cache', body);
      ping();
      Prem.recheck();
    } catch (_) {
      if (!loaded) error = 'Gagal mengambil data. Periksa koneksi lalu coba lagi.';
    }
    refresh.value++;
  }

  static Map<String, int> _ints(Map m) => {
        for (final e in m.entries)
          e.key.toString(): (e.value is num) ? (e.value as num).toInt() : 0
      };

  static void applyStats(Map d) {
    if (d['v'] is! Map) return;
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
    statsOk = true;
  }

  static Future<void> loadStats({bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_sb || (!force && now - _sl < 8000)) return;
    _sb = true;
    for (var a = 0; a < 3; a++) {
      try {
        final r = await http
            .get(Uri.parse(apiQ('stats=1&_=$now')))
            .timeout(const Duration(seconds: 15));
        final body = utf8.decode(r.bodyBytes);
        final d = jsonDecode(body);
        if (d is Map && d['v'] is Map) {
          applyStats(d);
          Store.p.setString('stats', body);
          break;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
    _sl = DateTime.now().millisecondsSinceEpoch;
    _sb = false;
    refresh.value++;
  }

  static void applyInfo(dynamic d) {
    if (d is Map && d['upd'] is Map) {
      final u = d['upd'] as Map;
      upd = {
        'min': int.tryParse(s(u['min'])) ?? 0,
        'url': s(u['url']),
        'msg': s(u['msg']),
        'force': s(u['force']) != '0',
      };
    }
    if (d is Map && d['info'] is List) {
      info = (d['info'] as List)
          .whereType<Map>()
          .map((m) => {'t': s(m['t']), 'l': s(m['l'])})
          .where((m) => m['t']!.isNotEmpty)
          .toList();
    }
  }

  static Future<void> loadInfo() async {
    try {
      final r = await http
          .get(Uri.parse(apiQ('info=1')))
          .timeout(const Duration(seconds: 15));
      final body = utf8.decode(r.bodyBytes);
      final d = jsonDecode(body);
      if (d is Map && d['info'] is List) {
        applyInfo(d);
        Store.p.setString('info', body);
        refresh.value++;
      }
    } catch (_) {}
  }

  /// perbarui statistik & pengumuman tiap 60 detik
  static void startPoll() {
    _poll ??= Timer.periodic(const Duration(seconds: 60), (_) {
      loadStats(force: true);
      loadInfo();
    });
  }

  static int views(String t) => vc[tkey(t)] ?? 0;

  static Future<String> resolveUrl(Ep e, int sv) async {
    if (sv > 0) return e.extra[sv - 1].url;
    if (e.direct != null) return e.direct!;
    final r = await http
        .get(Uri.parse(apiQ('id=${Uri.encodeComponent(e.rid!)}')))
        .timeout(const Duration(seconds: 15));
    final d = jsonDecode(utf8.decode(r.bodyBytes));
    final u = s(d is Map ? d['src'] : '');
    if (u.isEmpty) throw 'kosong';
    return u;
  }

  /// catat 1 pengunjung unik per hari (ID acak anonim, tanpa data pribadi)
  static void ping() {
    try {
      final today = DateTime.now().toUtc().add(const Duration(hours: 7));
      final ds = '${today.year}${today.month}${today.day}';
      if (Store.p.getString('pg_day') == ds) return;
      var id = Store.p.getString('pg_id');
      if (id == null) {
        final r = Random();
        id = List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join();
        Store.p.setString('pg_id', id);
      }
      Store.p.setString('pg_day', ds);
      unawaited(http
          .get(Uri.parse(apiQ('ping=$id')))
          .then((_) {}, onError: (_) {}));
    } catch (_) {}
  }

  static void regView(String title) {
    final k = tkey(title);
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = Store.p.getInt('vw_$k') ?? 0;
    if (now - last < 1800000) return;
    Store.p.setInt('vw_$k', now);
    unawaited(http
        .get(Uri.parse(apiQ('view=${Uri.encodeComponent(k)}')))
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
          .get(Uri.parse(apiQ('vote=${Uri.encodeComponent(k)}&v=$nv&prev=$prev')))
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
        'report=1&t=${Uri.encodeComponent(cut(e.title, 100))}&e=${Uri.encodeComponent(cut(e.eps, 40))}&r=${Uri.encodeComponent(reason)}&n=${Uri.encodeComponent(cut(note.trim(), 160))}';
    try {
      final r = await http.get(Uri.parse(apiQ(q))).timeout(const Duration(seconds: 15));
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
    // nama mirip (kata awal sama / kemiripan tinggi) didahulukan, lalu acak
    double sc(Group x) {
      final fa = g.base.split(' ').first, fb = x.base.split(' ').first;
      final s0 = simT(g.base, x.base);
      return s0 + (fa.length >= 4 && fa == fb ? .5 : 0);
    }

    final sim = pool.where((x) => sc(x) >= .6).toList()
      ..sort((a, b) => sc(b).compareTo(sc(a)));
    final simIds = sim.take(4).toSet();
    final rest = pool.where((x) => !simIds.contains(x)).toList();
    final same = rest.where((x) => kind(x.cat) == kind(g.cat)).toList()
      ..shuffle(rnd);
    final other = rest.where((x) => kind(x.cat) != kind(g.cat)).toList()
      ..shuffle(rnd);
    return _recCache[g.title] = Recs(rel.take(12).toList(),
        [...simIds, ...same, ...other].take(12).toList());
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

  static void removeHist(String key) {
    final l = hist..removeWhere((h) => h['key'] == key);
    sj('hist', l);
    final pos = jm('pos');
    if (pos.remove(key) != null) sj('pos', pos);
    App.refresh.value++;
  }

  static void clearHist() {
    p.remove('hist');
    p.remove('pos');
    p.remove('seen');
    App.refresh.value++;
  }

  /* ----- rekap tontonan (gaya Spotify Wrapped) ----- */
  static int get watchSec => p.getInt('lvsec') ?? 0;

  static String dayKey(DateTime d) => d.toIso8601String().substring(0, 10);

  static Map<String, int> wk(String bucket) {
    final m = jm('wk')[bucket];
    if (m is! Map) return {};
    return m.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  static void addWatch(Ep e, int sec) {
    p.setInt('lvsec', watchSec + sec);
    final w = jm('wk');
    void bump(String bucket, String k) {
      if (k.isEmpty) return;
      final m = Map<String, dynamic>.from((w[bucket] as Map?) ?? {});
      m[k] = ((m[k] as num?)?.toInt() ?? 0) + sec;
      w[bucket] = m;
    }

    bump('d', dayKey(DateTime.now()));
    bump('t', e.title);
    bump('c', e.cat);
    for (final g in e.gen.split(RegExp(r'[,;|]'))) {
      bump('g', g.trim());
    }
    sj('wk', w);
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
    Tap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
            color: sel ? accent : (ultra ? null : fg.withOpacity(.06)),
            gradient: (!sel && ultra)
                ? LinearGradient(colors: [
                    fg.withOpacity(isLight ? .06 : .14),
                    accent.withOpacity(.06)
                  ])
                : null,
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

BoxDecoration cardBox({double r = 16, Color? border}) => ultra
    ? BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              isLight ? Colors.white.withOpacity(.85) : Colors.white.withOpacity(.13),
              accent.withOpacity(.05)
            ]),
        borderRadius: BorderRadius.circular(r),
        border: Border.all(
            color: border ?? (isLight ? Colors.white : Colors.white24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.14),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ])
    : BoxDecoration(
        color: isLight ? Colors.white.withOpacity(.9) : fg.withOpacity(.06),
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: border ?? lineC));

void openDetail(BuildContext c, Group g) {
  final pl = _PlayerPageState.top;
  pl?.hold();
  Navigator.push(c, pageR(DetailPage(g.title))).then((_) {
    App.refresh.value++;
    pl?.release();
  });
}

Future<void> playEp(BuildContext c, Ep e) {
  final pl = _PlayerPageState.top;
  pl?.hold();
  return Navigator.push(c, pageR(PlayerPage(e))).then((_) {
    App.refresh.value++;
    pl?.release();
  });
}

class GroupCard extends StatelessWidget {
  final Group g;
  final double? width;
  const GroupCard(this.g, {this.width, super.key});
  @override
  Widget build(BuildContext context) => fxIn(Tap(
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
      ));
}

Widget section(String title, List<Widget> kids,
        {double h = 165, VoidCallback? more, bool auto = true}) =>
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
                  Tap(
                      onTap: more,
                      child: Text('Lihat Semua ›',
                          style: TextStyle(color: accent, fontSize: 13))),
              ]),
        ),
        SizedBox(
          height: h,
          child: AutoRow(count: kids.length, auto: auto, item: (_, i) => kids[i]),
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
  return Tap(
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

/* ===================== EFEK: LITE / ULTRA ===================== */
double get navPad => ultra ? 112.0 : 20.0;

Widget blurW({required Widget child, double s = 18, BorderRadius? r}) {
  if (!ultra) return child;
  return ClipRRect(
      borderRadius: r ?? BorderRadius.zero,
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: s, sigmaY: s), child: child));
}

/// muncul pelan (hanya Ultra)
Widget fxIn(Widget c) => !ultra
    ? c
    : TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (_, v, ch) => Opacity(
            opacity: v,
            child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: ch)),
        child: c,
      );

/// semua tombol/kartu: mengecil sedikit saat ditekan (Lite ringan, Ultra lebih terasa)
class Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Tap({required this.child, this.onTap, super.key});
  @override
  State<Tap> createState() => _TapS();
}

class _TapS extends State<Tap> {
  bool d = false;
  void _s(bool v) {
    if (mounted && d != v) setState(() => d = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _s(true),
        onTapUp: (_) => _s(false),
        onTapCancel: () => _s(false),
        onTap: widget.onTap == null
            ? null
            : () {
                // tap cepat tetap terlihat "memantul"
                _s(true);
                Future.delayed(const Duration(milliseconds: 110), () => _s(false));
                widget.onTap!();
              },
        child: AnimatedScale(
            scale: d ? (ultra ? .94 : .96) : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: widget.child),
      );
}

/// latar tema (cahaya warna) di belakang halaman Detail & Pemutar
class GlowShell extends StatelessWidget {
  final Widget child;
  const GlowShell(this.child, {super.key});
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        ColoredBox(color: bgc),
        const Positioned.fill(child: GlowBg()),
        Theme(
            data: Theme.of(context)
                .copyWith(scaffoldBackgroundColor: Colors.transparent),
            child: child),
      ]);
}

Route<T> pageR<T>(Widget w) {
  final pg = GlowShell(w);
  if (!ultra) return MaterialPageRoute<T>(builder: (_) => pg);
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => pg,
    transitionsBuilder: (_, a, __, c) {
      final cv = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
          opacity: cv,
          child: SlideTransition(
              position: Tween(begin: const Offset(0, .05), end: Offset.zero)
                  .animate(cv),
              child: c));
    },
  );
}

const _navIc = <List<Object>>[
  [Icons.home_outlined, Icons.home_rounded, 'Beranda'],
  [Icons.star_outline_rounded, Icons.star_rounded, 'Populer'],
  [Icons.grid_view_outlined, Icons.grid_view_rounded, 'Katalog'],
  [Icons.bookmark_outline_rounded, Icons.bookmark_rounded, 'Koleksi'],
  [Icons.person_outline_rounded, Icons.person_rounded, 'Profil'],
];

/// navigasi bawah melayang berbahan kaca, indikator meluncur ke tab terpilih
class FloatNav extends StatelessWidget {
  final int i;
  final ValueChanged<int> on;
  const FloatNav(this.i, this.on, {super.key});

  Widget _item(int k) {
    final sel = k == i;
    final ic = _navIc[k];
    return Container(
      color: Colors.transparent,
      alignment: Alignment.center,
      child: AnimatedScale(
        scale: sel ? 1.08 : 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(sel ? ic[1] as IconData : ic[0] as IconData,
                key: ValueKey(sel),
                size: 24,
                color: sel ? accent : mut),
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? accent : mut),
            child: Text(ic[2] as String),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        height: 68,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(.22),
                  blurRadius: 22,
                  offset: const Offset(0, 8))
            ]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isLight
                          ? [
                              Colors.white.withOpacity(.8),
                              Colors.white.withOpacity(.5)
                            ]
                          : [
                              Colors.white.withOpacity(.18),
                              Colors.black.withOpacity(.4)
                            ]),
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(
                      color: Colors.white.withOpacity(isLight ? .9 : .24))),
              child: LayoutBuilder(builder: (_, bc) {
                final w = bc.maxWidth / 5;
                return Stack(children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    left: i * w + 5,
                    top: 7,
                    width: w - 10,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            accent.withOpacity(.34),
                            accent.withOpacity(.14)
                          ]),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: accent.withOpacity(.55))),
                    ),
                  ),
                  Row(children: [
                    for (var k = 0; k < 5; k++)
                      Expanded(child: Tap(onTap: () => on(k), child: _item(k))),
                  ]),
                ]);
              }),
            ),
          ),
        ),
      );
}

/// pindah tab dengan geser + pudar (semua tab tetap hidup)
class TabSwitch extends StatelessWidget {
  final int index;
  final List<Widget> children;
  const TabSwitch({required this.index, required this.children, super.key});
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        for (var k = 0; k < children.length; k++)
          IgnorePointer(
            ignoring: k != index,
            child: AnimatedSlide(
              offset: k == index
                  ? Offset.zero
                  : Offset(k < index ? -.07 : .07, 0),
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: k == index ? 1 : 0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                child: children[k],
              ),
            ),
          ),
      ]);
}

/// teks pengumuman berjalan: waktu global, jadi tidak pernah ter-reset
final _mqSw = Stopwatch()..start();

class Marquee extends StatefulWidget {
  const Marquee({super.key});
  @override
  State<Marquee> createState() => _MarqueeS();
}

class _MarqueeS extends State<Marquee> with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (App.info.isEmpty) return const SizedBox.shrink();
    final txt = '${App.info.map((m) => m['t']!).join('      •      ')}            ';
    final st = TextStyle(fontSize: 13, color: fg);
    final tp = TextPainter(
        text: TextSpan(text: txt, style: st),
        textDirection: TextDirection.ltr,
        maxLines: 1)
      ..layout();
    final w = max(tp.width, 40.0);
    final link = App.info.map((m) => m['l']!).firstWhere((l) => l.isNotEmpty,
        orElse: () => '');
    return Tap(
      onTap: link.isEmpty ? null : () => openUrl(link),
      child: Container(
        height: 38,
        padding: const EdgeInsets.only(left: 12),
        decoration: cardBox(r: 14),
        child: Row(children: [
          const Text('📢', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(
                builder: (_, bc) {
                  final n = (bc.maxWidth / w).ceil() + 1;
                  return AnimatedBuilder(
                    animation: c,
                    builder: (_, __) {
                      final off = (_mqSw.elapsedMilliseconds * 0.045) % w;
                      return OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: 0,
                        maxWidth: double.infinity,
                        child: Transform.translate(
                          offset: Offset(-off, 0),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var k = 0; k < n; k++)
                                  Text(txt,
                                      style: st,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.visible),
                              ]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// volume & kecerahan asli perangkat lewat kode native (Kotlin)
const _nat = MethodChannel('lesehan/native');

class Gest {
  static double vol = .5, bri = .5;
  static Future<void> init() async {
    try {
      vol = ((await _nat.invokeMethod('getVolume')) as num).toDouble();
      bri = ((await _nat.invokeMethod('getBrightness')) as num).toDouble();
    } catch (_) {}
  }

  static void setVol(double v) {
    vol = v.clamp(0.0, 1.0);
    _nat.invokeMethod('setVolume', vol).catchError((_) {});
  }

  static void setBri(double v) {
    bri = v.clamp(0.01, 1.0);
    _nat.invokeMethod('setBrightness', bri).catchError((_) {});
  }

  static void resetBri() {
    _nat.invokeMethod('setBrightness', -1.0).catchError((_) {});
  }
}

/// geser vertikal: kiri = kecerahan, kanan = volume
class GestLayer extends StatefulWidget {
  final Widget child;
  final bool fitBtn;
  const GestLayer({required this.child, this.fitBtn = false, super.key});
  @override
  State<GestLayer> createState() => _GestS();
}

class _GestS extends State<GestLayer> {
  bool left = false, show = false;
  double val = 0;
  Timer? _h;

  @override
  void initState() {
    super.initState();
    Gest.init();
  }

  @override
  void dispose() {
    _h?.cancel();
    super.dispose();
  }

  void _pop() {
    setState(() => show = true);
    _h?.cancel();
    _h = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => show = false);
    });
  }

  Widget _ind() => Container(
        width: 170,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(.68),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(
              left
                  ? Icons.brightness_6
                  : (val <= 0 ? Icons.volume_off : Icons.volume_up),
              color: Colors.white,
              size: 22),
          const SizedBox(width: 10),
          Expanded(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: val,
                      minHeight: 6,
                      color: accent,
                      backgroundColor: Colors.white24))),
          const SizedBox(width: 8),
          Text('${(val * 100).round()}',
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, bc) => Listener(
          onPointerDown: (_) => Gest.init(),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (d) {
              left = d.localPosition.dx < bc.maxWidth / 2;
              val = left ? Gest.bri : Gest.vol;
            },
            onVerticalDragUpdate: (d) {
              val = (val - d.delta.dy / (bc.maxHeight * .75)).clamp(0.0, 1.0);
              if (left) {
                Gest.setBri(val);
              } else {
                Gest.setVol(val);
              }
              _pop();
            },
            child: Stack(fit: StackFit.expand, children: [
              Positioned.fill(child: widget.child),
              if (show)
                Positioned.fill(
                    child: IgnorePointer(child: Center(child: _ind()))),
              if (widget.fitBtn)
                Positioned(
                  top: 10,
                  left: 10,
                  child: SafeArea(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: fitN,
                      builder: (_, st, __) => Tap(
                        onTap: () => setFit(!st),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                              color: Colors.black.withOpacity(.4),
                              borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.aspect_ratio,
                                size: 16, color: st ? accent : Colors.white70),
                            const SizedBox(width: 5),
                            Text(st ? 'Regang' : 'Asli',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: st ? accent : Colors.white70)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/* ===================== ANIMASI PERGANTIAN KONTEN ===================== */
Widget swapT(Widget c, Animation<double> a) => FadeTransition(
    opacity: a,
    child: SlideTransition(
        position: Tween(begin: const Offset(0, .04), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: c));

/// baris muncul berurutan (makin bawah makin telat sedikit)
Widget fxAt(int i, Widget c) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + min(i, 10) * 55),
      curve: Curves.easeOutCubic,
      builder: (_, v, ch) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: ch)),
      child: c,
    );

/* ===================== SLIDER OTOMATIS ===================== */
/// baris geser horizontal yang bergerak sendiri (tiap baris punya irama sendiri),
/// tetap bisa digeser tangan; berhenti sebentar saat disentuh
class AutoRow extends StatefulWidget {
  final int count;
  final double gap;
  final IndexedWidgetBuilder item;
  final bool auto;
  const AutoRow(
      {required this.count,
      required this.item,
      this.gap = 10,
      this.auto = true,
      super.key});
  @override
  State<AutoRow> createState() => _AutoRowS();
}

class _AutoRowS extends State<AutoRow> {
  static int _n = 0;
  final sc = ScrollController();
  Timer? _t;
  late final int period, delay;
  bool touch = false, back = false;
  int resumeAt = 0;

  @override
  void initState() {
    super.initState();
    final k = _n++;
    if (!widget.auto) {
      period = 0;
      delay = 0;
      return;
    }
    period = 3600 + (k * 730) % 2900; // 3,6 - 6,5 detik, beda tiap baris
    delay = 600 + (k * 1170) % 3200; // mulai bergantian
    _t = Timer(Duration(milliseconds: delay), () {
      _step();
      _t = Timer.periodic(Duration(milliseconds: period), (_) => _step());
    });
  }

  void _step() {
    if (!mounted || !sc.hasClients || touch) return;
    if (DateTime.now().millisecondsSinceEpoch < resumeAt) return;
    final ps = sc.position;
    final mx = ps.maxScrollExtent;
    if (mx <= 8) return;
    if (ps.pixels >= mx - 6) back = true;
    if (ps.pixels <= 6) back = false;
    if (back) {
      sc.animateTo(0,
          duration: const Duration(milliseconds: 1700),
          curve: Curves.easeInOutCubic);
    } else {
      final to = min(mx, ps.pixels + ps.viewportDimension * .55);
      sc.animateTo(to,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOutCubic);
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => touch = true,
        onPointerUp: (_) {
          touch = false;
          resumeAt = DateTime.now().millisecondsSinceEpoch + 3000;
        },
        onPointerCancel: (_) {
          touch = false;
          resumeAt = DateTime.now().millisecondsSinceEpoch + 3000;
        },
        child: ListView.separated(
          controller: sc,
          scrollDirection: Axis.horizontal,
          itemCount: widget.count,
          separatorBuilder: (_, __) => SizedBox(width: widget.gap),
          itemBuilder: widget.item,
        ),
      );
}

/* ===================== SATURASI VIDEO ===================== */
/// 100 = normal, 200 = warna dua kali lebih pekat
final satN = ValueNotifier<double>(100);

void setSat(double v) {
  satN.value = v;
  Store.p.setDouble('sat', v);
}

ColorFilter satFilter(double pct) {
  final s = pct / 100;
  const r = .2126, g = .7152, b = .0722;
  return ColorFilter.matrix([
    r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0, //
    0, 0, 0, 1, 0,
  ]);
}

Widget satWrap(Widget c) => ValueListenableBuilder<double>(
      valueListenable: satN,
      child: c,
      builder: (_, v, ch) =>
          v <= 100 ? ch! : ColorFiltered(colorFilter: satFilter(v), child: ch),
    );

/* ===================== UKURAN VIDEO ===================== */
/// false = asli (proporsi video dijaga), true = regang memenuhi layar tanpa terpotong
final fitN = ValueNotifier<bool>(false);

void setFit(bool v) {
  fitN.value = v;
  Store.p.setBool('fit', v);
}

Widget fitWrap(Widget child, double va) => ValueListenableBuilder<bool>(
      valueListenable: fitN,
      child: child,
      builder: (_, st, ch) {
        if (!st || va <= 0) return ch!;
        return LayoutBuilder(builder: (_, bc) {
          final cw = bc.maxWidth, chh = bc.maxHeight;
          if (!cw.isFinite || !chh.isFinite) return ch!;
          double w, h;
          if (va > cw / chh) {
            w = cw;
            h = cw / va;
          } else {
            h = chh;
            w = chh * va;
          }
          return Center(
            child: Transform.scale(
              scaleX: cw / w,
              scaleY: chh / h,
              child: SizedBox(width: w, height: h, child: ch),
            ),
          );
        });
      },
    );

/* ===================== CADANGAN DATA ===================== */
Future<bool> saveBackup(String name, String b64) async {
  try {
    return (await _nat.invokeMethod('saveFile', {'name': name, 'b64': b64})) ==
        true;
  } catch (_) {
    return false;
  }
}

Future<String?> pickBackup() async {
  try {
    return await _nat.invokeMethod<String>('pickFile');
  } catch (_) {
    return null;
  }
}

/// format cadangan: biner terkompres & disandikan (tidak bisa dibaca di aplikasi teks)
final _bk = utf8.encode('LesehanTV-cadangan-2026');
List<int> _mask(List<int> b) => [
      for (var i = 0; i < b.length; i++)
        b[i] ^ _bk[i % _bk.length] ^ ((i * 31 + 7) & 0xFF)
    ];

String packBackup(Map<String, dynamic> d) {
  final raw = gzip.encode(utf8.encode(jsonEncode(d)));
  return base64Encode([0x4C, 0x54, 0x56, 1, ..._mask(raw)]);
}

Map<String, dynamic>? unpackBackup(String b64) {
  try {
    final b = base64Decode(b64.trim());
    if (b.length < 6 || b[0] != 0x4C || b[1] != 0x54 || b[2] != 0x56) {
      return null;
    }
    final raw = gzip.decode(_mask(b.sublist(4)));
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(raw)));
  } catch (_) {
    return null;
  }
}

/// tidak memuat sumber video (src); hanya judul, kunci acak (hash), posisi, dan rekap
Map<String, dynamic> backupData() => {
      'app': 'LesehanTV',
      'jenis': 'cadangan',
      'v': 1,
      'dibuat': DateTime.now().toIso8601String(),
      'bookmark': Store.bms,
      'riwayat': Store.hist,
      'posisi': Store.jm('pos'),
      'ditonton': Store.jm('seen'),
      'rekap': {'detik': Store.watchSec, 'detail': Store.jm('wk')},
    };

Future<void> exportBackup(BuildContext c) async {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final name = 'LesehanTV-Cadangan-${d.year}${two(d.month)}${two(d.day)}.lesehantv';
  final ok = await saveBackup(name, packBackup(backupData()));
  if (c.mounted && ok) toast(c, '✅ Cadangan tersimpan: $name');
}

Future<void> importBackup(BuildContext c) async {
  final txt = await pickBackup();
  if (txt == null || !c.mounted) return;
  final d = unpackBackup(txt);
  if (d == null || d['app'] != 'LesehanTV' || d['jenis'] != 'cadangan') {
    toast(c, 'Bukan file cadangan LesehanTV');
    return;
  }
  final mode = await showDialog<String>(
    context: c,
    builder: (x) => AlertDialog(
      backgroundColor: isLight ? Colors.white : const Color(0xFF15151C),
      title: const Text('Pulihkan cadangan'),
      content: const Text(
          'Gabungkan dengan data di perangkat ini, atau ganti semuanya dengan isi cadangan?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(x), child: const Text('Batal')),
        OutlinedButton(
            onPressed: () => Navigator.pop(x, 'ganti'),
            child: const Text('Ganti')),
        FilledButton(
            onPressed: () => Navigator.pop(x, 'gabung'),
            child: const Text('Gabung')),
      ],
    ),
  );
  if (mode == null) return;
  final merge = mode == 'gabung';
  Map<String, dynamic> mp(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  int ni(dynamic v) => v is num ? v.toInt() : 0;

  final bm = <String>[
    if (merge) ...Store.bms,
    ...((d['bookmark'] as List?) ?? []).map((e) => e.toString()),
  ].toSet().toList();
  Store.p.setStringList('bms', bm);
  final inH = ((d['riwayat'] as List?) ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  final hs = <Map<String, dynamic>>[];
  for (final h in [if (merge) ...Store.hist, ...inH]) {
    if (!hs.any((x) => x['title'] == h['title'])) hs.add(h);
  }
  Store.sj('hist', hs.take(20).toList());
  final pos = merge ? Store.jm('pos') : <String, dynamic>{};
  mp(d['posisi']).forEach((k, v) {
    final cur = pos[k];
    final nt = v is Map ? ((v['t'] as num?) ?? 0) : 0;
    final ct = cur is Map ? ((cur['t'] as num?) ?? 0) : -1;
    if (nt > ct) pos[k] = v;
  });
  Store.sj('pos', pos);
  final seen = merge ? Store.jm('seen') : <String, dynamic>{};
  seen.addAll(mp(d['ditonton']));
  Store.sj('seen', seen);
  final rk = mp(d['rekap']);
  Store.p.setInt('lvsec',
      merge ? max(Store.watchSec, ni(rk['detik'])) : ni(rk['detik']));
  final wk = merge ? Store.jm('wk') : <String, dynamic>{};
  mp(rk['detail']).forEach((b, v) {
    final cur = mp(wk[b]);
    mp(v).forEach((k, s2) {
      cur[k] = max(ni(cur[k]), ni(s2));
    });
    wk[b] = cur;
  });
  Store.sj('wk', wk);
  App.refresh.value++;
  if (c.mounted) {
    toast(c, '✅ Dipulihkan: ${bm.length} bookmark, ${hs.length} riwayat');
  }
}

Widget backupCard(BuildContext c) => Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(14),
      decoration: cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💾 Cadangan LesehanTV',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Simpan bookmark, riwayat, dan rekap tontonan ke file, lalu pulihkan kapan saja (misal di HP baru).',
            style: TextStyle(color: mut, fontSize: 12, height: 1.5)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
                onPressed: () => exportBackup(c),
                icon: const Icon(Icons.upload_rounded),
                label: const Text('Ekspor')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
                onPressed: () => importBackup(c),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Impor')),
          ),
        ]),
      ]),
    );

/* ===================== SKELETON & PEMILIH TONTONAN ===================== */
class Skel extends StatefulWidget {
  final double? w, h;
  final double r;
  const Skel({this.w, this.h, this.r = 12, super.key});
  @override
  State<Skel> createState() => _SkelS();
}

class _SkelS extends State<Skel> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = (isLight ? Colors.black : Colors.white).withOpacity(.07);
    final hi = (isLight ? Colors.black : Colors.white).withOpacity(.2);
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) => Container(
        width: widget.w,
        height: widget.h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.r),
          gradient: LinearGradient(
              begin: Alignment(-2.5 + 4 * c.value, 0),
              end: Alignment(-1.5 + 4 * c.value, 0),
              colors: [base, hi, base]),
        ),
      ),
    );
  }
}

/// kerangka tampilan pemutar saat video dimuat
class PlayerSkel extends StatelessWidget {
  const PlayerSkel({super.key});
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        const Skel(r: 0),
        Center(
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.black.withOpacity(.35)),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white70, size: 38),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 12,
          child: Row(children: [
            const Skel(w: 34, h: 8, r: 4),
            const SizedBox(width: 10),
            const Expanded(child: Skel(h: 6, r: 3)),
            const SizedBox(width: 10),
            const Skel(w: 34, h: 8, r: 4),
          ]),
        ),
      ]);
}

Future<void> confirmClear(BuildContext c) async {
  final ya = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      backgroundColor: isLight ? Colors.white : const Color(0xFF15151C),
      title: const Text('Hapus semua riwayat?'),
      content: const Text(
          'Seluruh riwayat tontonan dan posisi terakhir akan dihapus. Tindakan ini tidak bisa dibatalkan.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false), child: const Text('Tidak')),
        FilledButton(
            onPressed: () => Navigator.pop(d, true), child: const Text('Ya, hapus')),
      ],
    ),
  );
  if (ya == true) Store.clearHist();
}

/// kartu ajakan di Beranda
Widget pickerCard(BuildContext c) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Tap(
        onTap: () => showModalBottomSheet(
            context: c,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const PickerSheet()),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                accent.withOpacity(.32),
                curTh.g2.withOpacity(.16)
              ]),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withOpacity(.5))),
          child: Row(children: [
            const Text('🎲', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Bingung mau nonton apa?',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('Biar kami pilihkan tontonan acak untukmu',
                    style: TextStyle(color: mut, fontSize: 12)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: accent),
          ]),
        ),
      ),
    );

class PickerSheet extends StatefulWidget {
  const PickerSheet({super.key});
  @override
  State<PickerSheet> createState() => _PickerS();
}

class _PickerS extends State<PickerSheet> {
  String cat = 'all';
  Group? g;
  bool spin = false;
  Timer? _t;
  final _r = Random();

  List<Group> _pool() => App.groups
      .where((x) => cat == 'all' || kind(x.cat) == cat)
      .toList();

  @override
  void initState() {
    super.initState();
    _roll();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _roll() {
    final l = _pool();
    _t?.cancel();
    if (l.isEmpty) {
      setState(() => g = null);
      return;
    }
    var n = 0;
    setState(() => spin = true);
    _t = Timer.periodic(const Duration(milliseconds: 90), (tm) {
      n++;
      Group x = l[_r.nextInt(l.length)];
      if (n >= 9 && l.length > 1) {
        while (x == g) {
          x = l[_r.nextInt(l.length)];
        }
      }
      if (!mounted) return tm.cancel();
      setState(() {
        g = x;
        if (n >= 9) spin = false;
      });
      if (n >= 9) tm.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final x = g;
    final cats = [
      ['all', 'Semua'],
      ['anime', 'Anime'],
      ['donghua', 'Donghua'],
      ['drama', 'Drama'],
      ['movie', 'Film'],
    ];
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.fromLTRB(
              18, 12, 18, 20 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
              color: (isLight ? Colors.white : const Color(0xFF0E0E14))
                  .withOpacity(.82),
              border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(.2)))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: fg.withOpacity(.25),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            const Text('🎲 Bingung mau nonton apa?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cats.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => chipB(cats[i][1], cat == cats[i][0], () {
                  cat = cats[i][0];
                  _roll();
                }),
              ),
            ),
            const SizedBox(height: 14),
            if (x == null)
              const Padding(
                  padding: EdgeInsets.all(30),
                  child: Text('Belum ada tontonan di kategori ini.'))
            else ...[
              AnimatedScale(
                scale: spin ? .94 : 1,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(fit: StackFit.expand, children: [
                    poster(x.thumb, radius: 18),
                    Positioned(top: 8, left: 8, child: pill(x.cat)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Text(x.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                  '${x.eps.length} Eps${x.gen.isEmpty ? '' : '  •  ${x.gen}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: mut, fontSize: 12)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: spin ? null : _roll,
                    icon: const Icon(Icons.casino_outlined),
                    label: const Text('Acak Lagi'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: spin
                        ? null
                        : () {
                            final nav = Navigator.of(context);
                            nav.pop();
                            openDetail(nav.context, x);
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Lihat'),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/* ===================== SPLASH ===================== */
const _spBg = Color(0xFF0C2340);
const _spGold1 = Color(0xFFE3A653);
const _spGold2 = Color(0xFFB8732A);

class LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final sh = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_spGold1, _spGold2])
        .createShader(Offset.zero & size);
    final sw = size.width * .028;
    canvas.drawCircle(
        c,
        r - sw,
        Paint()
          ..shader = sh
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw);
    Path tri(double k) {
      final cx = c.dx - r * .06, cy = c.dy;
      return Path()
        ..moveTo(cx - r * .33 * k, cy - r * .42 * k)
        ..lineTo(cx - r * .33 * k, cy + r * .42 * k)
        ..lineTo(cx + r * .46 * k, cy)
        ..close();
    }

    final big = tri(1);
    canvas.drawPath(
        big,
        Paint()
          ..shader = sh
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        big,
        Paint()
          ..shader = sh
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = r * .16);
    canvas.drawPath(tri(.5), Paint()..color = _spBg);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class SplashLogo extends StatelessWidget {
  const SplashLogo({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _spBg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutBack,
              builder: (_, v, __) => Opacity(
                opacity: v.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: .6 + .4 * v,
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                      BoxShadow(
                          color: _spGold2.withOpacity(.35 * v), blurRadius: 40)
                    ]),
                    child: CustomPaint(painter: LogoPainter()),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOut,
              builder: (_, v, ch) => Opacity(
                  opacity: v,
                  child: Transform.translate(
                      offset: Offset(0, (1 - v) * 14), child: ch)),
              child: Column(children: [
                Text.rich(
                  const TextSpan(children: [
                    TextSpan(
                        text: 'Lesehan',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                    TextSpan(
                        text: 'TV',
                        style: TextStyle(
                            color: _spGold1, fontWeight: FontWeight.w400)),
                  ]),
                  style: const TextStyle(fontSize: 34, letterSpacing: .5),
                ),
                const SizedBox(height: 6),
                const Text('Streaming Santai di Mana Saja',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                    minHeight: 3,
                    color: _spGold1,
                    backgroundColor: Colors.white12),
              ),
            ),
          ]),
        ),
      );
}

/// splash: memutar assets/splash.mp4 sekali; selesai -> masuk (menunggu data siap)
class Splash extends StatefulWidget {
  final VoidCallback onDone;
  const Splash({required this.onDone, super.key});
  @override
  State<Splash> createState() => _SplashS();
}

class _SplashS extends State<Splash> {
  VideoPlayerController? v;
  bool fin = false;

  @override
  void initState() {
    super.initState();
    final c = splashCtl;
    if (c != null && c.value.isInitialized) {
      v = c;
      c.setVolume(0);
      c.addListener(_tick);
      c.play();
    } else {
      Future.delayed(const Duration(milliseconds: 1200), _end);
    }
  }

  void _tick() {
    final x = v!.value;
    if (x.hasError) return _end();
    if (x.isInitialized &&
        x.duration.inMilliseconds > 0 &&
        x.position >= x.duration - const Duration(milliseconds: 200)) {
      _end();
    }
  }

  void _end() {
    if (fin) return;
    fin = true;
    widget.onDone();
  }

  @override
  void dispose() {
    v?.removeListener(_tick);
    v?.dispose();
    splashCtl = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = v;
    if (c == null) return const Scaffold(backgroundColor: Colors.black);
    final s = c.value.size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: s.width, height: s.height, child: VideoPlayer(c)),
        ),
      ),
    );
  }
}

/* ===================== APLIKASI ===================== */
/// video splash dimuat sebelum tampilan pertama, jadi langsung main tanpa loading lain
VideoPlayerController? splashCtl;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final si = Store.init();
  try {
    final c = VideoPlayerController.asset('assets/splash.mp4');
    splashCtl = c;
    await c.initialize().timeout(const Duration(seconds: 3));
  } catch (_) {
    splashCtl?.dispose();
    splashCtl = null;
  }
  await si;
  final sv = Store.p.getString('theme');
  curTh = themes.firstWhere((t) => t.id == sv, orElse: () => themes[0]);
  themeId.value = curTh.id;
  satN.value = (Store.p.getDouble('sat') ?? 100).clamp(100.0, 200.0);
  fitN.value = Store.p.getBool('fit') ?? false;
  runApp(const LesehanApp());
  if (Store.p.getBool('notif') ?? true) syncNotif(true);
}

/// notifikasi judul baru (cek berkala di latar belakang oleh kode native)
Future<void> syncNotif(bool on) async {
  try {
    await _nat.invokeMethod('setNotif', {
      'on': on,
      'api': api,
      'key': String.fromCharCodes(_ak),
    });
  } catch (_) {}
}

class NotifRow extends StatefulWidget {
  const NotifRow({super.key});
  @override
  State<NotifRow> createState() => _NotifRowState();
}

class _NotifRowState extends State<NotifRow> {
  bool on = Store.p.getBool('notif') ?? true;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
            color: fg.withOpacity(.08), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(Icons.notifications_active_outlined, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Notifikasi judul baru',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('Dicek berkala di latar belakang',
                      style: TextStyle(color: mut, fontSize: 11)),
                ]),
          ),
          Switch(
            value: on,
            onChanged: (v) {
              setState(() => on = v);
              Store.p.setBool('notif', v);
              syncNotif(v);
            },
          ),
        ]),
      );
}

/* ===================== PREMIUM + DIRECT LINK ===================== */
const directLink = 'https://uplcm.com/4/12112706';
const premBuy = 'https://saweria.co/AKUINGINTERKENAL';
const premChat = 'https://t.me/+U0ocipINk6MzYmE1';

class Prem {
  static bool fs = false; // pemutar sedang layar penuh
  static bool skip = false; // ketukan pada kartu premium tidak dihitung
  static bool _sk = false;
  static int _n = 0, _ts = 0;
  static Offset? _p;

  static String get _today {
    final t = DateTime.now().toUtc().add(const Duration(hours: 7));
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  static String get until => Store.p.getString('prem_u') ?? '';
  static bool get on => until.isNotEmpty && until.compareTo(_today) >= 0;

  static String get dev {
    var d = Store.p.getString('prem_dev');
    if (d == null || d.isEmpty) {
      final r = Random();
      d = List.generate(16, (_) => r.nextInt(36).toRadixString(36)).join();
      Store.p.setString('prem_dev', d);
    }
    return d;
  }

  static const _err = {
    'invalid': 'Kode tidak ditemukan',
    'expired': 'Kode sudah kedaluwarsa',
    'device': 'Kode sudah dipakai di batas jumlah perangkat',
    'coba': 'Terlalu banyak percobaan, coba lagi nanti',
    'sibuk': 'Server sibuk, coba lagi sebentar',
  };

  /// kembalikan null kalau berhasil, atau pesan kesalahan
  static Future<String?> activate(String code) async {
    code = code.trim();
    if (code.length < 4) return 'Masukkan kode premium';
    try {
      final r = await http
          .get(Uri.parse(apiQ(
              'lic=${Uri.encodeQueryComponent(code)}&dev=${Uri.encodeQueryComponent(dev)}')))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map && d['ok'] == 1 && d['u'] != null) {
        Store.p.setString('prem_c', code);
        Store.p.setString('prem_u', d['u'].toString());
        Store.p.setInt('prem_v', DateTime.now().millisecondsSinceEpoch);
        App.refresh.value++;
        return null;
      }
      return _err[d is Map ? '${d['err']}' : ''] ?? 'Kode tidak valid';
    } catch (_) {
      return 'Tidak bisa terhubung ke server';
    }
  }

  static void off() {
    Store.p.remove('prem_c');
    Store.p.remove('prem_u');
    Store.p.remove('prem_v');
    App.refresh.value++;
  }

  /// periksa ulang ke server tiap 6 jam; kalau kode dicabut, premium dimatikan
  static Future<void> recheck() async {
    try {
      final c = Store.p.getString('prem_c');
      if (c == null || c.isEmpty) return;
      final v = Store.p.getInt('prem_v') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - v < 6 * 3600 * 1000) return;
      final r = await http
          .get(Uri.parse(apiQ(
              'lic=${Uri.encodeQueryComponent(c)}&dev=${Uri.encodeQueryComponent(dev)}')))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map && d['ok'] == 1 && d['u'] != null) {
        Store.p.setString('prem_u', d['u'].toString());
        Store.p.setInt('prem_v', DateTime.now().millisecondsSinceEpoch);
        App.refresh.value++;
      } else if (d is Map &&
          (d['err'] == 'invalid' ||
              d['err'] == 'expired' ||
              d['err'] == 'device')) {
        off();
      }
    } catch (_) {}
  }

  /// hitung ketukan (bukan geseran): tiap 3 ketukan -> direct link (akun gratis)
  static void down(PointerDownEvent e) {
    _p = e.position;
    _ts = e.timeStamp.inMilliseconds;
    _sk = skip;
    skip = false;
  }

  static void up(PointerUpEvent e) {
    final p = _p;
    _p = null;
    if (p == null || _sk) return;
    if ((e.position - p).distance > 24) return;
    if (e.timeStamp.inMilliseconds - _ts > 500) return;
    if (on || fs) return;
    if (++_n >= 3) {
      _n = 0;
      openUrl(directLink);
    }
  }
}

class PremiumCard extends StatefulWidget {
  const PremiumCard({super.key});
  @override
  State<PremiumCard> createState() => _PremiumCardS();
}

class _PremiumCardS extends State<PremiumCard> {
  final ctl = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => busy = true);
    final err = await Prem.activate(ctl.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (err == null) {
      ctl.clear();
      toast(context, '✅ Premium aktif, bebas gangguan');
    } else {
      toast(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = Prem.on;
    return Listener(
      onPointerDown: (_) => Prem.skip = true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: cardBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(on ? '⭐ Premium Aktif' : '⭐ Premium · Bebas Gangguan',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (on) ...[
            Text('Tanpa direct link sampai ${Prem.until}.',
                style: TextStyle(color: mut, fontSize: 12)),
            const SizedBox(height: 8),
            TextButton(
                onPressed: () {
                  Prem.off();
                  setState(() {});
                },
                child: const Text('Keluar dari Premium')),
          ] else ...[
            Text(
                'Akun gratis: tiap 3 ketukan membuka tab iklan. Masukkan kode premium untuk menghilangkannya.',
                style: TextStyle(color: mut, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              enabled: !busy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'LTV-XXXXX-XXXXX'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton(
                    onPressed: busy ? null : _go,
                    child: Text(busy ? 'Memeriksa...' : 'Aktifkan')),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: () => openUrl(premBuy),
                  child: const Text('Beli Kode')),
            ]),
            TextButton(
                onPressed: () => openUrl(premChat),
                child: const Text('Tanya / konfirmasi pembayaran')),
          ],
        ]),
      ),
    );
  }
}

class LesehanApp extends StatelessWidget {
  const LesehanApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: themeId,
        builder: (_, __) => MaterialApp(
          key: ValueKey(themeId.value),
          title: 'LesehanTV',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          builder: (c, child) => Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: Prem.down,
              onPointerUp: Prem.up,
              child: child ?? const SizedBox.shrink()),
          home: const Root(),
        ),
      );
}

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

bool _splashDone = false;

class _RootState extends State<Root> {
  int i = App.tab.value;
  void _tabL() {
    if (mounted) setState(() => i = App.tab.value);
    if (App.tab.value <= 1) App.loadStats();
  }

  @override
  void initState() {
    super.initState();
    App.tab.addListener(_tabL);
    App.refresh.addListener(_chkUpd);
    if (!App.started) {
      App.started = true;
      App.load();
    }
  }

  @override
  void dispose() {
    App.tab.removeListener(_tabL);
    App.refresh.removeListener(_chkUpd);
    super.dispose();
  }

  /// update wajib: kalau build di HP lebih kecil dari versi_min di sheet "Update"
  /// (kosong/0 = tidak ada update wajib; build lama tanpa nomor tidak terpengaruh)
  void _chkUpd() {
    final u = App.upd;
    if (u == null || App.updShown || !mounted) return;
    final mn = u['min'] as int;
    if (kBuild <= 0 || mn <= 0 || kBuild >= mn) return;
    App.updShown = true;
    final force = u['force'] == true;
    final url = u['url'] as String;
    final msg = (u['msg'] as String).isEmpty
        ? 'Versi baru LesehanTV sudah tersedia. Perbarui aplikasi untuk melanjutkan.'
        : u['msg'] as String;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: !force,
        builder: (c) => PopScope(
          canPop: !force,
          child: AlertDialog(
            backgroundColor: isLight ? Colors.white : const Color(0xFF15151C),
            title: const Text('Pembaruan tersedia'),
            content: Text('$msg\n\nVersi kamu: $kBuild  •  Terbaru: $mn'),
            actions: [
              if (!force)
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Nanti')),
              FilledButton(
                  onPressed: () {
                    if (url.isNotEmpty) openUrl(url);
                  },
                  child: const Text('Perbarui')),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _askExit() async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: isLight ? Colors.white : const Color(0xFF15151C),
        title: const Text('Keluar aplikasi?'),
        content: const Text('Yakin ingin keluar dari LesehanTV?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Tidak')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('Ya')),
        ],
      ),
    );
    if (ya == true) SystemNavigator.pop();
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
      barrierColor: Colors.transparent,
      builder: (c) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: ColoredBox(
          color: Colors.black.withOpacity(.4),
          child: Listener(
              onPointerDown: (_) => Prem.skip = true,
              child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (ok) openUrl(lk);
          Navigator.pop(c);
        },
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
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
                  const SizedBox(height: 16),
                  const Text('ketuk di mana saja untuk menutup',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              ),
            ),
          ),
        ),
      ),
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: App.refresh,
        builder: (_, __, ___) {
          if (!_splashDone || (!App.loaded && App.error == null)) {
            return Splash(onDone: () {
              _splashDone = true;
              if (mounted) setState(() {});
            });
          }
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
            body = TabSwitch(index: i, children: [
              HomeTab(),
              PopularTab(),
              CatalogTab(),
              LibraryTab(),
              ProfileTab(),
            ]);
          }
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (i != 0) {
                App.tab.value = 0;
              } else {
                _askExit();
              }
            },
            child: Scaffold(
            body: Stack(children: [
              const Positioned.fill(child: GlowBg()),
              SafeArea(bottom: false, child: body),
              if (App.loaded)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 14 + MediaQuery.of(context).padding.bottom,
                  child: FloatNav(i, (v) => App.tab.value = v),
                ),
            ]),)
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
        child: AutoRow(
          count: top.length,
          gap: 8,
          auto: false,
          item: (_, i) => t10Item(context, i, top[i].key, top[i].value),
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
    final latest = [...App.groups]..sort(newer);
    final kinds = [
      ['anime', 'Anime'],
      ['donghua', 'Donghua'],
      ['drama', 'Drama'],
      ['movie', 'Film'],
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 12, 14, navPad),
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
        if (App.info.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Marquee(),
        ],
        const SizedBox(height: 14),
        if (hero.isNotEmpty)
          SizedBox(
            height: 210,
            child: PageView(
              controller: pc,
              onPageChanged: (v) => setState(() => heroI = v),
              children: hero
                  .map((g) => Tap(
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
        pickerCard(context),
        if (hs.isNotEmpty)
          section('Lanjutkan Nonton', hs.map((e) => ResumeCard(e)).toList(),
              auto: false,
              more: () => App.tab.value = 3),
        top10(),
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
    return Tap(
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
    final top = l.take(10).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 14, 14, navPad),
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
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          transitionBuilder: swapT,
          child: Column(
              key: ValueKey('$week-${top.isEmpty}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
        if (top.isEmpty)
          Padding(
              padding: const EdgeInsets.all(30),
              child: Center(
                  child: App.statsOk
                      ? const Text('Belum ada data penonton.')
                      : const Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Memuat data populer…'),
                        ])))
        else
          for (var i = 0; i < top.length; i++)
            fxAt(i, Tap(
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
            )),
              ]),
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
      ..sort(newer);
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            transitionBuilder: swapT,
            child: KeyedSubtree(
              key: ValueKey(cat),
              child: l.isEmpty
                  ? const Center(child: Text('Tidak ada konten yang cocok.'))
                  : LayoutBuilder(
                      builder: (_, c) => GridView.builder(
                        padding: EdgeInsets.only(bottom: navPad),
                        itemCount: l.length,
                        gridDelegate: gridD(c.maxWidth),
                        itemBuilder: (_, i) => GroupCard(l[i]),
                      ),
                    ),
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
      padding: EdgeInsets.fromLTRB(14, 14, 14, navPad),
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
                onPressed: () => confirmClear(context),
                child: const Text('Hapus Semua')),
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
              itemBuilder: (_, i) => Stack(children: [
                ResumeCard(hs[i]),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Store.removeHist(hs[i].key),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          size: 15, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        backupCard(context),
      ],
    );
  }
}

/* ===================== PROFIL ===================== */
class ProfileTab extends StatelessWidget {
  ProfileTab({super.key});

  static const _hr = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  List<MapEntry<String, int>> _top(String bucket, [int n = 5]) {
    final l = Store.wk(bucket).entries.where((e) => e.value > 0).toList();
    l.sort((x, y) => y.value.compareTo(x.value));
    return l.take(n).toList();
  }

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      );

  Widget _stat(String big, String small) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: fg.withOpacity(.08),
              borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(big,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: accent)),
            Text(small, style: TextStyle(color: mut, fontSize: 11)),
          ]),
        ),
      );

  void _shareRecap(BuildContext context) {
    final total = Store.watchSec;
    final days = Store.wk('d');
    final now = DateTime.now();
    var streak = 0;
    var d = now;
    if ((days[Store.dayKey(d)] ?? 0) == 0) d = d.subtract(const Duration(days: 1));
    while ((days[Store.dayKey(d)] ?? 0) > 0) {
      streak++;
      d = d.subtract(const Duration(days: 1));
    }
    final wk = <MapEntry<String, int>>[];
    for (var i = 6; i >= 0; i--) {
      final x = now.subtract(Duration(days: i));
      wk.add(MapEntry(_hr[x.weekday - 1], days[Store.dayKey(x)] ?? 0));
    }
    final big = total >= 3600 ? '${total ~/ 3600}' : '${(total / 60).round()}';
    final unit = total >= 3600 ? 'jam ${(total % 3600) ~/ 60} mnt' : 'menit';
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: RecapShare(
          big: big,
          unit: unit,
          streak: streak,
          nTitles: Store.wk('t').length,
          wk: wk,
          wSum: wk.fold<int>(0, (m, e) => m + e.value),
          titles: [for (final e in _top('t', 3)) e.key],
          genres: [for (final e in _top('g', 3)) e.key],
        ),
      ),
    );
  }

  Widget _recap() {
    final total = Store.watchSec;
    final days = Store.wk('d');
    final titles = Store.wk('t');
    final now = DateTime.now();

    // streak: hari berturut-turut (hari ini yang masih kosong belum memutus)
    var streak = 0;
    var d = now;
    if ((days[Store.dayKey(d)] ?? 0) == 0) d = d.subtract(const Duration(days: 1));
    while ((days[Store.dayKey(d)] ?? 0) > 0) {
      streak++;
      d = d.subtract(const Duration(days: 1));
    }

    // 7 hari terakhir
    final wk = <MapEntry<String, int>>[];
    for (var i = 6; i >= 0; i--) {
      final x = now.subtract(Duration(days: i));
      wk.add(MapEntry(_hr[x.weekday - 1], days[Store.dayKey(x)] ?? 0));
    }
    final wMax = wk.fold<int>(1, (m, e) => max(m, e.value));
    final wSum = wk.fold<int>(0, (m, e) => m + e.value);

    final tt = _top('t');
    final tg2 = _top('g');
    // kategori favorit: gabungkan waktu nonton per jenis (anime/donghua/film/drama)
    const katNama = {
      'anime': 'Anime',
      'donghua': 'Donghua',
      'movie': 'Film',
      'drama': 'Drama'
    };
    final katSum = <String, int>{};
    Store.wk('c').forEach((c, v) {
      final k = kind(c);
      katSum[k] = (katSum[k] ?? 0) + v;
    });
    final kats = (katSum.entries.where((e) => e.value > 0).toList()
          ..sort((x, y) => y.value.compareTo(x.value)))
        .take(3)
        .map((e) => MapEntry(katNama[e.key] ?? e.key, e.value))
        .toList();
    final big = total >= 3600 ? '${total ~/ 3600}' : '${(total / 60).round()}';
    final unit = total >= 3600
        ? 'jam ${(total % 3600) ~/ 60} mnt'
        : 'menit';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withOpacity(.32), curTh.g2.withOpacity(.16)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withOpacity(.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🎧 Rekap Tontonanmu',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('Dicatat otomatis di perangkat ini, tanpa akun.',
            style: TextStyle(color: mut, fontSize: 12)),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(big,
              style: TextStyle(
                  fontSize: 52,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: accent)),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('$unit\nwaktu nonton',
                style: TextStyle(color: mut, fontSize: 12, height: 1.3)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _stat('🔥 $streak', 'hari beruntun'),
          const SizedBox(width: 10),
          _stat('🎬 ${titles.length}', 'judul ditonton'),
        ]),
        if (total > 0 && titles.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
                'Daftar judul & genre teratas mulai terisi dari tontonan berikutnya.',
                style: TextStyle(color: mut, fontSize: 12)),
          ),
        if (total == 0)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text('Belum ada tontonan. Putar video dan rekapmu muncul di sini.',
                style: TextStyle(color: mut, fontSize: 12)),
          ),
        _head('Minggu ini · ${fmtDur(wSum)}'),
        SizedBox(
          height: 92,
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final e in wk)
                  Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: 18,
                            height: e.value == 0 ? 4 : 8 + 60 * e.value / wMax,
                            decoration: BoxDecoration(
                                color: e.value == 0
                                    ? fg.withOpacity(.12)
                                    : accent,
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          const SizedBox(height: 6),
                          Text(e.key,
                              style: TextStyle(color: mut, fontSize: 10)),
                        ]),
                  ),
              ]),
        ),
        if (tt.isNotEmpty) ...[
          _head('Judul teratas'),
          for (var i = 0; i < tt.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(
                    width: 22,
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: i == 0 ? 20 : 15,
                            fontWeight: FontWeight.w800,
                            color: i == 0 ? accent : mut))),
                SizedBox(
                    width: 46,
                    height: 46,
                    child: poster(App.gm[tt[i].key]?.thumb ?? '', radius: 10)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tt[i].key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                              value: tt[i].value / tt[0].value,
                              minHeight: 5,
                              color: accent,
                              backgroundColor: fg.withOpacity(.1)),
                        ),
                        const SizedBox(height: 2),
                        Text(fmtDur(tt[i].value),
                            style: TextStyle(color: mut, fontSize: 11)),
                      ]),
                ),
              ]),
            ),
        ],
        if (kats.isNotEmpty) ...[
          _head('Kategori favorit'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < kats.length; i++)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: accent.withOpacity(i == 0 ? .3 : .12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withOpacity(.6))),
                child: Text('${kats[i].key} · ${fmtDur(kats[i].value)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500)),
              ),
          ]),
        ],
        if (tg2.isNotEmpty) ...[
          _head('Genre teratas'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < tg2.length; i++)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: accent.withOpacity(i == 0 ? .3 : .12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withOpacity(.6))),
                child: Text('${tg2[i].key} · ${fmtDur(tg2[i].value)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500)),
              ),
          ]),
        ],
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
          LayoutBuilder(builder: (_, bc) {
            final w = (bc.maxWidth - 16) / 3;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in themes)
                Tap(
                  onTap: () => setTheme(t.id),
                  child: Container(
                    width: w,
                    height: w / 2.4,
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
            ]);
          }),
        ]),
      );

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(14, 20, 14, navPad + 4),
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(.45), blurRadius: 26)
                  ]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('assets/logo_icon.jpg', fit: BoxFit.cover),
              ),
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
          Tap(
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
          const PremiumCard(),
          _recap(),
          Tap(
            onTap: () => _shareRecap(context),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: accent.withOpacity(.6))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.ios_share, size: 18, color: accent),
                const SizedBox(width: 8),
                const Text('Bagikan Rekap',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
          const NotifRow(),
          _theme(),
          const SizedBox(height: 8),
          Tap(
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


/* ===================== BAGIKAN REKAP (gambar) ===================== */
class RecapShare extends StatefulWidget {
  final String big, unit;
  final int streak, nTitles, wSum;
  final List<MapEntry<String, int>> wk;
  final List<String> titles, genres;
  const RecapShare({
    required this.big,
    required this.unit,
    required this.streak,
    required this.nTitles,
    required this.wk,
    required this.wSum,
    required this.titles,
    required this.genres,
    super.key,
  });
  @override
  State<RecapShare> createState() => _RecapShareState();
}

class _RecapShareState extends State<RecapShare> {
  final _k = GlobalKey();
  bool busy = false;

  Future<void> _go() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final b = _k.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 3);
      final bd = await img.toByteData(format: ImageByteFormat.png);
      final f = File('${Directory.systemTemp.path}/rekap_lesehantv.png');
      await f.writeAsBytes(bd!.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')],
          text: 'Rekap tontonanku di LesehanTV 🎧');
    } catch (_) {
      if (mounted) toast(context, 'Gagal membagikan rekap');
    }
    if (mounted) setState(() => busy = false);
  }

  static const _w = Colors.white;

  @override
  Widget build(BuildContext context) {
    final wMax = widget.wk.fold<int>(1, (m, e) => max(m, e.value));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      RepaintBoundary(
        key: _k,
        child: Container(
          width: 320,
          height: 470,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF0B1220), accent.withOpacity(.75)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/logo_icon.jpg',
                    width: 28, height: 28, fit: BoxFit.cover),
              ),
              const SizedBox(width: 8),
              const Text('LesehanTV',
                  style: TextStyle(
                      color: _w, fontSize: 15, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 14),
            const Text('🎧 Rekap Tontonanku',
                style: TextStyle(
                    color: _w, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(widget.big,
                  style: const TextStyle(
                      color: _w,
                      fontSize: 54,
                      height: 1,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${widget.unit}\nwaktu nonton',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12, height: 1.3)),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: Text('🔥 ${widget.streak} hari beruntun',
                      style: const TextStyle(color: _w, fontSize: 13))),
              Expanded(
                  child: Text('🎬 ${widget.nTitles} judul',
                      style: const TextStyle(color: _w, fontSize: 13))),
            ]),
            const SizedBox(height: 14),
            Text('Minggu ini · ${fmtDur(widget.wSum)}',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SizedBox(
              height: 70,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final e in widget.wk)
                      Expanded(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                width: 16,
                                height:
                                    e.value == 0 ? 4 : 8 + 40 * e.value / wMax,
                                decoration: BoxDecoration(
                                    color: e.value == 0
                                        ? Colors.white24
                                        : _w,
                                    borderRadius: BorderRadius.circular(5)),
                              ),
                              const SizedBox(height: 4),
                              Text(e.key,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 9)),
                            ]),
                      ),
                  ]),
            ),
            if (widget.titles.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Judul teratas',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (var i = 0; i < widget.titles.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('${i + 1}. ${widget.titles[i]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _w, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
            ],
            if (widget.genres.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Genre favorit: ${widget.genres.join(' · ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
              ),
            const Spacer(),
            const Text('Nonton santai di LesehanTV',
                style: TextStyle(color: Colors.white54, fontSize: 10)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        FilledButton.icon(
          onPressed: busy ? null : _go,
          icon: const Icon(Icons.ios_share, size: 18),
          label: Text(busy ? 'Menyiapkan…' : 'Bagikan'),
        ),
        const SizedBox(width: 10),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup')),
      ]),
    ]);
  }
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
                  Tap(
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
                return Tap(
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
  bool _fs = false, _wasPlaying = false, _webHeld = false;
  int _holds = 0;
  final _wvKey = GlobalKey(), _chKey = GlobalKey();
  static final List<_PlayerPageState> stack = [];
  static _PlayerPageState? get top => stack.isEmpty ? null : stack.last;

  bool _pb = Store.p.getBool('popblock') ?? true;
  bool _web1 = false;
  int _loadedAt = 0;
  static const _popJs =
      r'''(function(){try{window.open=function(){return null};}catch(e){}})();''';
  static String _rd(String h) {
    final p = h.split('.');
    return p.length <= 2 ? h : p.sublist(p.length - 2).join('.');
  }

  static const _fsJs = r'''(function(){if(window.__lfs)return;window.__lfs=1;function f(){var e=document.fullscreenElement||document.webkitFullscreenElement;LesehanFS.postMessage(e?'1':'0');}document.addEventListener('fullscreenchange',f);document.addEventListener('webkitfullscreenchange',f);})();''';

  /// jeda video saat halaman lain (Detail/pemutar lain) menutupi pemutar ini
  void hold() {
    if (_holds++ > 0) return;
    _wasPlaying = vc?.value.isPlaying ?? false;
    vc?.pause();
    if (wc != null) {
      _webHeld = true;
      wc!.loadHtmlString('<html><body style="background:#000"></body></html>');
    }
  }

  void release() {
    if (_holds == 0) return;
    if (--_holds > 0 || !mounted) return;
    if (_wasPlaying) vc?.play();
    if (_webHeld) {
      _webHeld = false;
      start();
    }
  }

  /// terapkan saturasi & ukuran ke halaman embed (CSS disuntikkan)
  void _applyWeb() {
    final w = wc;
    if (w == null) return;
    final sx = satN.value / 100;
    final css = '${fitN.value ? 'video{object-fit:fill!important}' : ''}'
        '${sx > 1 ? 'video,iframe{filter:saturate($sx)!important}' : ''}';
    w
        .runJavaScript(
            "(function(){var s=document.getElementById('lsty');if(!s){s=document.createElement('style');s.id='lsty';(document.head||document.documentElement).appendChild(s);}s.textContent='$css';})();")
        .catchError((_) {});
  }

  void _enterFs() {
    if (_fs || !mounted) return;
    Prem.fs = true;
    setState(() => _fs = true);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFs() {
    if (!_fs) return;
    Prem.fs = false;
    if (mounted) setState(() => _fs = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  void initState() {
    super.initState();
    ep = widget.ep;
    stack.add(this);
    satN.addListener(_applyWeb);
    fitN.addListener(_applyWeb);
    WidgetsBinding.instance.addObserver(this);
    _wt = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_resumed || _holds > 0 || loading || err != null) return;
      final playing = vc != null ? vc!.value.isPlaying : wc != null;
      if (!playing) return;
      Store.addWatch(ep, 5);
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
          routePageBuilder: (ctx, a, sa, prov) => AnimatedBuilder(
              animation: a,
              builder: (_, __) => Scaffold(
                  resizeToAvoidBottomInset: false,
                  backgroundColor: Colors.black,
                  body: GestLayer(
                      fitBtn: true,
                      child: satWrap(fitWrap(
                          prov,
                          c.value.aspectRatio == 0
                              ? 16 / 9
                              : c.value.aspectRatio))))),
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
        _web1 = false;
        _loadedAt = 0;
        wc = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..addJavaScriptChannel('LesehanFS', onMessageReceived: (m) {
            if (!mounted) return;
            if (m.message == '1') {
              _enterFs();
            } else {
              _exitFs();
            }
          })
          ..setNavigationDelegate(NavigationDelegate(
              onPageStarted: (_) {
                if (_pb) wc?.runJavaScript(_popJs).catchError((_) {});
              },
              onPageFinished: (_) {
                _loadedAt = DateTime.now().millisecondsSinceEpoch;
                _web1 = true;
                wc?.runJavaScript(_fsJs).catchError((_) {});
                if (_pb) wc?.runJavaScript(_popJs).catchError((_) {});
                _applyWeb();
              },
              onNavigationRequest: (r) {
                final u = Uri.tryParse(r.url);
                if (u == null || (u.scheme != 'http' && u.scheme != 'https')) {
                  return NavigationDecision.prevent;
                }
                if (!r.isMainFrame || !_pb) return NavigationDecision.navigate;
                // pengalihan awal server (sebelum halaman selesai / 3 detik pertama) diizinkan
                final now = DateTime.now().millisecondsSinceEpoch;
                if (!_web1 || now - _loadedAt < 3000) {
                  return NavigationDecision.navigate;
                }
                return (_rd(u.host) == _rd(host) || r.url == url)
                    ? NavigationDecision.navigate
                    : NavigationDecision.prevent;
              }))
          ..loadRequest(Uri.parse(url));
        final pf = wc!.platform;
        if (pf is AndroidWebViewController) {
          pf.setCustomWidgetCallbacks(
            onShowCustomWidget: (Widget w, void Function() hide) {
              if (!mounted) return;
              setState(() {
                _cw = w;
                _cwHide = hide;
              });
              _enterFs();
            },
            onHideCustomWidget: () {
              if (!mounted) return;
              setState(() {
                _cw = null;
                _cwHide = null;
              });
              _exitFs();
            },
          );
        }
        Store.markSeen(ep.key);
      }
      Store.touchHist(ep);
    } catch (_) {
      if (tk == _tok) err = 'Video gagal diputar';
    }
    if (tk == _tok && mounted) {
      setState(() => loading = false);
      if (_holds > 0) vc?.pause();
    }
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
    stack.remove(this);
    satN.removeListener(_applyWeb);
    fitN.removeListener(_applyWeb);
    WidgetsBinding.instance.removeObserver(this);
    _tok++;
    _release();
    Prem.fs = false;
    if (_fs) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    Gest.resetBri();
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
    if (loading) return const PlayerSkel();
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
    if (cc != null) {
      final va = vc?.value.aspectRatio ?? 0;
      return GestLayer(
          child: satWrap(fitWrap(
              Chewie(key: _chKey, controller: cc!), va == 0 ? 16 / 9 : va)));
    }
    if (wc != null) return _web();
    return const SizedBox.shrink();
  }

  Widget _web() => Stack(fit: StackFit.expand, children: [
        GestLayer(child: WebViewWidget(key: _wvKey, controller: wc!)),
        Positioned(
          top: 6,
          right: 6,
          child: Tap(
            onTap: _fs ? _exitFs : _enterFs,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: Colors.black54, borderRadius: BorderRadius.circular(10)),
              child: Icon(_fs ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white, size: 22),
            ),
          ),
        ),
      ]);

  Widget _infoList(Group? g, List<Ep> all, List<String> names) =>
      ListView(padding: const EdgeInsets.all(14), children: [
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
                Tap(
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
      ]);

  Widget? _cw;
  VoidCallback? _cwHide;

  @override
  Widget build(BuildContext context) {
    final core = _core(context);
    if (_cw == null) return core;
    // layar penuh bawaan embed: ditampilkan di sini agar gestur volume/kecerahan tetap jalan
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cwHide?.call();
      },
      child: Stack(fit: StackFit.expand, children: [
        core,
        Positioned.fill(
          child: Material(
            color: Colors.black,
            child: GestLayer(child: _cw!),
          ),
        ),
      ]),
    );
  }

  Widget _core(BuildContext context) {
    if (_fs && wc != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitFs();
        },
        child: Scaffold(backgroundColor: Colors.black, body: _web()),
      );
    }
    final g = App.gm[ep.title];
    final all = g?.eps ?? [ep];
    final names = [
      ep.svn.isEmpty ? 'Server 1' : ep.svn,
      ...ep.extra.map((x) => x.name)
    ];
    final land = MediaQuery.of(context).orientation == Orientation.landscape;
    // tombol kembali melayang di atas pemutar (judul dihapus agar pemutar naik)
    final back = Positioned(
      top: 6,
      left: 6,
      child: Tap(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.black45),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
        ),
      ),
    );
    final sat = Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
      child: Column(children: [
        ValueListenableBuilder<bool>(
          valueListenable: fitN,
          builder: (_, st, __) => Row(children: [
            Icon(Icons.aspect_ratio, size: 18, color: accent),
            const SizedBox(width: 8),
            Text('Ukuran', style: TextStyle(color: mut, fontSize: 12)),
            const SizedBox(width: 12),
            chipB('Asli', !st, () => setFit(false)),
            const SizedBox(width: 8),
            chipB('Regang', st, () => setFit(true)),
          ]),
        ),
        if (wc != null)
          Row(children: [
            Icon(Icons.shield_outlined, size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Blokir pop-up iklan (disarankan)',
                  style: TextStyle(color: mut, fontSize: 12)),
            ),
            Switch(
              value: _pb,
              onChanged: (v) {
                setState(() => _pb = v);
                Store.p.setBool('popblock', v);
                start();
              },
            ),
          ]),
        ValueListenableBuilder<double>(
          valueListenable: satN,
          builder: (_, v, __) => Row(children: [
            Icon(Icons.palette_outlined, size: 18, color: accent),
            const SizedBox(width: 8),
            Text('Saturasi', style: TextStyle(color: mut, fontSize: 12)),
            Expanded(
              child: Slider(
                min: 100,
                max: 200,
                divisions: 20,
                value: v.clamp(100.0, 200.0),
                onChanged: setSat,
              ),
            ),
            SizedBox(
                width: 40,
                child: Text('${v.round()}%',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12))),
            IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Normal',
                icon: const Icon(Icons.restart_alt, size: 20),
                onPressed: () => setSat(100)),
          ]),
        ),
      ]),
    );
    final info = _infoList(g, all, names);
    if (land) {
      // lanskap: kiri khusus pemutar, kanan info/server/episode/rekomendasi
      return Scaffold(
        body: SafeArea(
          child: Row(children: [
            Expanded(
              flex: 5,
              child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(fit: StackFit.expand, children: [_video(), back]))),
            ),
            Expanded(
              flex: 3,
              child: Column(children: [sat, Expanded(child: info)]),
            ),
          ]),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                  color: Colors.black,
                  child: Stack(fit: StackFit.expand, children: [_video(), back]))),
          sat,
          Expanded(child: info),
        ]),
      ),
    );
  }
}

