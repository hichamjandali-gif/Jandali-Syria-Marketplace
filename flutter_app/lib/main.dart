import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'market_service.dart';

const url = String.fromEnvironment('SUPABASE_URL');
const anon = String.fromEnvironment('SUPABASE_ANON_KEY');
const green = Color(0xFF178447);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (url.isEmpty || anon.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('إعداد اتصال السوق غير مكتمل')))));
    return;
  }
  await Supabase.initialize(url: url, anonKey: anon);
  runApp(const MarketApp());
}

class MarketApp extends StatelessWidget {
  const MarketApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'السوق العربي',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: green), scaffoldBackgroundColor: const Color(0xFFF3F2EC)),
    home: const MarketHome(),
  );
}

class MarketHome extends StatefulWidget {
  const MarketHome({super.key});
  @override State<MarketHome> createState() => _MarketHomeState();
}
class _MarketHomeState extends State<MarketHome> {
  final api = MarketService.instance;
  int tab = 0;
  List<MarketListing> ads = [];
  Set<String> fav = {};
  bool busy = true;
  String search = '', city = '';
  String? category;
  final searchBox = TextEditingController();

  @override void initState() { super.initState(); loadFav(); load(); }
  @override void dispose() { searchBox.dispose(); super.dispose(); }

  Future<void> loadFav() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => fav = p.getStringList('market_favorites')?.toSet() ?? {});
  }
  Future<void> saveFav() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('market_favorites', fav.toList());
  }
  Future<void> load() async {
    setState(() => busy = true);
    try { final rows = await api.loadListings(); if (mounted) setState(() => ads = rows); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحميل الإعلانات: ' + e.toString()))); }
    finally { if (mounted) setState(() => busy = false); }
  }
  List<MarketListing> get results => ads.where((x) {
    if (category != null && x.category != category) return false;
    if (city.isNotEmpty && !x.city.toLowerCase().contains(city.toLowerCase())) return false;
    final q = search.toLowerCase().trim();
    return q.isEmpty || (x.title + ' ' + x.description + ' ' + x.city).toLowerCase().contains(q);
  }).toList();

  Future<void> auth() async {
    final email = TextEditingController(), password = TextEditingController();
    bool signup = false, waiting = false;
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      title: Text(signup ? 'إنشاء حساب' : 'تسجيل الدخول'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: email, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
        TextButton(onPressed: () => setD(() => signup = !signup), child: Text(signup ? 'تسجيل الدخول' : 'إنشاء حساب جديد')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: waiting ? null : () async {
          setD(() => waiting = true);
          try {
            final a = Supabase.instance.client.auth;
            final r = signup ? await a.signUp(email: email.text.trim(), password: password.text) : await a.signInWithPassword(email: email.text.trim(), password: password.text);
            if (r.user != null && ctx.mounted) Navigator.pop(ctx);
            if (signup && r.session == null && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('افتح بريدك لتأكيد الحساب')));
          } catch (e) {
            if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
          } finally { if (ctx.mounted) setD(() => waiting = false); }
        }, child: Text(waiting ? 'انتظر...' : 'متابعة')),
      ],
    )));
    email.dispose(); password.dispose(); if (mounted) setState(() {});
  }

  Future<void> add() async {
    if (api.user == null) { await auth(); if (api.user == null) return; }
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddAdPage()));
    if (ok == true) await load();
  }
  void toggle(String id) {
    setState(() { if (fav.contains(id)) { fav.remove(id); } else { fav.add(id); } });
    saveFav();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [homePage(), searchPage(), favoritesPage(), chatsPage(), accountPage()];
    return Scaffold(
      appBar: AppBar(title: const Text('السوق العربي | Arab Market', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
      body: IndexedStack(index: tab, children: pages),
      floatingActionButton: FloatingActionButton.extended(onPressed: add, backgroundColor: green, foregroundColor: Colors.white, icon: const Icon(Icons.add), label: const Text('أضف إعلاناً')),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
        NavigationDestination(icon: Icon(Icons.search), label: 'بحث'),
        NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'المفضلة'),
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'الرسائل'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي'),
      ]),
    );
  }

  Widget homePage() => RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(13), children: [
    Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(18)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('السوق العربي', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
      Text('بيع وشراء مجاني بين الناس', style: TextStyle(color: Colors.white)),
    ])),
    const SizedBox(height: 15), const Text('الأقسام', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
    GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: marketCategories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.08, crossAxisSpacing: 7, mainAxisSpacing: 7),
      itemBuilder: (c, i) { final x = marketCategories[i]; return InkWell(onTap: () => setState(() { category = x.id; tab = 1; }), child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(x.emoji, style: const TextStyle(fontSize: 28)), Text(x.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))]))); }),
    const SizedBox(height: 14), const Text('أحدث الإعلانات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
    feed(ads.take(15).toList()),
  ]));

  Widget searchPage() => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: Column(children: [
      TextField(controller: searchBox, onChanged: (v) => setState(() => search = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث عن سلعة أو خدمة', filled: true, fillColor: Colors.white)),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String?>(value: category, decoration: const InputDecoration(labelText: 'القسم'), items: [const DropdownMenuItem<String?>(value: null, child: Text('كل الأقسام')), ...marketCategories.map((x) => DropdownMenuItem<String?>(value: x.id, child: Text(x.name)))], onChanged: (v) => setState(() => category = v))),
        const SizedBox(width: 8), Expanded(child: TextField(decoration: const InputDecoration(labelText: 'المدينة'), onChanged: (v) => setState(() => city = v))),
      ]),
      TextButton(onPressed: () => setState(() { category = null; city = ''; search = ''; searchBox.clear(); }), child: const Text('مسح الفلاتر')),
    ])),
    Expanded(child: feed(results)),
  ]);

  Widget favoritesPage() {
    final rows = ads.where((x) => fav.contains(x.id)).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [const Text('المفضلة ❤️', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), if (rows.isEmpty) const Text('لا توجد إعلانات محفوظة'), feed(rows)]);
  }

  Widget feed(List<MarketListing> rows) {
    if (busy && rows.isEmpty) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(25), child: Text('لا توجد إعلانات حالياً', textAlign: TextAlign.center));
    return ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (c, i) {
      final x = rows[i], cat = MarketCategory.byId(x.category);
      return Card(child: ListTile(
        contentPadding: const EdgeInsets.all(8), leading: SizedBox(width: 76, height: 76, child: x.photos.isEmpty ? Center(child: Text(cat.emoji, style: const TextStyle(fontSize: 30))) : Image.network(x.photos.first, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(cat.emoji)))),
        title: Text(x.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(x.priceLabel + '\n' + x.location, style: const TextStyle(color: green, fontWeight: FontWeight.bold)),
        trailing: IconButton(onPressed: () => toggle(x.id), icon: Icon(fav.contains(x.id) ? Icons.favorite : Icons.favorite_border, color: fav.contains(x.id) ? Colors.red : null)),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdDetailPage(ad: x, favorite: fav.contains(x.id), onFavorite: () => toggle(x.id)))),
      ));
    });
  }

  Widget chatsPage() => FutureBuilder<List<Map<String, dynamic>>>(future: api.user == null ? Future.error('سجّل الدخول لعرض الرسائل') : api.conversations(), builder: (c, s) {
    if (s.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (s.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(s.error.toString()), FilledButton(onPressed: auth, child: const Text('تسجيل الدخول'))]));
    final rows = s.data ?? [];
    if (rows.isEmpty) return const Center(child: Text('لا توجد محادثات بعد'));
    return ListView(children: rows.map((r) { return ListTile(leading: const Icon(Icons.chat), title: const Text('محادثة خاصة'), subtitle: Text(r['created_at'].toString()), onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(id: r['id'] as String))); }); }).toList());
  });

  Widget accountPage() => ListView(padding: const EdgeInsets.all(16), children: [
    const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 38)),
    Center(child: Text(api.user?.email ?? 'زائر', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
    if (api.user == null) FilledButton(onPressed: auth, child: const Text('تسجيل الدخول / إنشاء حساب'))
    else ...[
      ListTile(leading: const Icon(Icons.inventory), title: const Text('إعلاناتي'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAdsPage()))),
      ListTile(leading: const Icon(Icons.logout), title: const Text('تسجيل الخروج'), onTap: () async { await Supabase.instance.client.auth.signOut(); setState(() {}); }),
    ],
    const Divider(), const ListTile(title: Text('السوق العربي - By Hicham Jandali'), subtitle: Text('نسخة Flutter تجريبية')),
  ]);
}

class AdDetailPage extends StatefulWidget {
  final MarketListing ad; final bool favorite; final VoidCallback onFavorite;
  const AdDetailPage({super.key, required this.ad, required this.favorite, required this.onFavorite});
  @override State<AdDetailPage> createState() => _AdDetailPageState();
}
class _AdDetailPageState extends State<AdDetailPage> {
  int active = 0; bool waiting = false;
  @override Widget build(BuildContext context) {
    final x = widget.ad;
    return Scaffold(appBar: AppBar(title: const Text('تفاصيل الإعلان'), actions: [IconButton(onPressed: widget.onFavorite, icon: Icon(widget.favorite ? Icons.favorite : Icons.favorite_border))]),
      body: ListView(padding: const EdgeInsets.all(13), children: [
        Container(height: 290, color: Colors.black12, alignment: Alignment.center, child: x.photos.isEmpty ? Text(MarketCategory.byId(x.category).emoji, style: const TextStyle(fontSize: 75)) : Image.network(x.photos[active], fit: BoxFit.contain)),
        if (x.photos.length > 1) SizedBox(height: 88, child: ListView(scrollDirection: Axis.horizontal, children: [for (var i = 0; i < x.photos.length; i++) GestureDetector(onTap: () => setState(() => active = i), child: Container(width: 82, margin: const EdgeInsets.all(4), decoration: BoxDecoration(border: Border.all(color: active == i ? green : Colors.transparent, width: 3)), child: Image.network(x.photos[i], fit: BoxFit.cover)))])),
        const SizedBox(height: 10), Text(x.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        Text(x.priceLabel, style: const TextStyle(color: green, fontSize: 20, fontWeight: FontWeight.bold)),
        ListTile(leading: const Icon(Icons.location_on), title: Text(x.location)),
        Text(x.description, style: const TextStyle(fontSize: 16)),
        FilledButton.icon(onPressed: waiting ? null : () async {
          setState(() => waiting = true);
          try { final id = await MarketService.instance.openConversation(x); if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(id: id))); }
          catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
          finally { if (mounted) setState(() => waiting = false); }
        }, icon: const Icon(Icons.message), label: const Text('راسل البائع')),
      ]),
    );
  }
}

class AddAdPage extends StatefulWidget { const AddAdPage({super.key}); @override State<AddAdPage> createState() => _AddAdPageState(); }
class _AddAdPageState extends State<AddAdPage> {
  final picker = ImagePicker();
  final title = TextEditingController(), desc = TextEditingController(), city = TextEditingController(), district = TextEditingController(), phone = TextEditingController(), price = TextEditingController();
  final List<XFile> photos = [];
  String category = 'houses', currency = 'SYP'; bool busy = false;
  @override void dispose() { title.dispose(); desc.dispose(); city.dispose(); district.dispose(); phone.dispose(); price.dispose(); super.dispose(); }
  void msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> album() async { try { final p = await picker.pickMultiImage(imageQuality: 92, maxWidth: 2400, maxHeight: 2400); if (mounted) setState(() => photos.addAll(p.take(8 - photos.length))); } catch (e) { msg(e.toString()); } }
  Future<void> camera() async { try { final p = await picker.pickImage(source: ImageSource.camera, imageQuality: 92, maxWidth: 2400, maxHeight: 2400); if (p != null && mounted && photos.length < 8) setState(() => photos.add(p)); } catch (e) { msg(e.toString()); } }
  Future<void> map() async { final r = await Navigator.push<Map<String, String>>(context, MaterialPageRoute(builder: (_) => const MapPage())); if (r != null) { city.text = r['city'] ?? ''; district.text = r['district'] ?? ''; setState(() {}); } }
  Future<void> publish() async {
    if (photos.isEmpty) { msg('أضف صورة واحدة على الأقل'); return; }
    setState(() => busy = true);
    try {
      final bytes = <Uint8List>[], names = <String>[];
      for (final p in photos) { bytes.add(await p.readAsBytes()); names.add(p.name); }
      await MarketService.instance.publish(title: title.text, description: desc.text, category: category, city: city.text, district: district.text, phone: phone.text, price: category == 'free' ? 0 : num.tryParse(price.text), currency: currency, photoBytes: bytes, photoNames: names);
      if (mounted) Navigator.pop(context, true);
    } catch (e) { msg('تعذر النشر: ' + e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('إضافة إعلان')), body: ListView(padding: const EdgeInsets.all(13), children: [
    const Text('الصورة الأولى هي الغلاف', style: TextStyle(fontWeight: FontWeight.bold)),
    Container(height: 240, color: Colors.black, alignment: Alignment.center, child: photos.isEmpty ? const Text('اختر الصور', style: TextStyle(color: Colors.white)) : Image.file(File(photos.first.path), fit: BoxFit.contain)),
    if (photos.isNotEmpty) SizedBox(height: 92, child: ReorderableListView(scrollDirection: Axis.horizontal, onReorder: (a, b) { setState(() { if (b > a) b--; final p = photos.removeAt(a); photos.insert(b, p); }); }, children: [for (var i = 0; i < photos.length; i++) Container(key: ValueKey(photos[i].path), width: 80, margin: const EdgeInsets.all(4), child: Stack(fit: StackFit.expand, children: [GestureDetector(onTap: () => setState(() { final p = photos.removeAt(i); photos.insert(0, p); }), child: Image.file(File(photos[i].path), fit: BoxFit.cover)), Positioned(right: 0, top: 0, child: IconButton(onPressed: () => setState(() => photos.removeAt(i)), icon: const Icon(Icons.close, color: Colors.red)))]))])),
    Row(children: [Expanded(child: OutlinedButton.icon(onPressed: album, icon: const Icon(Icons.photo_library), label: const Text('الألبوم'))), Expanded(child: FilledButton.icon(onPressed: camera, icon: const Icon(Icons.camera_alt), label: const Text('الكاميرا')))]),
    DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'القسم'), items: marketCategories.map((x) => DropdownMenuItem(value: x.id, child: Text(x.name))).toList(), onChanged: (v) => setState(() => category = v ?? 'houses')),
    TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان الإعلان')),
    TextField(controller: desc, maxLines: 4, decoration: const InputDecoration(labelText: 'التفاصيل')),
    Row(children: [Expanded(child: TextField(controller: city, decoration: const InputDecoration(labelText: 'المدينة'))), IconButton(onPressed: map, icon: const Icon(Icons.map))]),
    TextField(controller: district, decoration: const InputDecoration(labelText: 'الحي')),
    TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف (اختياري)')),
    if (category != 'free') Row(children: [Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر'))), DropdownButton<String>(value: currency, items: const [DropdownMenuItem(value: 'SYP', child: Text('ل.س')), DropdownMenuItem(value: 'USD', child: Text('USD'))], onChanged: (v) => setState(() => currency = v ?? 'SYP'))]),
    const SizedBox(height: 12), FilledButton(onPressed: busy ? null : publish, child: Text(busy ? 'جارٍ النشر...' : 'نشر الإعلان')),
  ]));
}

class MapPage extends StatefulWidget { const MapPage({super.key}); @override State<MapPage> createState() => _MapPageState(); }
class _MapPageState extends State<MapPage> {
  LatLng point = const LatLng(33.5138, 36.2765); String city = 'دمشق', district = ''; bool busy = false;
  Future<void> locate() async {
    try { var p = await Geolocator.checkPermission(); if (p == LocationPermission.denied) p = await Geolocator.requestPermission(); if (p == LocationPermission.denied || p == LocationPermission.deniedForever) throw Exception('اسمح بالوصول للموقع'); final pos = await Geolocator.getCurrentPosition(); point = LatLng(pos.latitude, pos.longitude); await reverse(point); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
  }
  Future<void> reverse(LatLng p) async {
    setState(() => busy = true);
    try {
      final u = Uri.https('nominatim.openstreetmap.org', '/reverse', {'format':'jsonv2','lat':p.latitude.toString(),'lon':p.longitude.toString(),'zoom':'18','addressdetails':'1','accept-language':'ar'});
      final r = await http.get(u, headers: {'User-Agent':'JandaliArabMarket/1.0'});
      if (r.statusCode == 200) { final a = (jsonDecode(r.body)['address'] ?? {}) as Map<String, dynamic>; city = (a['city'] ?? a['town'] ?? a['village'] ?? a['county'] ?? 'موقع محدد').toString(); district = (a['suburb'] ?? a['neighbourhood'] ?? a['quarter'] ?? '').toString(); }
    } catch (_) {} finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('اختيار الموقع')), body: Stack(children: [
    FlutterMap(options: MapOptions(initialCenter: point, initialZoom: 12, onTap: (_, p) { setState(() => point = p); reverse(p); }), children: [
      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.jandali.market'),
      MarkerLayer(markers: [Marker(point: point, width: 44, height: 44, child: const Icon(Icons.location_pin, color: Colors.red, size: 42))]),
    ]),
    Positioned(top: 12, left: 12, child: FloatingActionButton.small(onPressed: locate, child: const Icon(Icons.my_location))),
    Positioned(bottom: 16, left: 12, right: 12, child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(busy ? 'جارٍ تحديد العنوان...' : city + ' ' + district, style: const TextStyle(fontWeight: FontWeight.bold)),
      FilledButton(onPressed: busy ? null : () => Navigator.pop(context, {'city': city, 'district': district}), child: const Text('تأكيد الموقع')),
    ])))),
  ]));
}

class ChatPage extends StatefulWidget { final String id; const ChatPage({super.key, required this.id}); @override State<ChatPage> createState() => _ChatPageState(); }
class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController(); bool sending = false;
  @override void dispose() { input.dispose(); super.dispose(); }
  Future<void> send() async { if (input.text.trim().isEmpty) return; setState(() => sending = true); try { await MarketService.instance.sendMessage(widget.id, input.text); input.clear(); setState(() {}); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); } finally { if (mounted) setState(() => sending = false); } }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('محادثة خاصة')), body: Column(children: [
    Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(future: MarketService.instance.messages(widget.id), builder: (c, s) {
      if (s.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (s.hasError) return Center(child: Text(s.error.toString()));
      return ListView(padding: const EdgeInsets.all(12), children: (s.data ?? []).map((m) { final mine = m['sender_id'] == MarketService.instance.user?.id; return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(12), constraints: const BoxConstraints(maxWidth: 300), decoration: BoxDecoration(color: mine ? const Color(0xFFDDF3E3) : Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(m['body'].toString()))); }).toList());
    })),
    SafeArea(child: Row(children: [Expanded(child: TextField(controller: input, decoration: const InputDecoration(hintText: 'اكتب رسالتك'))), IconButton(onPressed: sending ? null : send, icon: const Icon(Icons.send, color: green))])),
  ]));
}

class MyAdsPage extends StatefulWidget { const MyAdsPage({super.key}); @override State<MyAdsPage> createState() => _MyAdsPageState(); }
class _MyAdsPageState extends State<MyAdsPage> {
  late Future<List<MarketListing>> future;
  @override void initState() { super.initState(); future = MarketService.instance.myListings(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('إعلاناتي')), body: FutureBuilder<List<MarketListing>>(future: future, builder: (c, s) {
    if (s.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (s.hasError) return Center(child: Text(s.error.toString()));
    final rows = s.data ?? [];
    return ListView(children: rows.map((x) => ListTile(title: Text(x.title), subtitle: Text(x.location + ' • ' + x.status), trailing: PopupMenuButton<String>(onSelected: (v) async { try { if (v == 'close') await MarketService.instance.closeListing(x.id); if (v == 'delete') await MarketService.instance.deleteListing(x.id); setState(() => future = MarketService.instance.myListings()); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); } }, itemBuilder: (_) => const [PopupMenuItem(value: 'close', child: Text('إيقاف')), PopupMenuItem(value: 'delete', child: Text('حذف'))]))).toList());
  }));
}
