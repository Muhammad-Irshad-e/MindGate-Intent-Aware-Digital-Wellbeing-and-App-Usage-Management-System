import 'package:flutter/material.dart';

class AppIconWidget extends StatelessWidget {
  final String iconKey;
  final double size;

  const AppIconWidget({
    super.key,
    required this.iconKey,
    this.size = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    IconData iconData;
    Color bgColor;
    Color iconColor;

    switch (iconKey.toLowerCase()) {
      case 'youtube':
        iconData = Icons.play_arrow_rounded;
        bgColor = const Color(0xFFFF0000);
        iconColor = Colors.white;
        break;
      case 'whatsapp':
        iconData = Icons.chat_bubble_rounded;
        bgColor = const Color(0xFF25D366);
        iconColor = Colors.white;
        break;
      case 'chrome':
        iconData = Icons.public_rounded;
        bgColor = const Color(0xFF4285F4);
        iconColor = Colors.white;
        break;
      case 'vscode':
        iconData = Icons.code_rounded;
        bgColor = const Color(0xFF007ACC);
        iconColor = Colors.white;
        break;
      case 'notion':
        iconData = Icons.edit_note_rounded;
        bgColor = const Color(0xFF000000);
        iconColor = Colors.white;
        break;
      case 'instagram':
        iconData = Icons.camera_alt_rounded;
        bgColor = const Color(0xFFE1306C);
        iconColor = Colors.white;
        break;
      case 'spotify':
        iconData = Icons.music_note_rounded;
        bgColor = const Color(0xFF1DB954);
        iconColor = Colors.white;
        break;
      case 'gmail':
        iconData = Icons.mail_rounded;
        bgColor = const Color(0xEAEA4335);
        iconColor = Colors.white;
        break;
      default:
        iconData = Icons.android_rounded;
        bgColor = const Color(0xFF64748B);
        iconColor = Colors.white;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Center(
        child: Icon(
          iconData,
          color: iconColor,
          size: size * 0.58,
        ),
      ),
    );
  }
}
