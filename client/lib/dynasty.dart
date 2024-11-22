import 'package:flutter/widgets.dart';

class Dynasty {
  const Dynasty(this.id);
  final int id;

  @override
  String toString() => '<Dynasty #$id>';
}

class DynastyManager {
  final Map<int, Dynasty> _dynasties = <int, Dynasty>{};
  Dynasty getDynasty(int id) {
    return _dynasties.putIfAbsent(id, () => Dynasty(id));
  }

  Dynasty? get currentDynasty => _currentDynasty;
  Dynasty? _currentDynasty;
  void setCurrentDynastyId(int? id) {
    if (id == null) {
      _currentDynasty = null;
    } else {
      _currentDynasty = getDynasty(id);
    }
  }
}

class DynastyProvider extends InheritedWidget {
  const DynastyProvider({ super.key, required this.dynastyManager, required super.child });

  final DynastyManager dynastyManager;

  static Dynasty? currentDynastyOf(BuildContext context) {
    final DynastyProvider? provider = context.dependOnInheritedWidgetOfExactType<DynastyProvider>();
    assert(provider != null, 'No DynastyProvider found in context');
    return provider!.dynastyManager.currentDynasty;
  }

  @override
  bool updateShouldNotify(DynastyProvider oldWidget) => dynastyManager != oldWidget.dynastyManager;
}
