import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

const api =
    'https://script.google.com/macros/s/AKfycbycxushyypYFF1FptMeQYXRcldkioUTsHXg6-l69LamTBvK_BPjP5w5NHa8XK3_Cuc/exec';
const accent = Color(0xFFFF2D46);
const bgc = Color(0xFF07070B);
const cardc = Color(0xFF16161B);

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
  Group(this.title, this.cat, this.gi);
}

/* ===================== DATA ===================== */
class App {
  static List<Ep> eps = [];
  static List<Group> groups = [];
  static Map<String, Group> gm = {};
  static Map<String, Ep> byKey = {};
  static Map<String, int> vc = {}, wk = {};
  static bool loaded = false;
  static String? error;
  static final refresh = ValueNotifier<int>(0);
  static final tab = ValueNotifier<int>(0);
  static final catReq = ValueNotifier<String>('');

  static void ingest(List raw) {
    final out = <Ep>[];
    for (final it in raw) {
      if (it is! Map) continue;
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
        syn: cut(s(it['sinopsis']).isNotEmpty ? s(it['sinopsis']) : s(it['synopsis']), 2000),
        gen: cut(s(it['genre']).isNotEmpty ? s(it['genre']) : s(it['genres']), 200),
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
      final r = await http
          .get(Uri.parse(api))
          .timeout(const Duration(seconds: 20));
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
}

/* ===================== PENYIMPANAN LOKAL ===================== */
class Store {
  static late SharedPreferences p;
  static Future<void> init() async {
    p = await SharedPreferences.getInstance();
  }

  static List<String> get bms => List<String>.from(p.getStringList('bms') ?? []);
  static bool isBm(String t) => bms.contains(t);
  static void toggleBm(String t) {
    final l = bms;
    if (!l.remove(t)) l.add(t);
    p.setStringList('bms', l);
  }

  static Map<String, dynamic> _m(String k) {
    try {
      return Map<String, dynamic>.from(jsonDecode(p.getString(k) ?? '{}'));
    } catch (_) {
      return {};
    }
  }

  static double posOf(String key) {
    final v = _m('pos')[key];
    if (v is Map) return (v['t'] as num?)?.toDouble() ?? 0.0;
    return 0.0;
  }

  static double progOf(String key) {
    final v = _m('pos')[key];
    if (v is Map) {
      final t = (v['t'] as num?)?.toDouble() ?? 0.0;
      final d = (v['d'] as num?)?.toDouble() ?? 0.0;
      return d > 0 ? (t / d).clamp(0.0, 1.0) : 0.0;
    }
    return 0.0;
  }

  static bool seen(String key) => _m('seen').containsKey(key);
  static void markSeen(String key) {
    final m = _m('seen');
    if (m.containsKey(key)) return;
    m[key] = 1;
    p.setString('seen', jsonEncode(m));
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
    p.setString('hist', jsonEncode(l.take(20).toList()));
  }

  static void savePos(Ep e, double t, double d) {
    if (d <= 0 || t < 10) return;
    final pos = _m('pos');
    if (t / d > .9) markSeen(e.key);
    if (t / d > .95) {
      pos.remove(e.key);
      p.setString('pos', jsonEncode(pos));
      return;
    }
    pos[e.key] = {'t': t, 'd': d};
    p.setString('pos', jsonEncode(pos));
  }

  static void clearHist() {
    p.remove('hist');
    p.remove('pos');
    p.remove('seen');
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
                              fontWeight: FontWeight.w700, shadows: [
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
                      child: const Text('Lihat Semua ›',
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

/// grid dengan tinggi sel pasti (poster 16:9 + judul 2 baris), tidak ada celah kosong
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
                      fontSize: 11, fontWeight: FontWeight.w600, height: 1.25)),
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
                center: a, radius: .95, colors: [c.withOpacity(o), Colors.transparent]),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Stack(children: [
          _g(const Alignment(-1, -1), accent, .26),
          _g(const Alignment(1, -.3), const Color(0xFF7846FF), .20),
          _g(const Alignment(-1, .8), const Color(0xFF0096FF), .16),
        ]),
      );
}

/* ===================== APLIKASI ===================== */
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(const LesehanApp());
}

class LesehanApp extends StatelessWidget {
  const LesehanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LesehanTV',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bgc,
          colorScheme: const ColorScheme.dark(
              primary: accent, secondary: accent, surface: cardc),
          chipTheme: ChipThemeData(
            backgroundColor: Colors.white.withOpacity(.06),
            selectedColor: accent,
            checkmarkColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(.14)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            labelStyle: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: const Color(0xFF0C0C10),
            indicatorColor: accent.withOpacity(.28),
          ),
        ),
        home: const Root(),
      );
}

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  int i = 0;
  void _tabL() {
    if (mounted) setState(() => i = App.tab.value);
  }

  @override
  void initState() {
    super.initState();
    App.tab.addListener(_tabL);
    App.load();
  }

  @override
  void dispose() {
    App.tab.removeListener(_tabL);
    super.dispose();
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
            body = IndexedStack(index: i, children: const [
              HomeTab(),
              PopularTab(),
              CatalogTab(),
              LibraryTab(),
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
              ],
            ),
          );
        },
      );
}

/* ===================== BERANDA ===================== */
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
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
          itemBuilder: (_, i) =>
              t10Item(context, i, top[i].key, top[i].value),
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
    final hs = Store.hist.map((h) => App.byKey[h['key']]).whereType<Ep>().toList();
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
            child: const Icon(Icons.play_arrow_rounded, size: 28),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Welcome',
                  style: TextStyle(fontSize: 11, color: Colors.white60)),
              Text('LesehanTV',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(
              onPressed: () => App.tab.value = 2,
              icon: const Icon(Icons.search, color: accent, size: 26)),
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
                                    colors: [Colors.black87, Colors.transparent]),
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
                                        style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(g.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
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
                      color: k == heroI ? accent : Colors.white24,
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
  const PopularTab({super.key});
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
          ChoiceChip(
              label: const Text('Minggu Ini'),
              selected: week,
              onSelected: (_) => setState(() => week = true)),
          const SizedBox(width: 8),
          ChoiceChip(
              label: const Text('Sepanjang Masa'),
              selected: !week,
              onSelected: (_) => setState(() => week = false)),
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
                decoration: BoxDecoration(
                    color: cardc, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  SizedBox(
                      width: 38,
                      child: Text('#${i + 1}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
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
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white60)),
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
  const CatalogTab({super.key});
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
            fillColor: cardc,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: cats
                .map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                          label: Text(c[1]),
                          selected: cat == c[0],
                          onSelected: (_) => setState(() => cat = c[0])),
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
  const LibraryTab({super.key});
  @override
  Widget build(BuildContext context) {
    final bm = Store.bms.map((t) => App.gm[t]).whereType<Group>().toList();
    final hs = Store.hist.map((h) => App.byKey[h['key']]).whereType<Ep>().toList();
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
                onPressed: () {
                  Store.clearHist();
                  App.refresh.value++;
                },
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
              itemBuilder: (_, i) => ResumeCard(hs[i]),
            ),
          ),
      ],
    );
  }
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
  @override
  Widget build(BuildContext context) {
    final g = App.gm[widget.title];
    if (g == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Judul tidak ditemukan.')));
    }
    final hist = Store.hist.where((h) => h['title'] == g.title);
    final last = hist.isEmpty ? null : App.byKey[hist.first['key']];
    final first = last ?? g.eps.first;
    final list = desc ? g.eps.reversed.toList() : g.eps;
    final genres = g.gen
        .split(RegExp(r'[,;|]'))
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toList();
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 230,
          backgroundColor: bgc,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              poster(g.thumb, radius: 0),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [bgc, Colors.transparent]),
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
                  style: const TextStyle(
                      color: accent, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(g.title,
                  style: const TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(label: Text('${g.eps.length} Eps')),
                for (final x in genres) Chip(label: Text(x)),
              ]),
              if (g.syn.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(g.syn,
                    maxLines: more ? null : 4,
                    overflow: more ? null : TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, height: 1.5)),
                if (g.syn.length > 220)
                  TextButton(
                      onPressed: () => setState(() => more = !more),
                      child: Text(more ? 'Tutup' : 'Selengkapnya')),
              ],
              const SizedBox(height: 12),
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
                    onPressed: () => setState(() => Store.toggleBm(g.title)),
                    icon: Icon(Store.isBm(g.title)
                        ? Icons.bookmark
                        : Icons.bookmark_add_outlined),
                    label: Text(Store.isBm(g.title) ? 'Tersimpan' : 'Bookmark'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${g.eps.length} Episode',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w500)),
                TextButton(
                    onPressed: () => setState(() => desc = !desc),
                    child: Text(desc ? '↓ Terbaru' : '↑ Terlama')),
              ]),
            ]),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final e = list[i];
              final seen = Store.seen(e.key);
              final pr = Store.progOf(e.key);
              return GestureDetector(
                onTap: () => playEp(context, e).then((_) {
                  if (mounted) setState(() {});
                }),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  decoration: BoxDecoration(
                      color: cardc,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: (last != null && last.key == e.key)
                              ? accent
                              : Colors.white10)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(children: [
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(children: [
                          Expanded(
                              child: Opacity(
                                  opacity: seen ? .55 : 1,
                                  child: Text(e.eps.isEmpty ? 'Putar Video' : e.eps,
                                      style: const TextStyle(fontSize: 15)))),
                          if (seen)
                            const Icon(Icons.check, size: 18, color: accent),
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
        const SliverToBoxAdapter(child: SizedBox(height: 30)),
      ]),
    );
  }
}

/* ===================== PEMUTAR ===================== */
class PlayerPage extends StatefulWidget {
  final Ep ep;
  const PlayerPage(this.ep, {super.key});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late Ep ep;
  int sv = 0, _tok = 0, _last = 0;
  bool loading = true, _ended = false;
  String? err;
  VideoPlayerController? vc;
  ChewieController? cc;
  WebViewController? wc;

  @override
  void initState() {
    super.initState();
    ep = widget.ep;
    start();
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
      Store.savePos(ep, 1, 1);
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
    _tok++;
    _release();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Widget _video() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (err != null) {
      final n = 1 + ep.extra.length;
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('⚠️ $err'),
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
              Text(ep.title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
              Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 12),
                child: Text(
                    '${ep.eps}${ep.eps.isEmpty ? '' : '  •  '}👁 ${fv(App.views(ep.title))} penonton',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ),
              if (names.length > 1) ...[
                const Text('🖥 Pilih Server'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: names.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => ChoiceChip(
                      label: Text(names[i]),
                      selected: sv == i,
                      onSelected: (_) {
                        if (sv == i) return;
                        sv = i;
                        start();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (all.length > 1) ...[
                const Text('Episode List',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: all.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final e = all[i];
                      final lb = e.eps.replaceFirst(
                          RegExp(r'^Eps\s*', caseSensitive: false), '');
                      return ChoiceChip(
                        label: Text(lb.isEmpty ? '▶' : lb),
                        selected: e.id == ep.id,
                        avatar: Store.seen(e.key)
                            ? const Icon(Icons.check, size: 14)
                            : null,
                        onSelected: (_) {
                          if (e.id != ep.id) _go(e);
                        },
                      );
                    },
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
