import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

String _getProxiedUrl(String url) {
  return url;
}

/// A drop-in replacement for CachedNetworkImage that safely falls back to
/// Image.network (with a CORS proxy) on Flutter Web/WASM.
class UniversalImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  const UniversalImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        _getProxiedUrl(imageUrl),
        fit: fit,
        width: width,
        height: height,
        errorBuilder: errorWidget != null
            ? (context, error, stackTrace) =>
                errorWidget!(context, imageUrl, error)
            : null,
      );
    } else {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        width: width,
        height: height,
        errorWidget: errorWidget,
      );
    }
  }
}

/// A drop-in replacement for CachedNetworkImageProvider
ImageProvider getUniversalImageProvider(String imageUrl) {
  if (kIsWeb) {
    return NetworkImage(_getProxiedUrl(imageUrl));
  } else {
    return CachedNetworkImageProvider(imageUrl);
  }
}
