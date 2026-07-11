class OutletType {
  final int id;
  final String name;
  final String description;

  OutletType({
    required this.id,
    required this.name,
    required this.description,
  });

  factory OutletType.fromJson(Map<String, dynamic> json) {
    return OutletType(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String,
    );
  }
}
