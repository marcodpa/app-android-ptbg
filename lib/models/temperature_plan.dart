class TemperatureStep {
  final int pointNumber;
  final int visualPointNumber;
  final int dbPointNumber;
  final String label;
  double? value;

  TemperatureStep({
    required this.pointNumber,
    required this.visualPointNumber,
    required this.dbPointNumber,
    required this.label,
    this.value,
  });

  String get dbColumn => 'T$dbPointNumber';
}

class TemperaturePlanResolver {
  static List<TemperatureStep> fromPuntos(int puntos) {
    switch (puntos) {
      case 2:
        return _motorPump(const [4, 3, 1, 2]);
      case 3:
        return _motorPump(const [1, 2, 4, 3]);
      case 7:
      case 8:
        return _motorPump(const [1, 1, 2, 2]);
      case 9:
        return _motorPump(const [1, 2, 4, 3]);
      case 4:
        return [
          _step(1, 1, 1, 'Motor - lado libre'),
          _step(2, 2, 2, 'Motor - lado acople'),
          _step(3, 3, 9, 'Ventilador FIN-FAN - lado libre'),
          _step(4, 4, 10, 'Correa (FIN-FAN)'),
        ];
      case 5:
        return [
          _step(1, 1, 1, 'Motor - lado libre'),
          _step(2, 2, 2, 'Motor - lado acople'),
          _step(3, 3, 7, 'Ventilador - punto 1'),
          _step(4, 4, 8, 'Ventilador - punto 2'),
        ];
      case 6:
        return [
          _step(1, 1, 1, 'Motor - lado libre'),
          _step(2, 2, 2, 'Motor - lado acople'),
          _step(3, 3, 3, 'Caja - lado eje baja'),
          _step(4, 4, 4, 'Caja - lado eje alta'),
          _step(5, 6, 5, 'Bomba - lado acople'),
          _step(6, 5, 6, 'Bomba - lado libre'),
        ];
      case 1:
      default:
        return _motorPump(const [1, 2, 3, 4]);
    }
  }

  static List<TemperatureStep> _motorPump(List<int> visuals) => [
        _step(1, visuals[0], 1, 'Motor - lado libre'),
        _step(2, visuals[1], 2, 'Motor - lado acople'),
        _step(3, visuals[2], 5, 'Bomba - lado acople'),
        _step(4, visuals[3], 6, 'Bomba - lado libre'),
      ];

  static TemperatureStep _step(
    int point,
    int visual,
    int dbPoint,
    String label,
  ) {
    return TemperatureStep(
      pointNumber: point,
      visualPointNumber: visual,
      dbPointNumber: dbPoint,
      label: label,
    );
  }
}
