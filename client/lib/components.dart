class Material { }

class StructuralComponent {
  StructuralComponent({
    required this.current,
    required this.max,
    required this.name,
    required this.material,
    required this.description,
  });

  final int current;
  final int? max;
  final String? name;
  final Material material;
  final String description;
}
