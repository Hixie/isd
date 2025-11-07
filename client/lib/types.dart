class DisabledReason {
  DisabledReason(this._flags);

  final int _flags;

  bool get enabled => _flags == 0;

  bool get manuallyDisabled => _flags & 0x01 > 0;
  bool get structurallyUnsound => _flags & 0x02 > 0;
  bool get noCoordinator => _flags & 0x04 > 0;

  String get description {
    if (noCoordinator) {
      return 'In this location, functionality is impossible.';
    }
    if (structurallyUnsound) {
      return 'Incomplete structure impeding functionality.';
    }
    if (manuallyDisabled) {
      return 'Manually disabled.';
    }
    if (enabled)
      throw StateError('Tried to obtain disabled reason while enabled.');
    return 'Unknown problem prevents functionality.';
  }
}
