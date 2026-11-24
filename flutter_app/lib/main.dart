import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:mime/mime.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'market_service.dart';

const url = const String.fromEnvironment('SUPABASE_URL');
const anon = const String.fromEnvironment('SUPABASE_ANON_KEY');
const green = Color(0xFF178447);

String _cleanError(Object? error) => (error?.toString() ?? '')
    .replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '')
    .trim();

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

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key});
  @override State<AuthDialog> createState() => _AuthDialogState();
}
class _AuthDialogState extends State<AuthDialog> {
  final email = TextEditingController();
  final password = TextEditingController();
  final displayName = TextEditingController();
  bool signup = false, waiting = false, showPassword = false;
  @override void dispose() {
    email.dispose();
    password.dispose();
    displayName.dispose();
    super.dispose();
  }
  Future<void> submit() async {
    if (waiting) return;
    setState(() => waiting = true);
    try {
      final auth = Supabase.instance.client.auth;
      debugPrint('محاولة دخول من APK - البريد: ${email.text.trim()} - العملية: ${signup ? 'إنشاء حساب' : 'تسجيل دخول'}');
      final response = signup
          ? await auth.signUp(email: email.text.trim(), password: password.text, data: {'full_name': displayName.text.trim()})
          : await auth.signInWithPassword(email: email.text.trim(), password: password.text);
      debugPrint('وصل رد من Supabase - النتيجة: user=${response.user != null}, session=${response.session != null}');
      if (!mounted) return;
      if (response.user != null && response.session != null) {
        Navigator.of(context).pop(true);
      } else if (signup) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('افتح بريدك لتأكيد الحساب، ثم سجّل الدخول')));
      }
    } on AuthException catch (e) {
      debugPrint('وصل رد من Supabase - رفض Auth: status=${e.statusCode}, code=${e.code}, message=${e.message}');
      if (mounted) {
        final invalid = e.statusCode == '400' || e.code == 'invalid_credentials' || e.message.toLowerCase().contains('invalid login credentials');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: !signup && invalid
          ? Column(mainAxisSize: MainAxisSize.min, children: [const Text('الإيميل أو كلمة المرور غير صحيحة - أو أنشئ حساب جديد'), TextButton(onPressed: resetPassword, child: const Text('نسيت كلمة المرور؟'))])
          : Text(signup ? 'تعذر إنشاء الحساب. تحقق من البيانات وحاول مجدداً' : 'تعذر تسجيل الدخول. حاول مرة أخرى')));
      }
    } catch (e, stackTrace) {
      debugPrint('خطأ أثناء محاولة Auth من APK: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ. تحقق من الاتصال وحاول مرة أخرى')));
    } finally {
      if (mounted) setState(() => waiting = false);
    }
  }
  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل بريدك الإلكتروني أولاً'))); return; }
    try { await Supabase.instance.client.auth.resetPasswordForEmail(email.text.trim()); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال رابط إعادة تعيين كلمة المرور إلى بريدك'))); }
    on AuthException catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر إرسال رابط إعادة التعيين. تحقق من البريد وحاول مجدداً'))); }
  }
  @override Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(signup ? 'إنشاء حساب' : 'تسجيل الدخول'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      if (signup) TextField(controller: displayName, decoration: const InputDecoration(labelText: 'اسمك')),
      TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
      TextField(controller: password, obscureText: !showPassword, decoration: InputDecoration(labelText: 'كلمة المرور', suffixIcon: IconButton(icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => showPassword = !showPassword)))),
      if (!signup) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: waiting ? null : resetPassword, child: const Text('نسيت كلمة المرور؟'))),
      TextButton(onPressed: waiting ? null : () => setState(() => signup = !signup), child: Text(signup ? 'لديك حساب؟ تسجيل الدخول' : 'إنشاء حساب جديد')),
    ]),
    actions: [
      TextButton(onPressed: waiting ? null : () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
      FilledButton(onPressed: waiting ? null : submit, child: Text(waiting ? 'انتظر...' : 'متابعة')),
    ],
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
  bool hasMoreAds = true, loadingMoreAds = false;
  static const int _pageSize = 200;
  String search = '', city = '', selectedLocation = 'كاسل، ألمانيا';
  String? category;
  final searchBox = TextEditingController();
  final speech = stt.SpeechToText();
  bool listening = false;
  final homeTts = FlutterTts();
  double radiusKm = 25;
  double? searchLat, searchLng;

  @override void initState() { super.initState(); loadFav(); load(); }
  @override void dispose() { searchBox.dispose(); speech.stop(); homeTts.stop(); super.dispose(); }

  Future<void> speak(String text) async { try { await homeTts.setLanguage('ar-SA'); await homeTts.speak(text); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ميزة الاستماع غير متاحة على هذا الجهاز'))); } }

  Future<void> changeLocation() async {
    final r = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (_) => const MapPage()));
    if (!mounted || r == null) return;
    setState(() { selectedLocation = (r['city'] ?? selectedLocation).toString(); radiusKm = (r['radius'] as num?)?.toDouble() ?? radiusKm; searchLat = (r['lat'] as num?)?.toDouble(); searchLng = (r['lng'] as num?)?.toDouble(); });
  }

  Future<void> voiceSearch() async {
    try {
      final available = await speech.initialize(onStatus: (status) { if (mounted) setState(() => listening = status == 'listening'); }, onError: (_) { if (mounted) setState(() => listening = false); });
      if (!mounted) return;
      if (!available) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('البحث الصوتي غير متاح على هذا الجهاز'))); return; }
      setState(() => listening = true);
      await speech.listen(localeId: 'ar_SA', onResult: (result) { if (!mounted) return; searchBox.text = result.recognizedWords; setState(() => search = result.recognizedWords); });
    } catch (e) { if (mounted) { setState(() => listening = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تشغيل البحث الصوتي: $e'))); } }
  }

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
    try {
      final rows = await api.loadListings(offset: 0, limit: _pageSize);
      if (mounted) setState(() { ads = rows; hasMoreAds = rows.length == _pageSize; });
    }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحميل الإعلانات: ' + _cleanError(e)))); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> loadMoreAds() async {
    if (busy || loadingMoreAds || !hasMoreAds) return;
    setState(() => loadingMoreAds = true);
    try {
      final rows = await api.loadListings(offset: ads.length, limit: _pageSize);
      if (mounted) setState(() { ads.addAll(rows); hasMoreAds = rows.length == _pageSize; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحميل المزيد: ' + _cleanError(e))));
    } finally {
      if (mounted) setState(() => loadingMoreAds = false);
    }
  }

  Widget _loadMoreButton() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: OutlinedButton(
      onPressed: loadingMoreAds || !hasMoreAds ? null : loadMoreAds,
      child: Text(loadingMoreAds ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد من الإعلانات'),
    ),
  );
  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) + math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.pow(math.sin(dLng / 2), 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  List<MarketListing> get locationFilteredAds => ads.where((x) {
    if (searchLat == null || searchLng == null || x.lat == null || x.lng == null) return true;
    return _distanceKm(searchLat!, searchLng!, x.lat!, x.lng!) <= radiusKm;
  }).toList();

  List<MarketListing> get results => locationFilteredAds.where((x) {
    if (category != null && x.category != category) return false;
    if (city.isNotEmpty && !x.city.toLowerCase().contains(city.toLowerCase())) return false;
    final q = search.toLowerCase().trim();
    return q.isEmpty || (x.title + ' ' + x.description + ' ' + x.city).toLowerCase().contains(q);
  }).toList();

  Future<bool> auth() async {
    if (api.user != null) return true;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AuthDialog(),
    );
    if (!mounted) return false;
    setState(() {});
    return result == true && api.user != null;
  }

  Future<bool> requireLogin() async {
    if (api.user != null) return true;
    final ok = await auth();
    if (!mounted) return false;
    if (!ok) {
      setState(() => tab = 0);
      return false;
    }
    return true;
  }

  Future<void> add({bool byVoice = false}) async {
    // TEMPORARY PHOTO TEST: guests may open the ad form, but cannot publish.
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AddAdPage(voiceFirst: byVoice)));
    if (mounted && ok == true) await load();
  }
  void toggle(String id) {
    setState(() { if (fav.contains(id)) { fav.remove(id); } else { fav.add(id); } });
    saveFav();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [homePage(), searchPage(), favoritesPage(), chatsPage(), accountPage()];
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _topHeader(),
            _searchHeader(),
            _locationHeader(),
            Expanded(child: IndexedStack(index: tab, children: pages)),
          ],
        ),
      ),
      bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0 ? null : SafeArea(
        top: false,
        child: Container(
          height: 82,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE8E8E8))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              _navItem('حسابي', Icons.person_outline, 4),
              _navItem('الرسائل', Icons.chat_bubble_outline, 3),
              Expanded(
                child: InkWell(
                  onTap: () => add(byVoice: true),
                  borderRadius: BorderRadius.circular(14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 39,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF5EC),
                          border: Border.all(color: green, width: 1.6),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add, color: green, size: 22),
                            Icon(Icons.mic, color: green, size: 17),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text('أضف إعلانك', maxLines: 1, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: green)),
                      const Text('بالصوت', maxLines: 1, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black54)),
                    ],
                  ),
                ),
              ),
              _navItem('المفضلة', Icons.favorite_border, 2, activeLabel: fav.isEmpty ? 'المفضلة' : 'المفضلة ${fav.length}'),
              _navItem('بحث', Icons.search, 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topHeader() => Container(
    width: double.infinity,
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('السوق العربي', maxLines: 1, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF202020))),
        const Text('Arab Market By Hicham Jandali', maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54)),
        const SizedBox(height: 7),
        Row(
          children: [
            _statusChip('المفضلة: ${fav.length}', Colors.black87),
            const SizedBox(width: 5),
            _statusChip('مباشر الآن', green),
            const SizedBox(width: 5),
            _statusChip('سوريا • 3', green),
          ],
        ),
      ],
    ),
  );

  Widget _statusChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: color == green ? const Color(0xFFEAF5EC) : const Color(0xFFF4F4F4), borderRadius: BorderRadius.circular(20)),
    child: Text(label, maxLines: 1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color)),
  );

  Widget _searchHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 7),
    child: TextField(
      controller: searchBox,
      textDirection: TextDirection.rtl,
      onChanged: (v) => setState(() => search = v),
      decoration: InputDecoration(
        hintText: 'عن ماذا تبحث؟ سيارة، بيت، عمل...',
        hintStyle: const TextStyle(fontSize: 13, color: Colors.black45),
        prefixIcon: const Icon(Icons.search, color: Colors.black45),
        suffixIcon: IconButton(
          onPressed: voiceSearch,
          tooltip: 'بحث صوتي',
          icon: Icon(Icons.mic, color: listening ? Colors.red : green, size: 25),
        ),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE8E8E8))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: green, width: 1.5)),
      ),
    ),
  );

  Widget _locationHeader() => InkWell(
    onTap: changeLocation,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFEAF5EC), borderRadius: BorderRadius.circular(12), border: Border.all(color: green.withOpacity(0.25))),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: green, size: 18),
          const SizedBox(width: 5),
          Expanded(child: Text('منطقة البحث: $selectedLocation • ${radiusKm.round()} كم', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF286C3D)))),
          const SizedBox(width: 5),
          const Text('تغيير الموقع', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: green)),
        ],
      ),
    ),
  );

  Widget _navItem(String label, IconData icon, int target, {String? activeLabel}) => Expanded(
    child: InkWell(
      onTap: () => setState(() => tab = target),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: tab == target ? green : Colors.black45),
          const SizedBox(height: 3),
          Text(activeLabel ?? label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, fontWeight: tab == target ? FontWeight.w900 : FontWeight.w700, color: tab == target ? green : Colors.black54)),
        ],
      ),
    ),
  );

  Widget homePage() => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 18),
      children: [
        if (search.trim().isNotEmpty) ...[
          Text('نتائج البحث (${results.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          feed(results),
        ] else ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('كل الأقسام • اضغط على الصورة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text('${marketCategories.length} قسم', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black45)),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: marketCategories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 190,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (c, i) {
            final x = marketCategories[i];
            final count = ads.where((a) => a.category == x.id).length;
            final tones = [
              const Color(0xFFFFF1E8), const Color(0xFFEAF5EC),
              const Color(0xFFFFF8DF), const Color(0xFFEAF1FF),
              const Color(0xFFFFEDF1), const Color(0xFFEAF8F8),
            ];
            return InkWell(
              onTap: () => setState(() { category = x.id; tab = 1; }),
              borderRadius: BorderRadius.circular(17),
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFEAEAEA)), boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 7, offset: Offset(0, 2))]),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 88,
                      color: tones[i % tones.length],
                      alignment: Alignment.center,
                      child: Text(x.emoji, style: const TextStyle(fontSize: 48)),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(9, 7, 9, 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Expanded(child: Text(x.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black54, height: 1.15))),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$count إعلان', style: const TextStyle(fontSize: 9, color: Colors.black45, fontWeight: FontWeight.bold)),
                                InkWell(onTap: () => speak('${x.name}. ${x.subtitle}'), child: const Padding(padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.volume_up, size: 13, color: green), SizedBox(width: 2), Text('استماع', style: TextStyle(fontSize: 9, color: green, fontWeight: FontWeight.w900))]))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 17),
        const Text('أحدث الإعلانات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 7),
        feed(locationFilteredAds),
        if (hasMoreAds || loadingMoreAds) _loadMoreButton(),
        ],
      ],
    ),
  );

  Widget searchPage() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 3, 12, 9),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: category,
                    decoration: const InputDecoration(labelText: 'القسم', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('كل الأقسام')),
                      ...marketCategories.map((x) => DropdownMenuItem<String?>(value: x.id, child: Text(x.name))),
                    ],
                    onChanged: (v) => setState(() => category = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: TextField(decoration: const InputDecoration(labelText: 'المدينة', isDense: true, border: OutlineInputBorder()), onChanged: (v) => setState(() => city = v))),
              ],
            ),
            Align(alignment: Alignment.centerRight, child: Text(searchLat == null ? 'اختر موقع البحث من الخريطة لتفعيل فلترة المسافة. الإعلانات القديمة بلا إحداثيات تبقى ظاهرة.' : 'تُخفى الإعلانات ذات الإحداثيات خارج ${radiusKm.round()} كم، وتبقى الإعلانات القديمة ظاهرة مع تنبيه.', style: const TextStyle(fontSize: 10, color: Colors.deepOrange))),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() { category = null; city = ''; search = ''; searchBox.clear(); }),
                child: const Text('مسح الفلاتر'),
              ),
            ),
          ],
        ),
      ),
      Expanded(child: SingleChildScrollView(child: Column(children: [
        feed(results),
        if (hasMoreAds || loadingMoreAds) _loadMoreButton(),
      ]))),
    ],
  );

  Widget favoritesPage() {
    final rows = locationFilteredAds.where((x) => fav.contains(x.id)).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [const Text('المفضلة ❤️', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), if (rows.isEmpty) const Text('لا توجد إعلانات محفوظة'), feed(rows)]);
  }

  Widget feed(List<MarketListing> rows) {
    if (busy && rows.isEmpty) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(25), child: Text('لا توجد إعلانات حالياً', textAlign: TextAlign.center));
    return ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (c, i) {
      final x = rows[i], cat = MarketCategory.byId(x.category);
      return Card(child: ListTile(
        contentPadding: const EdgeInsets.all(8), leading: SizedBox(width: 76, height: 76, child: x.photos.isEmpty ? Center(child: Text(cat.emoji, style: const TextStyle(fontSize: 30))) : Image.network(x.photos.first, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(cat.emoji)))),
        title: Row(children: [Expanded(child: Text(x.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))), IconButton(visualDensity: VisualDensity.compact, onPressed: () => speak(x.title + '. ' + x.description), icon: const Icon(Icons.volume_up, size: 18), tooltip: 'استمع')]),
        subtitle: Text(x.priceLabel + '\n' + x.location + (x.lat == null || x.lng == null ? '\nبدون موقع دقيق' : ''), style: const TextStyle(color: green, fontWeight: FontWeight.bold)),
        trailing: IconButton(onPressed: () => toggle(x.id), icon: Icon(fav.contains(x.id) ? Icons.favorite : Icons.favorite_border, color: fav.contains(x.id) ? Colors.red : null)),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdDetailPage(ad: x, favorite: fav.contains(x.id), onFavorite: () => toggle(x.id)))),
      ));
    });
  }

  Widget chatsPage() => api.user == null
      ? Center(child: FilledButton(onPressed: () async { if (await requireLogin() && mounted) setState(() => tab = 3); }, child: const Text('تسجيل الدخول لعرض الرسائل')))
      : FutureBuilder<List<Map<String, dynamic>>>(future: api.conversations(), builder: (c, s) {
    if (s.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (s.hasError) return Center(child: Text(_cleanError(s.error)));
    final rows = s.data ?? [];
    if (rows.isEmpty) return const Center(child: Text('لا توجد محادثات بعد'));
    return ListView(children: rows.map((r) {
      final buyer = r['buyer_id'] == api.user?.id;
      return ListTile(
        leading: const Icon(Icons.chat),
        title: FutureBuilder<String>(future: api.conversationTitle(r), builder: (context, title) => Text(title.data ?? 'جارٍ تحميل الإعلان...', maxLines: 1, overflow: TextOverflow.ellipsis)),
        subtitle: Text((buyer ? 'أنت المشتري' : 'أنت البائع') + ' • ' + r['created_at'].toString()),
        onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(id: r['id'] as String))); },
      );
    }).toList());
  });

  Widget accountPage() {
    final user = api.user;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final displayName = (metadata['full_name'] ?? metadata['name'] ?? metadata['display_name'] ?? '').toString().trim();
    return ListView(padding: const EdgeInsets.all(16), children: [
      const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 38)),
      if (user == null) ...[
        const Center(child: Text('تتصفح كزائر', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        const ListTile(leading: Icon(Icons.person_outline), title: Text('تتصفح كزائر'), subtitle: Text('تسجيل الدخول مطلوب فقط عند إضافة إعلان أو مراسلة بائع')),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: () async { final ok = await auth(); if (mounted && ok) setState(() {}); }, icon: const Icon(Icons.login), label: const Text('تسجيل الدخول'), style: FilledButton.styleFrom(backgroundColor: green, minimumSize: const Size.fromHeight(50))),
      ] else ...[
        Center(child: Text(displayName.isEmpty ? 'حسابي' : displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        Center(child: Text(user.email ?? '', style: const TextStyle(color: Colors.black54))),
        ListTile(leading: const Icon(Icons.inventory), title: const Text('إعلاناتي'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAdsPage()))),
        ListTile(leading: const Icon(Icons.logout), title: const Text('تسجيل الخروج'), onTap: () async { await Supabase.instance.client.auth.signOut(); if (mounted) setState(() => tab = 0); }),
      ],
      const Divider(), const ListTile(title: Text('السوق العربي - By Hicham Jandali'), subtitle: Text('نسخة Flutter')),
    ]);
  }
}

class AdDetailPage extends StatefulWidget {
  final MarketListing ad; final bool favorite; final VoidCallback onFavorite;
  const AdDetailPage({super.key, required this.ad, required this.favorite, required this.onFavorite});
  @override State<AdDetailPage> createState() => _AdDetailPageState();
}
class _AdDetailPageState extends State<AdDetailPage> {
  int active = 0; bool waiting = false;
  final tts = FlutterTts();
  @override void dispose() { tts.stop(); super.dispose(); }
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
        OutlinedButton.icon(onPressed: () async { try { await tts.setLanguage('ar-SA'); await tts.speak('${x.title}. ${x.description}'); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تشغيل الاستماع: $e'))); } }, icon: const Icon(Icons.volume_up), label: const Text('استماع لوصف الإعلان')),
        FilledButton.icon(onPressed: waiting ? null : () async {
          if (MarketService.instance.user == null) {
            final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => const AuthDialog());
            if (!mounted || ok != true || MarketService.instance.user == null) return;
          }
          setState(() => waiting = true);
          try { final id = await MarketService.instance.openConversation(x); if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(id: id))); }
          catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(e)))); }
          finally { if (mounted) setState(() => waiting = false); }
        }, icon: const Icon(Icons.message), label: const Text('راسل البائع')),
      ]),
    );
  }
}

class AddAdPage extends StatefulWidget {
  final bool voiceFirst;
  const AddAdPage({super.key, this.voiceFirst = false});
  @override
  State<AddAdPage> createState() => _AddAdPageState();
}

class _AddAdPageState extends State<AddAdPage> {
  final picker = ImagePicker();
  final voice = stt.SpeechToText();
  bool recording = false;
  bool categorySelected = false;
  final title = TextEditingController(), desc = TextEditingController(), city = TextEditingController(), district = TextEditingController(), phone = TextEditingController(), price = TextEditingController();
  final List<XFile> photos = [];
  final Map<String, Uint8List> previewCache = {};
  final Map<String, ({Uint8List bytes, String name})> uploadCache = {};
  final Map<String, TextEditingController> detailControllers = {};
  LatLng? adPoint;
  String category = 'houses', currency = 'SYP';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.voiceFirst) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) dictateDescription(); });
    }
  }

  @override
  void dispose() {
    voice.stop();
    title.dispose(); desc.dispose(); city.dispose(); district.dispose(); phone.dispose(); price.dispose();
    for (final controller in detailControllers.values) { controller.dispose(); }
    super.dispose();
  }

  Future<void> dictateDescription() async {
    try {
      final ok = await voice.initialize(
        onStatus: (v) { if (mounted) setState(() => recording = v == 'listening'); },
        onError: (_) { if (mounted) setState(() => recording = false); },
      );
      if (!mounted) return;
      if (!ok) { msg('التعرف الصوتي غير متاح على هذا الجهاز'); return; }
      setState(() => recording = true);
      await voice.listen(localeId: 'ar_SA', onResult: (r) { if (!mounted) return; desc.text = r.recognizedWords; setState(() {}); });
    } catch (_) {
      if (mounted) { setState(() => recording = false); msg('تعذر تشغيل الميكروفون'); }
    }
  }

  void msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  static const Map<String, List<String>> _categoryFields = {
    'houses':['نوع العقار','نوع العرض (بيع/إيجار)','المساحة','عدد الغرف','عدد الحمامات','الطابق','عدد الطوابق','حالة العقار','الملكية/الطابو','التدفئة','الكهرباء والماء'],
    'cars':['الماركة','الموديل','سنة الصنع','عدد الكيلومترات','نوع الوقود','ناقل الحركة','سعة المحرك','حالة السيارة','نوع الهيكل','بلد المنشأ'],
    'free':['نوع الغرض','الماركة أو الوصف','حالة الغرض','العدد','طريقة الاستلام','المدينة أو المنطقة'],
    'jobs':['المسمى الوظيفي','مجال العمل','نوع الدوام','الراتب','ساعات العمل','الخبرة المطلوبة','المؤهل العلمي','مكان العمل'],
    'clothes':['نوع الملابس','المقاس','الفئة (رجالي/نسائي/أطفال)','الحالة','اللون','الماركة','العدد'],
    'phones':['الماركة','الموديل','سعة التخزين','الذاكرة العشوائية RAM','حالة الجهاز','صحة البطارية','اللون','الملحقات'],
    'animals':['نوع الحيوان','العمر','العدد','السلالة','الجنس','الحالة الصحية','مكان التسليم'],
    'services':['نوع الخدمة','المهنة','سنوات الخبرة','نطاق الخدمة','أيام العمل','هل يوجد انتقال للزبون','السعر أو طريقة الحساب'],
    'furniture':['نوع الأثاث','الخامة','الحالة','الأبعاد','اللون','العدد','مكان الاستلام'],
    'bikes':['الماركة','الموديل','سنة الصنع','سعة المحرك','عدد الكيلومترات','الحالة','نوع الوقود'],
    'kitchen':['نوع الأداة','المادة','الحالة','العدد','الماركة','المقاس أو السعة'],
  };
  List<String> get _fieldsForCategory => _categoryFields[category] ?? const [];
  TextEditingController _detailController(String field) => detailControllers.putIfAbsent('$category::$field', () => TextEditingController());
  String _descriptionWithDetails() {
    final values = _fieldsForCategory.map((field) => MapEntry(field, _detailController(field).text.trim())).where((e) => e.value.isNotEmpty).toList();
    final details = values.map((e) => '${e.key}: ${e.value}').join('\n');
    final base = desc.text.trim();
    return details.isEmpty ? base : '$base\n\nتفاصيل القسم:\n$details';
  }
  Widget _categorySpecificFields() => Column(children: [
    const Align(alignment: Alignment.centerRight, child: Padding(padding: EdgeInsets.only(top: 8), child: Text('معلومات خاصة بهذا القسم', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)))),
    for (final field in _fieldsForCategory) TextField(controller: _detailController(field), decoration: InputDecoration(labelText: field)),
  ]);

  Future<({Uint8List bytes, String name})> _photoUploadData(XFile photo) async {
    final originalBytes = await photo.readAsBytes();
    final mimeType = lookupMimeType(photo.name, headerBytes: originalBytes)?.toLowerCase();
    final extension = photo.name.contains('.')
        ? photo.name.split('.').last.toLowerCase()
        : '';
    final isHeic = mimeType == 'image/heic' ||
        mimeType == 'image/heif' ||
        extension == 'heic' ||
        extension == 'heif';
    if (!isHeic) {
      return (bytes: originalBytes, name: photo.name);
    }

    // Supabase Storage rejects image/heic in this project: convert the actual
    // image bytes to JPEG before preview, test upload, or publishing.
    final jpegBytes = await FlutterImageCompress.compressWithList(
      originalBytes,
      format: CompressFormat.jpeg,
      quality: 95,
      keepExif: false,
    );
    if (jpegBytes.isEmpty) {
      throw Exception('تعذر تحويل صورة HEIC إلى JPEG');
    }
    final dot = photo.name.lastIndexOf('.');
    final baseName = dot > 0 ? photo.name.substring(0, dot) : photo.name;
    return (bytes: Uint8List.fromList(jpegBytes), name: '$baseName.jpg');
  }

  Future<void> _cachePhoto(XFile photo) async {
    final prepared = await _photoUploadData(photo);
    uploadCache[photo.path] = prepared;
    previewCache[photo.path] = prepared.bytes;
  }

  Future<void> album() async {
    try {
      final selected = await picker.pickMultiImage();
      if (!mounted || selected.isEmpty) return;
      final accepted = selected.take(8 - photos.length).toList();
      final added = <XFile>[];
      for (final photo in accepted) {
        try { await _cachePhoto(photo); added.add(photo); } catch (_) {}
      }
      if (!mounted) return;
      setState(() => photos.addAll(added));
      if (added.length < accepted.length) msg('تعذر تجهيز إحدى الصور، يمكنك اختيارها مرة أخرى');
      if (selected.length > accepted.length) msg('الحد الأقصى 8 صور');
    } catch (_) {
      if (mounted) msg('تعذر اختيار الصور من الألبوم، حاول مرة أخرى');
    }
  }

  Future<void> camera() async {
    try {
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo == null || !mounted) return;
      if (photos.length >= 8) { msg('الحد الأقصى 8 صور'); return; }
      await _cachePhoto(photo);
      if (mounted) setState(() => photos.add(photo));
    } catch (_) {
      if (mounted) msg('تعذر التقاط الصورة، حاول مرة أخرى');
    }
  }

  Future<void> map() async {
    final r = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (_) => const MapPage()));
    if (r != null) { city.text = (r['city'] ?? '').toString(); district.text = (r['district'] ?? '').toString(); adPoint = LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()); setState(() {}); }
  }

  Future<void> testPhotoUpload() async {
    if (photos.isEmpty) { msg('اختر صورة واحدة على الأقل من الألبوم أولاً'); return; }
    setState(() => busy = true);
    final storage = Supabase.instance.client.storage.from('market-photos');
    final uploadedPaths = <String>[];
    final testFolder = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      for (var i = 0; i < photos.length; i++) {
        final prepared = uploadCache[photos[i].path] ?? await _photoUploadData(photos[i]);
        final extension = prepared.name.contains('.')
            ? prepared.name.split('.').last.toLowerCase()
            : 'jpg';
        final path = '__photo_test__/' + testFolder + '/' + i.toString() + '_' +
            DateTime.now().microsecondsSinceEpoch.toString() + '.' + extension;
        await storage.uploadBinary(
          path,
          prepared.bytes,
          fileOptions: FileOptions(
            contentType: lookupMimeType(path) ?? 'image/jpeg',
            upsert: false,
          ),
        );
        uploadedPaths.add(path);
      }
      await storage.remove(uploadedPaths);
      if (mounted) msg('نجح رفع ' + uploadedPaths.length.toString() + ' صورة إلى الخادم، ثم حُذفت ملفات الاختبار. لم يتم نشر إعلان.');
    } catch (e) {
      if (uploadedPaths.isNotEmpty) {
        try { await storage.remove(uploadedPaths); } catch (_) {}
      }
      if (mounted) msg('فشل اختبار رفع الصور: ' + _cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> publish() async {
    // The publish action is always visible. If the visitor is not authenticated,
    // request sign-in here before uploading any permanent listing photos.
    if (MarketService.instance.user == null) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AuthDialog(),
      );
      if (!mounted || ok != true || MarketService.instance.user == null) return;
    }
    if (photos.isEmpty) { msg('أضف صورة واحدة على الأقل'); return; }
    if (adPoint == null) { msg('اختر موقع الإعلان من الخريطة قبل النشر'); return; }
    setState(() => busy = true);
    try {
      final bytes = <Uint8List>[], names = <String>[];
      for (final photo in photos) {
        final prepared = uploadCache[photo.path] ?? await _photoUploadData(photo);
        bytes.add(prepared.bytes);
        names.add(prepared.name);
      }
      final id = await MarketService.instance.publish(
        title: title.text,
        description: _descriptionWithDetails(),
        category: category,
        city: city.text,
        district: district.text,
        phone: phone.text,
        price: category == 'free' ? 0 : num.tryParse(price.text),
        currency: currency,
        photoBytes: bytes,
        photoNames: names,
        lat: adPoint!.latitude,
        lng: adPoint!.longitude,
      );
      final saved = await Supabase.instance.client
          .from('market_listings')
          .select()
          .eq('id', id)
          .single();
      final listing = MarketListing.fromMap(saved);
      if (!mounted) return;
      msg('تم نشر الإعلان');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdDetailPage(
            ad: listing,
            favorite: false,
            onFavorite: () {},
          ),
        ),
      );
    } catch (e) {
      if (mounted) msg('تعذر نشر الإعلان: ${_cleanError(e)}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _categoryPicker() => ListView(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
    children: [
      const Text('ماذا تريد أن تعرض؟', textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      const Text('اختر القسم بصورة كبيرة، سنجهز لك نموذج مخصص مع حقول وصف المنتج، السعر، المكان', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.35)),
      const SizedBox(height: 14),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: marketCategories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: 230, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemBuilder: (c, i) {
          final x = marketCategories[i];
          final tones = [const Color(0xFFFFF1E8), const Color(0xFFEAF5EC), const Color(0xFFFFF8DF), const Color(0xFFEAF1FF), const Color(0xFFFFEDF1), const Color(0xFFEAF8F8)];
          return InkWell(
            onTap: () => setState(() { category = x.id; categorySelected = true; }),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8E8E8))),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(height: 91, color: tones[i % tones.length], alignment: Alignment.center, child: Text(x.emoji, style: const TextStyle(fontSize: 49))),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                          Text(x.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black54, height: 1.2)),
                          const Row(
                            children: [
                              Icon(Icons.photo_camera_outlined, size: 13, color: green),
                              SizedBox(width: 3),
                              Text('أضف ٤ صور', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: green)),
                              SizedBox(width: 4),
                              Text('• المكان', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black45)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ],
  );

  Widget _photoPreview() => Column(
    children: [
      Container(
        height: 235,
        width: double.infinity,
        decoration: const BoxDecoration(color: Color(0xFFF3F3F3)),
        alignment: Alignment.center,
        child: photos.isEmpty
            ? const Text('اختر صور الإعلان', style: TextStyle(color: Colors.black45))
            : Image.memory(
                previewCache[photos.first.path] ?? Uint8List(0),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, size: 55, color: Colors.black26),
              ),
      ),
      if (photos.isNotEmpty)
        SizedBox(
          height: 91,
          child: ReorderableListView(
            scrollDirection: Axis.horizontal,
            onReorder: (a, b) {
              setState(() {
                if (b > a) b--;
                final p = photos.removeAt(a);
                photos.insert(b, p);
              });
            },
            children: [
              for (var i = 0; i < photos.length; i++)
                Container(
                  key: ValueKey(photos[i].path),
                  width: 82,
                  margin: const EdgeInsets.all(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() { final p = photos.removeAt(i); photos.insert(0, p); }),
                        child: Image.memory(
                          previewCache[photos[i].path] ?? Uint8List(0),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEAEAEA), child: Icon(Icons.image_not_supported_outlined, color: Colors.black38)),
                        ),
                      ),
                      Positioned(
                        right: 3,
                        top: 3,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            final removed = photos.removeAt(i);
                            previewCache.remove(removed.path);
                            uploadCache.remove(removed.path);
                          }),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.close, color: Colors.white, size: 15),
                          ),
                        ),
                      ),
                      Positioned(left: 3, bottom: 3, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: i == 0 ? green : Colors.black54, borderRadius: BorderRadius.circular(8)), child: Text(i == 0 ? 'الغلاف' : '${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ],
  );

  Widget _formPage() => ListView(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
    children: [
      Row(
        children: [
          Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFEAF5EC), borderRadius: BorderRadius.circular(13)), child: Text(MarketCategory.byId(category).emoji, style: const TextStyle(fontSize: 27))),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(MarketCategory.byId(category).name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            Text(MarketCategory.byId(category).subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ])),
          TextButton(onPressed: () => setState(() => categorySelected = false), child: const Text('تغيير')),
        ],
      ),
      const SizedBox(height: 9),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('الصور (${photos.length}/8) • الأولى هي الغلاف', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          const Text('حتى ٨ صور', style: TextStyle(fontSize: 10, color: Colors.black45)),
        ],
      ),
      const SizedBox(height: 6),
      _photoPreview(),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: OutlinedButton.icon(onPressed: album, icon: const Icon(Icons.photo_library_outlined), label: const Text('الألبوم'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(onPressed: camera, icon: const Icon(Icons.camera_alt_outlined), label: const Text('الكاميرا'))),
        ],
      ),
      TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان الإعلان')),
      TextField(controller: desc, maxLines: 4, decoration: const InputDecoration(labelText: 'التفاصيل والوصف')),
      _categorySpecificFields(),
      OutlinedButton.icon(onPressed: dictateDescription, icon: Icon(recording ? Icons.mic : Icons.mic_none, color: green), label: Text(recording ? 'يتم الاستماع...' : 'أضف إعلانك بالصوت - تحدث لوصف الإعلان')),
      Row(
        children: [
          Expanded(child: TextField(controller: city, decoration: const InputDecoration(labelText: 'المدينة'))),
          IconButton(onPressed: map, icon: const Icon(Icons.map_outlined, color: green)),
        ],
      ),
      TextField(controller: district, decoration: const InputDecoration(labelText: 'الحي أو المنطقة')),
      ListTile(leading: const Icon(Icons.map, color: green), title: Text(adPoint == null ? 'اختر موقع الإعلان من الخريطة' : 'تم تحديد الموقع على الخريطة'), subtitle: Text(adPoint == null ? 'مطلوب لحفظ الإحداثيات الدقيقة' : '${adPoint!.latitude.toStringAsFixed(5)}, ${adPoint!.longitude.toStringAsFixed(5)}'), trailing: const Icon(Icons.chevron_right), onTap: map),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف (اختياري)')),
      if (category != 'free')
        Row(
          children: [
            Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر'))),
            DropdownButton<String>(value: currency, items: const [DropdownMenuItem(value: 'SYP', child: Text('ل.س')), DropdownMenuItem(value: 'USD', child: Text('USD'))], onChanged: (v) => setState(() => currency = v ?? 'SYP')),
          ],
        )
      else
        const ListTile(leading: Icon(Icons.card_giftcard, color: green), title: Text('السعر: مجاناً', style: TextStyle(fontWeight: FontWeight.w900))),
      const SizedBox(height: 13),
      OutlinedButton(
        onPressed: busy ? null : testPhotoUpload,
        style: OutlinedButton.styleFrom(
          foregroundColor: green,
          minimumSize: const Size.fromHeight(40),
          side: BorderSide(color: green.withOpacity(0.55)),
        ),
        child: Text(busy ? 'جارٍ اختبار رفع الصور...' : 'اختبار رفع الصور إلى الخادم'),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: busy ? null : publish,
        style: FilledButton.styleFrom(
          backgroundColor: green,
          minimumSize: const Size.fromHeight(54),
        ),
        child: Text(busy ? 'جارٍ النشر...' : 'نشر الإعلان'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(title: const Text('إضافة إعلان'), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
    body: categorySelected ? _formPage() : _categoryPicker(),
  );
}

class MapPage extends StatefulWidget { const MapPage({super.key}); @override State<MapPage> createState() => _MapPageState(); }
class _MapPageState extends State<MapPage> {
  LatLng point = const LatLng(51.3127, 9.4797); String city = 'كاسل، ألمانيا', district = ''; bool busy = false; double radius = 25;
  final placeSearch = TextEditingController();
  @override void dispose() { placeSearch.dispose(); super.dispose(); }
  Future<void> searchPlace() async {
    final q = placeSearch.text.trim(); if (q.isEmpty) return;
    setState(() => busy = true);
    try {
      final u = Uri.https('nominatim.openstreetmap.org', '/search', {'format':'jsonv2','q':q,'limit':'1','addressdetails':'1','accept-language':'ar'});
      final r = await http.get(u, headers: {'User-Agent':'JandaliArabMarket/1.0'});
      if (r.statusCode == 200) { final rows = jsonDecode(r.body) as List; if (rows.isNotEmpty) { final a = rows.first as Map<String,dynamic>; point = LatLng(double.parse(a['lat'].toString()),double.parse(a['lon'].toString())); final ad = (a['address'] ?? {}) as Map<String,dynamic>; city = (ad['city'] ?? ad['town'] ?? ad['village'] ?? a['display_name'] ?? q).toString(); district = (ad['suburb'] ?? ad['neighbourhood'] ?? '').toString(); } else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم نجد المكان، اكتب المدينة مع الدولة'))); }
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر البحث عن الموقع الآن'))); }
    finally { if (mounted) setState(() => busy = false); }
  }
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
      CircleLayer(circles: [CircleMarker(point: point, radius: radius * 1000, useRadiusInMeter: true, color: green.withOpacity(0.13), borderColor: green, borderStrokeWidth: 2)]),
      MarkerLayer(markers: [Marker(point: point, width: 44, height: 44, child: const Icon(Icons.location_pin, color: Colors.red, size: 42))]),
    ]),
    Positioned(top: 12, left: 12, right: 12, child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [Expanded(child: TextField(controller: placeSearch, decoration: const InputDecoration(hintText: 'اكتب مدينة وبلداً، مثل كاسل، ألمانيا', isDense: true), onSubmitted: (_) => searchPlace())), IconButton(onPressed: busy ? null : searchPlace, icon: const Icon(Icons.search)), IconButton(onPressed: busy ? null : locate, icon: const Icon(Icons.my_location))])))),
    Positioned(bottom: 16, left: 12, right: 12, child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(busy ? 'جارٍ تحديد العنوان...' : city + ' ' + district, style: const TextStyle(fontWeight: FontWeight.bold)),
      Row(children: [const Text('نطاق البحث'), Expanded(child: Slider(value: radius, min: 1, max: 50, divisions: 49, label: '${radius.round()} كم', onChanged: (v) => setState(() => radius = v))), Text('${radius.round()} كم')]),
      FilledButton(onPressed: busy ? null : () => Navigator.pop(context, {'city': city, 'district': district, 'radius': radius, 'lat': point.latitude, 'lng': point.longitude}), child: const Text('تأكيد موقع البحث')),
    ])))),
  ]));
}class ChatPage extends StatefulWidget { final String id; const ChatPage({super.key, required this.id}); @override State<ChatPage> createState() => _ChatPageState(); }
class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  bool sending = false;
  late Future<List<Map<String, dynamic>>> messageFuture;
  Timer? refreshTimer;
  @override void initState() {
    super.initState();
    messageFuture = MarketService.instance.messages(widget.id);
    refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => messageFuture = MarketService.instance.messages(widget.id));
    });
  }
  @override void dispose() { refreshTimer?.cancel(); input.dispose(); super.dispose(); }
  Future<void> send() async {
    if (input.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await MarketService.instance.sendMessage(widget.id, input.text);
      input.clear();
      if (mounted) setState(() => messageFuture = MarketService.instance.messages(widget.id));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر إرسال الرسالة. حاول مرة أخرى')));
    } finally { if (mounted) setState(() => sending = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('محادثة خاصة')), body: Column(children: [
    Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(future: messageFuture, builder: (c, s) {
      if (s.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (s.hasError) return Center(child: Text(_cleanError(s.error)));
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
    if (s.hasError) return Center(child: Text(_cleanError(s.error)));
    final rows = s.data ?? [];
    return ListView(children: rows.map((x) => ListTile(
      title: Text(x.title), subtitle: Text(x.location + ' • ' + x.status),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'edit') {
            final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditAdPage(ad: x)));
            if (changed == true && mounted) setState(() => future = MarketService.instance.myListings());
            return;
          }
          try {
            if (v == 'close') await MarketService.instance.closeListing(x.id);
            if (v == 'delete') await MarketService.instance.deleteListing(x.id);
            if (mounted) setState(() => future = MarketService.instance.myListings());
          } catch (_) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تنفيذ العملية. حاول مرة أخرى')));
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('تعديل الإعلان')),
          PopupMenuItem(value: 'close', child: Text('إيقاف')),
          PopupMenuItem(value: 'delete', child: Text('حذف')),
        ],
      ),
    )).toList());
  }));
}

class _EditableAdPhoto {
  final String? url;
  final Uint8List? bytes;
  final String? name;
  const _EditableAdPhoto.existing(this.url) : bytes = null, name = null;
  const _EditableAdPhoto.added(this.bytes, this.name) : url = null;
  bool get isNew => bytes != null;
}

class EditAdPage extends StatefulWidget {
  final MarketListing ad;
  const EditAdPage({super.key, required this.ad});
  @override State<EditAdPage> createState() => _EditAdPageState();
}
class _EditAdPageState extends State<EditAdPage> {
  final picker = ImagePicker();
  late final title = TextEditingController(text: widget.ad.title);
  late final description = TextEditingController(text: widget.ad.description);
  late final city = TextEditingController(text: widget.ad.city);
  late final district = TextEditingController(text: widget.ad.district ?? '');
  late final phone = TextEditingController(text: widget.ad.phone ?? '');
  late final price = TextEditingController(text: widget.ad.price?.toString() ?? '');
  late String currency = widget.ad.currency;
  late final List<_EditableAdPhoto> photos =
      widget.ad.photos.map((url) => _EditableAdPhoto.existing(url)).toList();
  bool saving = false;
  bool picking = false;
  @override void dispose() {
    title.dispose(); description.dispose(); city.dispose(); district.dispose(); phone.dispose(); price.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _addPhotos({required bool camera}) async {
    if (picking || saving) return;
    final remaining = 8 - photos.length;
    if (remaining <= 0) { _message('الحد الأقصى 8 صور'); return; }
    setState(() => picking = true);
    try {
      final selected = camera ? await picker.pickImage(source: ImageSource.camera) : null;
      final List<XFile> files;
      if (camera) {
        files = selected == null ? <XFile>[] : <XFile>[selected];
      } else {
        files = await picker.pickMultiImage(imageQuality: 100);
      }
      if (!mounted || files.isEmpty) return;
      final accepted = files.take(remaining).toList();
      final added = <_EditableAdPhoto>[];
      for (final file in accepted) {
        try {
          final bytes = await file.readAsBytes();
          added.add(_EditableAdPhoto.added(bytes, file.name));
        } catch (_) {
          _message('تعذر قراءة إحدى الصور، حاول اختيارها مرة أخرى');
        }
      }
      if (!mounted) return;
      setState(() => photos.addAll(added));
      if (files.length > accepted.length) _message('تمت إضافة الصور ضمن الحد الأقصى وهو 8 صور');
    } catch (_) {
      _message(camera ? 'تعذر التقاط الصورة' : 'تعذر اختيار الصور من الألبوم');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Widget _photoImage(_EditableAdPhoto photo, {BoxFit fit = BoxFit.cover}) {
    if (photo.isNew) {
      return Image.memory(photo.bytes!, fit: fit,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEAEAEA), child: Icon(Icons.broken_image_outlined)));
    }
    return Image.network(photo.url!, fit: fit,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEAEAEA), child: Icon(Icons.broken_image_outlined)));
  }

  Widget _photosEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('صور الإعلان (${photos.length}/8)', style: const TextStyle(fontWeight: FontWeight.w900)),
        const Text('الأولى هي الغلاف', style: TextStyle(fontSize: 11, color: Colors.black54)),
      ]),
      const SizedBox(height: 8),
      Container(
        height: 210, alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(12)),
        child: photos.isEmpty ? const Text('لا توجد صور') : _photoImage(photos.first, fit: BoxFit.contain),
      ),
      if (photos.isNotEmpty) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ReorderableListView(
            scrollDirection: Axis.horizontal,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = photos.removeAt(oldIndex);
                photos.insert(newIndex, item);
              });
            },
            children: [
              for (var i = 0; i < photos.length; i++)
                Container(
                  key: ValueKey(photos[i].isNew ? 'new-${identityHashCode(photos[i])}' : photos[i].url),
                  width: 88,
                  margin: const EdgeInsets.all(4),
                  child: Stack(fit: StackFit.expand, children: [
                    GestureDetector(
                      onTap: () => setState(() {
                        final item = photos.removeAt(i);
                        photos.insert(0, item);
                      }),
                      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: _photoImage(photos[i])),
                    ),
                    Positioned(right: 0, top: 0, child: Material(
                      color: Colors.white.withOpacity(0.9), shape: const CircleBorder(),
                      child: IconButton(
                        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                        padding: EdgeInsets.zero,
                        tooltip: 'حذف الصورة',
                        onPressed: saving ? null : () => setState(() => photos.removeAt(i)),
                        icon: const Icon(Icons.close, color: Colors.red, size: 19),
                      ),
                    )),
                    Positioned(left: 3, bottom: 3, child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: i == 0 ? green : Colors.black54, borderRadius: BorderRadius.circular(7)),
                      child: Text(i == 0 ? 'الغلاف' : '${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    )),
                  ]),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: saving || picking || photos.length >= 8 ? null : () => _addPhotos(camera: false),
          icon: const Icon(Icons.photo_library_outlined), label: const Text('إضافة من الألبوم'),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: saving || picking || photos.length >= 8 ? null : () => _addPhotos(camera: true),
          icon: const Icon(Icons.camera_alt_outlined), label: const Text('الكاميرا'),
        )),
      ]),
      const Text('اسحب الصور لتغيير ترتيبها، أو اضغط صورة لتعيينها غلافاً. لا تُحذف الصورة القديمة من التخزين إلا بعد الضغط على ❌ ثم حفظ التعديلات.',
        style: TextStyle(fontSize: 11, color: Colors.black54)),
    ],
  );

  Future<void> save() async {
    if (saving) return;
    if (photos.isEmpty) { _message('يجب إبقاء صورة واحدة على الأقل للإعلان'); return; }
    setState(() => saving = true);
    try {
      final newPhotos = photos.where((photo) => photo.isNew).toList();
      final newPhotoBytes = newPhotos.map((photo) => photo.bytes!).toList();
      final newPhotoNames = newPhotos.map((photo) => photo.name!).toList();
      final photoOrder = photos.map((photo) {
        if (photo.isNew) return -(newPhotos.indexOf(photo) + 1);
        return widget.ad.photos.indexOf(photo.url!);
      }).toList();
      await MarketService.instance.updateListing(
        id: widget.ad.id,
        title: title.text,
        description: description.text,
        city: city.text,
        district: district.text,
        phone: phone.text,
        price: widget.ad.category == 'free' ? 0 : num.tryParse(price.text),
        currency: currency,
        originalPhotoUrls: widget.ad.photos,
        photoOrder: photoOrder,
        newPhotoBytes: newPhotoBytes,
        newPhotoNames: newPhotoNames,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر حفظ التعديلات أو رفع الصور. لم تُحذف الصور القديمة من التخزين قبل نجاح الحفظ.')));
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تعديل الإعلان')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان الإعلان')),
      TextField(controller: description, maxLines: 5, decoration: const InputDecoration(labelText: 'الوصف والتفاصيل')),
      TextField(controller: city, decoration: const InputDecoration(labelText: 'المدينة')),
      TextField(controller: district, decoration: const InputDecoration(labelText: 'الحي')),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
      if (widget.ad.category != 'free') ...[
        TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')),
        DropdownButton<String>(value: currency, items: const [DropdownMenuItem(value: 'SYP', child: Text('ل.س')), DropdownMenuItem(value: 'USD', child: Text('USD'))], onChanged: saving ? null : (v) => setState(() => currency = v ?? 'SYP')),
      ],
      const SizedBox(height: 16),
      _photosEditor(),
      const SizedBox(height: 16),
      FilledButton(onPressed: saving || picking ? null : save, child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ التعديلات')),
    ]),
  );
}