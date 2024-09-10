class Material { }

class StructuralComponent {
  StructuralComponent({
    required this.current,
    required this.max,
    required this.name,
    required this.materialID,
    required this.description,
  });

  final int current;
  final int? max;
  final String? name;
  final int materialID;
  final String description;
}
