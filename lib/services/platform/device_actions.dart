import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens links, the dialer or the SMS app.
abstract interface class LinkOpener {
  Future<bool> open(Uri uri);
}

class UrlLinkOpener implements LinkOpener {
  @override
  Future<bool> open(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Asks the user before Viora does something on their behalf.
abstract interface class ActionConfirmer {
  Future<bool> confirm(String title, String message, {String action = 'Continue'});
}

class DialogConfirmer implements ActionConfirmer {
  DialogConfirmer(this.navigatorKey);
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Future<bool> confirm(String title, String message, {String action = 'Continue'}) async {
    final context = navigatorKey.currentContext;
    if (context == null) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    return ok ?? false;
  }
}

class PickedPhoto {
  const PickedPhoto(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
}

abstract interface class PhotoPicker {
  Future<PickedPhoto?> pick({required bool fromCamera});
}

class DevicePhotoPicker implements PhotoPicker {
  final _picker = ImagePicker();

  @override
  Future<PickedPhoto?> pick({required bool fromCamera}) async {
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 82,
    );
    if (file == null) return null;
    return PickedPhoto(await file.readAsBytes(), file.mimeType ?? 'image/jpeg');
  }
}
