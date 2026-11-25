import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'lock.dart';

/// 照片存在 APP 自己的資料夾（documents/photos），事件裡只記檔名
class PhotoStore {
  String? _dir;
  final ImagePicker _picker = ImagePicker();

  Future<void> init() async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}/photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir.path;
  }

  File file(String name) => File('$_dir/$name');

  String _newName() {
    final r = Random().nextInt(1 << 32).toRadixString(36);
    return 'p${DateTime.now().millisecondsSinceEpoch}_$r.jpg';
  }

  Future<String> _import(XFile x) async {
    final name = _newName();
    await File(x.path).copy(file(name).path);
    return name;
  }

  /// 從相簿選多張
  Future<List<String>> pickFromGallery() async {
    appLock.suspendOnce();
    final xs = await _picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    final out = <String>[];
    for (final x in xs) {
      out.add(await _import(x));
    }
    return out;
  }

  /// 拍照
  Future<String?> takePhoto() async {
    appLock.suspendOnce();
    final x = await _picker.pickImage(
        source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    if (x == null) return null;
    return _import(x);
  }

  Future<void> delete(Iterable<String> names) async {
    for (final n in names) {
      try {
        final f = file(n);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}

final PhotoStore photos = PhotoStore();

/// 縮圖
class PhotoThumb extends StatelessWidget {
  final String name;
  final double size;
  final VoidCallback? onTap;
  const PhotoThumb(this.name, {super.key, this.size = 84, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          photos.file(name),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            color: cs.surfaceContainerHigh,
            child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// 一排縮圖（時間軸展開時用）
class PhotoStrip extends StatelessWidget {
  final List<String> names;
  const PhotoStrip(this.names, {super.key});

  @override
  Widget build(BuildContext context) {
    // 用 SingleChildScrollView（而不是 ListView），才能放在 IntrinsicHeight 裡
    return SizedBox(
      height: 84,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (var i = 0; i < names.length; i++)
              Padding(
                padding: EdgeInsets.only(right: i == names.length - 1 ? 0 : 8),
                child: PhotoThumb(names[i], onTap: () => openPhotoViewer(context, names, i)),
              ),
          ],
        ),
      ),
    );
  }
}

void openPhotoViewer(BuildContext context, List<String> names, int index) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => PhotoViewer(names: names, initial: index)),
  );
}

/// 全螢幕看照片，可雙指縮放、左右滑
class PhotoViewer extends StatefulWidget {
  final List<String> names;
  final int initial;
  const PhotoViewer({super.key, required this.names, required this.initial});

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_i + 1} / ${widget.names.length}'),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.names.length,
        onPageChanged: (i) => setState(() => _i = i),
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(child: Image.file(photos.file(widget.names[i]), fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
