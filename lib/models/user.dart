import 'package:appwrite/models.dart' as models;

class User {
  final String id;
  final String email;
  final String name;
  final String? phone;
  final String? password;

  User({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    this.password,
  });

  factory User.fromAppwriteUser(models.User user) {
    return User(
      id: user.$id,
      email: user.email,
      name: user.name,
      phone: user.phone.isNotEmpty ? user.phone : null,
      password: null,
    );
  }

  Map<String, dynamic> toMap() {
    return {'email': email, 'name': name, if (phone != null) 'phone': phone!};
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['\$id'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'],
      password: null,
    );
  }
}
