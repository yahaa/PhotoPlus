import 'package:flutter/cupertino.dart';
import 'package:photoplus/core/theme/app_theme.dart';
import 'package:photoplus/ui/pages/home_page.dart';

void main() {
  runApp(const PhotoPlusApp());
}

class PhotoPlusApp extends StatelessWidget {
  const PhotoPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'PhotoPlus',
      theme: AppTheme.cupertino,
      home: const HomePage(),
    );
  }
}
