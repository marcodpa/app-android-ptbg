class LimpiezaPlato {
  const LimpiezaPlato(
      {required this.uuid,
      required this.localizacion,
      required this.fecha,
      required this.hora,
      required this.horasFuncionamiento,
      required this.odt,
      this.observaciones = '',
      this.responsable = '',
      this.cargo = '',
      this.marca = '',
      this.modelo = '',
      this.serial = '',
      this.sincronizado = false,
      this.errorSync});

  final String uuid,
      fecha,
      hora,
      observaciones,
      responsable,
      cargo,
      marca,
      modelo,
      serial;
  final int localizacion, horasFuncionamiento, odt;
  final bool sincronizado;
  final String? errorSync;

  static int? leerHorometro(String valor) {
    if (!RegExp(r'^\d+$').hasMatch(valor.trim())) return null;
    final numero = int.tryParse(valor.trim());
    return numero != null && numero <= 2147483647 ? numero : null;
  }

  Map<String, Object?> toDbMap() => {
        'uuid': uuid,
        'localizacion': localizacion,
        'fecha': fecha,
        'hora': hora,
        'horas_funcionamiento': horasFuncionamiento,
        'observaciones': observaciones,
        'responsable': responsable,
        'cargo': cargo,
        'marca': marca,
        'modelo': modelo,
        'serial': serial,
        'odt': odt,
        'sincronizado': sincronizado ? 1 : 0,
        'error_sync': errorSync,
      };

  factory LimpiezaPlato.fromMap(Map<String, Object?> row) => LimpiezaPlato(
        uuid: '${row['uuid']}',
        localizacion: (row['localizacion'] as num).toInt(),
        fecha: '${row['fecha']}',
        hora: '${row['hora']}',
        horasFuncionamiento: (row['horas_funcionamiento'] as num).toInt(),
        odt: (row['odt'] as num).toInt(),
        observaciones: '${row['observaciones'] ?? ''}',
        responsable: '${row['responsable'] ?? ''}',
        cargo: '${row['cargo'] ?? ''}',
        marca: '${row['marca'] ?? ''}',
        modelo: '${row['modelo'] ?? ''}',
        serial: '${row['serial'] ?? ''}',
        sincronizado: row['sincronizado'] == 1,
        errorSync: row['error_sync']?.toString(),
      );
}
