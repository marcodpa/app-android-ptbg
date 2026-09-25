class UsbSyncStatus {
  final bool online;
  final String rawStatus;
  final String label;
  final String detail;
  final DateTime? lastSeen;
  final String? requestId;

  const UsbSyncStatus({
    required this.online,
    required this.rawStatus,
    required this.label,
    required this.detail,
    this.lastSeen,
    this.requestId,
  });

  /// Igualdad por valor, para que las pantallas que sondean el estado cada
  /// pocos segundos puedan preguntar "¿cambio algo?" antes de redibujarse.
  /// Sin esto, cada tick del sondeo reconstruia pantallas de mas de mil
  /// lineas aunque el estado fuera identico al anterior.
  @override
  bool operator ==(Object other) =>
      other is UsbSyncStatus &&
      other.online == online &&
      other.rawStatus == rawStatus &&
      other.label == label &&
      other.detail == detail &&
      other.requestId == requestId;

  @override
  int get hashCode => Object.hash(online, rawStatus, label, detail, requestId);

  factory UsbSyncStatus.fromValues({
    required String? status,
    required String? serial,
    required String? detail,
    required String? lastSeen,
    String? requestId,
    required DateTime now,
    DateTime? receivedAt,
    Duration freshFor = const Duration(seconds: 25),
  }) {
    final seenAt = DateTime.tryParse(lastSeen ?? '');
    // El uploader copia el archivo SIN preservar su fecha: Android asigna
    // su mtime con el reloj de la tablet. Comparar esa recepcion local con
    // now evita exigir que los relojes de laptop y tablet esten alineados.
    // last_seen se conserva como dato de origen; el fallback es para estados
    // antiguos que solo existen en preferencias, sin archivo de recepcion.
    final freshnessTime = receivedAt ?? seenAt;
    final isFresh = seenAt != null &&
        freshnessTime != null &&
        now.difference(freshnessTime).abs() <= freshFor;
    final raw = (status ?? '').trim().toUpperCase();
    final isConnectedStatus =
        raw == 'ONLINE' || raw == 'SYNCING' || raw == 'DONE' || raw == 'ERROR';
    final isOnline = isConnectedStatus && isFresh;
    final shownDetail = isOnline
        ? (detail?.trim().isNotEmpty == true
            ? detail!.trim()
            : 'Laptop conectada: ${serial?.trim().isNotEmpty == true ? serial!.trim() : 'USB'}')
        : (detail?.trim().isNotEmpty == true
            ? detail!.trim()
            : 'Conecta la tablet a la laptop y presiona Detectar');

    return UsbSyncStatus(
      online: isOnline,
      rawStatus: raw,
      label: isOnline ? (raw.isEmpty ? 'ONLINE' : raw) : 'OFFLINE',
      detail: shownDetail,
      lastSeen: seenAt,
      requestId:
          requestId?.trim().isNotEmpty == true ? requestId!.trim() : null,
    );
  }
}
