import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mime/mime.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  }
  runApp(const JandaliPhotoTestApp());
}

class JandaliPhotoTestApp extends StatelessWidget {
  const JandaliPhotoTestApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'السوق العربي - اختبار الصور',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087A43)),
          useMaterial3: true,
        ),
        home: const PhotoTestPage(),
      );
}

class PhotoTestPage extends StatefulWidget {
  const PhotoTestPage({super.key});

  @override
  State<PhotoTestPage> createState() => _PhotoTestPageState();
}

class _PhotoTestPageState extends State<PhotoTestPage> {
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  int _active = 0;
  bool _busy = false;
  bool _frontCamera = false;
  String _status = 'اختر صورة من الألبوم أو التقط صورة بالكاميرا.';
  List<String> _uploadedUrls = [];

  bool get _supabaseReady =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  Future<void> _pickAlbum() async {
    if (_busy) return;
    try {
      final selected = await _picker.pickMultiImage(
        imageQuality: 90,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (!mounted || selected.isEmpty) return;
      setState(() {
        for (final file in selected) {
          if (_photos.length == 8) break;
          _photos.add(file);
        }
        _active = _photos.length - 1;
        _status = 'تم اختيار الصور. افحص المعاينة قبل الرفع.';
      });
    } catch (e) {
      _showError('تعذر فتح الألبوم: $e');
    }
  }

  Future<void> _takePhoto() async {
    if (_busy) return;
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice:
            _frontCamera ? CameraDevice.front : CameraDevice.rear,
        imageQuality: 90,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (!mounted || photo == null) return;
      setState(() {
        if (_photos.length < 8) {
          _photos.add(photo);
          _active = _photos.length - 1;
          _status = 'تم التقاط الصورة.';
        } else {
          _status = 'الحد الأقصى 8 صور.';
        }
      });
    } catch (e) {
      _showError('تعذر تشغيل الكاميرا: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _status = message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
      if (_photos.isEmpty) {
        _active = 0;
      } else if (_active >= _photos.length) {
        _active = _photos.length - 1;
      } else if (index < _active) {
        _active--;
      }
    });
  }

  Future<void> _uploadPhotos() async {
    if (_photos.isEmpty) {
      _showError('اختر صورة واحدة على الأقل أولاً.');
      return;
    }
    if (!_supabaseReady) {
      _showError(
        'اختبار المعاينة جاهز، لكن الرفع يحتاج إعداد SUPABASE_ANON_KEY بشكل آمن.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = 'جارٍ رفع الصور إلى market-photos...';
      _uploadedUrls = [];
    });
    try {
      final storage = Supabase.instance.client.storage.from('market-photos');
      final urls = <String>[];
      for (final photo in _photos) {
        final bytes = await photo.readAsBytes();
        final safeName = photo.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final path =
            'flutter-photo-test/${DateTime.now().microsecondsSinceEpoch}_$safeName';
        final contentType =
            lookupMimeType(photo.name, headerBytes: bytes) ??
            'application/octet-stream';
        await storage.uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
        urls.add(storage.getPublicUrl(path));
      }
      if (!mounted) return;
      setState(() {
        _uploadedUrls = urls;
        _status =
            'اكتمل رفع ${urls.length} صورة إلى bucket market-photos. لم يتم إنشاء إعلان أو تعديل قاعدة البيانات.';
      });
    } catch (e) {
      _showError('فشل رفع الصور: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _photos.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('السوق العربي - اختبار الصور'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.black,
                alignment: Alignment.center,
                child: hasPhoto
                    ? Image.file(
                        File(_photos[_active].path),
                        key: ValueKey(_photos[_active].path),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'تعذر عرض صيغة الصورة في المعاينة على هذا الجهاز.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                    : const Text(
                        'لا توجد صور بعد\nاختر من الألبوم أو افتح الكاميرا',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 17),
                      ),
              ),
            ),
            if (hasPhoto)
              SizedBox(
                height: 104,
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final item = _photos.removeAt(oldIndex);
                      _photos.insert(newIndex, item);
                      if (_active == oldIndex) {
                        _active = newIndex;
                      } else if (oldIndex < _active && newIndex >= _active) {
                        _active--;
                      } else if (oldIndex > _active && newIndex <= _active) {
                        _active++;
                      }
                    });
                  },
                  children: [
                    for (var i = 0; i < _photos.length; i++)
                      Container(
                        key: ValueKey(_photos[i].path),
                        width: 82,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() => _active = i),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: i == _active
                                        ? Colors.green
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Image.file(
                                    File(_photos[i].path),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: InkWell(
                                onTap: () => _removePhoto(i),
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.white,
                                  child: Icon(Icons.close,
                                      size: 16, color: Colors.black),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickAlbum,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('الألبوم'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _takePhoto,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('الكاميرا'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'تبديل الكاميرا الأمامية والخلفية',
                    onPressed: _busy
                        ? null
                        : () => setState(
                            () => _frontCamera = !_frontCamera),
                    icon: const Icon(Icons.flip_camera_android),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _uploadPhotos,
                  child: Text(_busy ? 'جارٍ الرفع...' : 'اختبار رفع الصور'),
                ),
              ),
            ),
            if (_uploadedUrls.isNotEmpty)
              SizedBox(
                height: 68,
                child: ListView(
                  children: [
                    for (final url in _uploadedUrls)
                      SelectableText(
                        url,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 10),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
