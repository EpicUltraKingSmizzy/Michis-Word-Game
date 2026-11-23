import 'package:material_ui/material_ui.dart';

class AvatarStyle {
  const AvatarStyle(this.icon, this.color, this.label);
  final IconData icon;
  final Color color;
  final String label;
}

/// Built-in avatars. The index is what gets saved and sent over the network.
const List<AvatarStyle> avatarStyles = [
  AvatarStyle(Icons.pets, Color(0xFFFF8A3D), 'Paw'),
  AvatarStyle(Icons.rocket_launch, Color(0xFF3DA5FF), 'Rocket'),
  AvatarStyle(Icons.star_rounded, Color(0xFFFFC21A), 'Star'),
  AvatarStyle(Icons.local_pizza, Color(0xFFE5484D), 'Pizza'),
  AvatarStyle(Icons.sports_esports, Color(0xFF8B5CF6), 'Gamer'),
  AvatarStyle(Icons.bolt, Color(0xFFF59E0B), 'Bolt'),
  AvatarStyle(Icons.eco, Color(0xFF22C55E), 'Leaf'),
  AvatarStyle(Icons.icecream, Color(0xFFF472B6), 'Ice cream'),
  AvatarStyle(Icons.auto_awesome, Color(0xFF06B6D4), 'Sparkle'),
  AvatarStyle(Icons.cake, Color(0xFFEC4899), 'Cake'),
  AvatarStyle(Icons.directions_bike, Color(0xFF14B8A6), 'Bike'),
  AvatarStyle(Icons.music_note, Color(0xFF6366F1), 'Music'),
  AvatarStyle(Icons.sailing, Color(0xFF0EA5E9), 'Boat'),
  AvatarStyle(Icons.emoji_nature, Color(0xFF84CC16), 'Bee'),
  AvatarStyle(Icons.nightlight_round, Color(0xFF475569), 'Moon'),
  AvatarStyle(Icons.local_fire_department, Color(0xFFEF4444), 'Fire'),
];

AvatarStyle avatarStyle(int index) => avatarStyles[index.abs() % avatarStyles.length];

class AvatarCircle extends StatelessWidget {
  const AvatarCircle({super.key, required this.avatar, this.size = 48, this.ring = true});
  final int avatar;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final s = avatarStyle(avatar);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: s.color,
        shape: BoxShape.circle,
        border: ring ? Border.all(color: Colors.white, width: size * 0.06) : null,
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Icon(s.icon, color: Colors.white, size: size * 0.55),
    );
  }
}
