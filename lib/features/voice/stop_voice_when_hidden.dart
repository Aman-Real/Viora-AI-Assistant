import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'voice_controller.dart';

/// Ends a live voice session when the app is no longer on screen (home
/// button, app switch, an incoming call), so the mic never stays open unseen.
class StopVoiceWhenHidden extends StatefulWidget {
  const StopVoiceWhenHidden({super.key, required this.child});
  final Widget child;

  @override
  State<StopVoiceWhenHidden> createState() => _StopVoiceWhenHiddenState();
}

class _StopVoiceWhenHiddenState extends State<StopVoiceWhenHidden> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: () => context.read<VoiceController>().stop());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
