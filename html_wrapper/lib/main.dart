import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const String marketUrl =
    'https://hichamjandali-gif.github.io/Jandali-Syria-Marketplace/?jandaliNativeApp=1';

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
          onPageFinished: (_) {
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
        await android.setGeolocationEnabled(true);
        await android.setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (request) async {
            if (request.origin != 'https://hichamjandali-gif.github.io') {
              return const GeolocationPermissionsResponse(
                allow: false,
                retain: false,
              );
            }
            final permission = await Permission.locationWhenInUse.request();
            return GeolocationPermissionsResponse(
              allow: permission.isGranted,
              retain: permission.isGranted,
            );
          },
        );
      }

      await controller.loadRequest(Uri.parse(marketUrl));
      if (mounted) setState(() => _controller = controller);
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
          imageQuality: 100,
        );
        return photo == null ? <String>[] : <String>[_fileUri(photo)];
      }

      if (params.mode == FileSelectorMode.openMultiple) {
        final photos = await _picker.pickMultiImage(imageQuality: 100);
        return photos.map(_fileUri).toList(growable: false);
      }

      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
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
