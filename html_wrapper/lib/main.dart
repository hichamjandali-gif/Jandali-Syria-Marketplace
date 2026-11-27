import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const String marketUrl =
    'https://hichamjandali-gif.github.io/Jandali-Syria-Marketplace/?jandaliNativeApp=1&v=20261127-geo-photo';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ArabMarketApp());
}

class ArabMarketApp extends StatelessWidget {
  const ArabMarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'السوق العربي',
      home: MarketWebViewPage(),
    );
  }
}

class MarketWebViewPage extends StatefulWidget {
  const MarketWebViewPage({super.key});

  @override
  State<MarketWebViewPage> createState() => _MarketWebViewPageState();
}

class _MarketWebViewPageState extends State<MarketWebViewPage> {
  final ImagePicker _picker = ImagePicker();
  WebViewController? _controller;
  bool _loading = true;
  bool _failed = false;
  int _progress = 0;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _createWebView();
  }

  Future<void> _createWebView() async {
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'JandaliLocation',
        onMessageReceived: (message) {
          unawaited(_handleNativeLocationRequest(message.message));
        },
      );
      await controller.setBackgroundColor(Colors.white);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && uri.scheme.toLowerCase() == 'https') {
              return NavigationDecision.navigate;
            }
            // Ignore geo:, intent:, chrome:, tel:, file: and all non-HTTPS URLs.
            return NavigationDecision.prevent;
          },
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _failed = false;
                _error = '';
              });
            }
          },
          onPageFinished: (_) async {
            await _installNativeGeolocationBridge(controller);
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.description.contains('ERR_UNKNOWN_URL_SCHEME')) {
              return;
            }
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _failed = true;
                _loading = false;
                _error = error.description;
              });
            }
          },
        ),
      );

      if (controller.platform is AndroidWebViewController) {
        final android = controller.platform as AndroidWebViewController;
        await android.setAllowFileAccess(true);
        await android.setAllowContentAccess(true);
        await android.setOnShowFileSelector(_selectFiles);
        // Location is provided through the native JavaScript bridge.
        await android.setGeolocationEnabled(false);
      }

      if (mounted) setState(() => _controller = controller);
      await controller.loadRequest(Uri.parse(marketUrl));
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _installNativeGeolocationBridge(
    WebViewController controller,
  ) async {
    const script = r'''
      (() => {
        if (window.__jandaliNativeGeoInstalled) return;
        window.__jandaliNativeGeoInstalled = true;
        let nextId = 0;
        const pending = new Map();
        window.__jandaliGeoResolve = (id, latitude, longitude, accuracy) => {
          const callbacks = pending.get(String(id));
          if (!callbacks) return;
          pending.delete(String(id));
          callbacks.success({
            coords: {latitude: Number(latitude), longitude: Number(longitude),
              accuracy: Number(accuracy) || 0, altitude: null,
              altitudeAccuracy: null, heading: null, speed: null},
            timestamp: Date.now()
          });
        };
        window.__jandaliGeoReject = (id, code, message) => {
          const callbacks = pending.get(String(id));
          if (!callbacks) return;
          pending.delete(String(id));
          if (callbacks.failure) callbacks.failure({code, message});
        };
        const request = (success, failure) => {
          const id = String(++nextId);
          pending.set(id, {success, failure});
          if (!window.JandaliLocation || !window.JandaliLocation.postMessage) {
            window.__jandaliGeoReject(id, 2, 'خدمة الموقع غير متاحة داخل التطبيق');
            return id;
          }
          window.JandaliLocation.postMessage(id);
          return id;
        };
        const geolocation = {
          getCurrentPosition(success, failure) { request(success, failure); },
          watchPosition(success, failure) { return Number(request(success, failure)); },
          clearWatch() {}
        };
        try {
          Object.defineProperty(navigator, 'geolocation', {configurable: true, value: geolocation});
        } catch (_) { navigator.geolocation = geolocation; }
      })();
    ''';
    try { await controller.runJavaScript(script); } catch (_) {}
  }

  Future<void> _handleNativeLocationRequest(String requestId) async {
    final id = int.tryParse(requestId.trim());
    if (id == null) return;
    final controller = _controller;
    if (controller == null) return;

    Future<void> reject(int code, String message) async {
      final encodedMessage = jsonEncode(message);
      await controller.runJavaScript(
        "window.__jandaliGeoReject?.('$id', $code, $encodedMessage);",
      );
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await reject(2, 'يرجى تشغيل خدمة الموقع GPS في الهاتف');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        await reject(1, 'لم يتم السماح بإذن الموقع');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        await reject(1, 'إذن الموقع مرفوض نهائياً. فعّله من إعدادات التطبيق');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      await controller.runJavaScript(
        "window.__jandaliGeoResolve?.('$id', ${position.latitude}, ${position.longitude}, ${position.accuracy});",
      );
    } catch (error) {
      await reject(2, 'تعذر تحديد GPS: $error');
    }
  }

  String _fileUri(XFile file) {
    final path = file.path;
    if (path.startsWith('content://') || path.startsWith('file://')) {
      return path;
    }
    return Uri.file(path).toString();
  }

  Future<List<String>> _selectFiles(FileSelectorParams params) async {
    try {
      final accepts = params.acceptTypes.join(',').toLowerCase();
      final acceptsImages =
          accepts.isEmpty || accepts.contains('image/') || accepts.contains('*/*');
      if (!acceptsImages || params.mode == FileSelectorMode.save) {
        return <String>[];
      }

      if (params.isCaptureEnabled) {
        final photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          maxWidth: 1200,
          maxHeight: 1200,
        );
        return photo == null ? <String>[] : <String>[_fileUri(photo)];
      }

      if (params.mode == FileSelectorMode.openMultiple) {
        final photos = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1200, maxHeight: 1200);
        return photos.map(_fileUri).toList(growable: false);
      }

      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
          maxWidth: 1200,
          maxHeight: 1200,
      );
      return photo == null ? <String>[] : <String>[_fileUri(photo)];
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _goBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              if (controller != null && !_failed)
                WebViewWidget(controller: controller),
              if (_failed)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off, size: 42, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text(
                          'تعذر فتح السوق',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(_error, textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _failed = false;
                              _loading = true;
                            });
                            if (_controller != null) {
                              _controller!.reload();
                            } else {
                              _createWebView();
                            }
                          },
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_loading && !_failed)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress / 100,
                    minHeight: 2,
                    color: const Color(0xFF16834A),
                    backgroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
