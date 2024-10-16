import 'package:flutter/material.dart';

import 'galaxy.dart';
import 'materials.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  _MainAppState createState() => _MainAppState();
}

enum Pane { main, galaxy, materials }

class _MainAppState extends State<MainApp> {
  Pane _pane = Pane.main;

  void _exit() {
    setState(() { _pane = Pane.main; });
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: switch (_pane) {
          Pane.main => MainPane(onSelect: (Pane value) { setState(() { _pane = value; }); }),
          Pane.galaxy => GalaxyPane(onExit: _exit),
          Pane.materials => MaterialsPane(onExit: _exit),
        },
      ),
    );
  }
}

class MainPane extends StatelessWidget {
  const MainPane({super.key, required this.onSelect});

  final ValueSetter<Pane> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          OutlinedButton(
            child: const Text('Galaxy Tools'),
            onPressed: () => onSelect(Pane.galaxy),
          ),
          const SizedBox(height: 24.0),
          OutlinedButton(
            child: const Text('Materials Tools'),
            onPressed: () => onSelect(Pane.materials),
          ),
        ],
      ),
    );
  }
}
