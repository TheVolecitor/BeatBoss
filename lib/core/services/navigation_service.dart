import 'package:flutter/foundation.dart';

class NavigationService with ChangeNotifier {
  bool _canGoBack = false;
  VoidCallback? _onBack;

  bool get canGoBack => _canGoBack;
  VoidCallback? get onBack => _onBack;

  void setBackHandler(VoidCallback? handler) {
    _onBack = handler;
    _canGoBack = handler != null;
    notifyListeners();
  }

  void clearBackHandler() {
    _onBack = null;
    _canGoBack = false;
    notifyListeners();
  }

  bool handleBack() {
    if (_canGoBack && _onBack != null) {
      _onBack!();
      return true;
    }
    return false;
  }
}
