import 'package:flutter/material.dart';

class RenditionsShell extends StatelessWidget {
  const RenditionsShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: false,
      resizeToAvoidBottomInset: true,
      body: SafeArea(child: child),
    );
  }
}
