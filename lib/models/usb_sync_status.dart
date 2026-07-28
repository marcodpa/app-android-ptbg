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

  factory UsbSyncStatus.fromValues({
    required String? status,
    required String? serial,
    required String? detail,
    required String? lastSeen,
    String? requestId,
    required DateTime now,
    Duration freshFor = const Duration(seconds: 25),
  }) {
    final seenAt = DateTime.tryParse(lastSeen ?? '');
    final isFresh = seenAt != null && now.difference(seenAt).abs() <= freshFor;
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
