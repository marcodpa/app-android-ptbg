/// Catálogos de filtros: los códigos nunca se deducen del ID ni del nombre.
typedef FilterRow = Map<String, dynamic>;

int filterInt(Object? value) => int.tryParse('$value') ?? 0;
String filterText(Object? value) => value?.toString().trim() ?? '';

class FilterCatalog {
  const FilterCatalog(
      {this.systems = const [],
      this.subsystems = const [],
      this.elements = const []});
  final List<FilterRow> systems, subsystems, elements;

  List<FilterRow> get enabledSystems =>
      systems.where((r) => filterInt(r['PTBG_FLT']) == 1).toList();

  List<FilterRow> forSystem(int code, {bool enabledOnly = true}) => subsystems
      .where((r) =>
          filterInt(r['CODE_SYS']) == code &&
          (!enabledOnly || filterInt(r['PTBG_FLT']) == 1))
      .toList();

  List<FilterRow> forSubsystem(int system, int subsystem) => elements
      .where((r) =>
          filterInt(r['CODE_SYS']) == system &&
          filterInt(r['CODE_SUB_SYS']) == subsystem)
      .toList();

  static String? validateElement(FilterRow row) {
    for (final field in [
      'CODE_SYS',
      'CODE_SUB_SYS',
      'LOCALIZACION',
      'CANTIDAD'
    ]) {
      final n = int.tryParse('${row[field]}');
      if (n == null || n <= 0 || n > 32767) {
        return '$field debe estar entre 1 y 32767.';
      }
    }
    for (final field in [
      'ELEMENTO',
      'TAGNAME',
      'MODELO',
      'MARCA',
      'ESPECIFICACIONES'
    ]) {
      final value = filterText(row[field]);
      final max = field == 'ESPECIFICACIONES' ? 50 : 150;
      if (value.isEmpty || value.length > max) {
        return '$field: ingrese entre 1 y $max caracteres.';
      }
    }
    return null;
  }
}
