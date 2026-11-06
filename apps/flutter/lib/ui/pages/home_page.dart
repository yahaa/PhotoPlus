import 'package:flutter/cupertino.dart';

/// Blank home shell. TODO: timeline / albums / search tabs.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('PhotoPlus'),
      ),
      child: SafeArea(
        child: Center(
          child: Text('PhotoPlus'),
        ),
      ),
    );
  }
}
