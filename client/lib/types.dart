class DisabledReason {
  DisabledReason(this._flags);

  final int _flags;

  bool get fullyActive => _flags == 0;

  bool get noCoordinator => _flags & 0x01 > 0;
  bool get structurallyUnsound => _flags & 0x02 > 0;
  bool get manuallyDisabled => _flags & 0x04 > 0;
  bool get understaffed => _flags & 0x08 > 0;
  bool get unowned => _flags & 0x10 > 0;
  bool get sourceLimited => _flags & 0x20 > 0;
  bool get targetLimited => _flags & 0x40 > 0;

  String _describeLong(double? rate) {
    if (unowned) {
      return 'No dynasty controls this, so it is disabled';
    }
    if (noCoordinator) {
      return 'In this location, functionality is impossible';
    }
    if (structurallyUnsound) {
      return 'Incomplete structure impeding functionality';
    }
    if (manuallyDisabled) {
      return 'Manually disabled';
    }
    if (understaffed && (rate == 0.0 || rate == null)) {
      return 'Insufficient staffing prevents functionality';
    }
    if (understaffed) {
      return 'Understaffed, operating at reduced functionality';
    }
    if (sourceLimited) {
      return 'Inadequate input supply';
    }
    if (targetLimited) {
      return 'Insufficient storage for output';
    }
    return 'Unknown problem prevents functionality';
  }

  String _describeShort() {
    final List<String> bits = <String>[];
    if (unowned) {
      bits.add('unowned');
    }
    if (noCoordinator) {
      bits.add('in');
    }
    if (structurallyUnsound) {
      bits.add('incomplete');
    }
    if (manuallyDisabled) {
      bits.add('disabled');
    }
    if (understaffed) {
      bits.add('understaffed');
    }
    if (sourceLimited) {
      bits.add('source limited');
    }
    if (targetLimited) {
      bits.add('target limited');
    }
    if (bits.length > 1) {
      return ' (also ${bits.skip(1).join(', ')})';
    }
    return '';
  }

  String describe(double? rate) {
    if (fullyActive)
      throw StateError('Tried to obtain disabled reason while enabled.');
    return '${_describeLong(rate)}${_describeShort()}.';
  }
}
