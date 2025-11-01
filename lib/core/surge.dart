class DavaoSurgeConfig {
  final double min = 1.0;
  final double max = 1.8;

  double compose({required DateTime now, required bool isRaining}) {
    final timeBoost = _timeBoost(now);
    final rainBoost = isRaining ? 1.15 : 1.0;
    return _clamp(timeBoost * rainBoost);
  }

  double _timeBoost(DateTime t) {
    final wk = t.weekday;
    final hm = t.hour * 60 + t.minute;
    bool inRange(int s, int e) => hm >= s && hm < e;

    double mult = 1.0;
    if (inRange(6 * 60, 8 * 60 + 30)) mult = 1.15; // morning rush
    if (inRange(16 * 60 + 30, 19 * 60 + 30)) mult = 1.20; // evening rush
    if ((wk == DateTime.friday || wk == DateTime.saturday) &&
        (hm >= 21 * 60 || hm < 1 * 60))
      mult = 1.10; // nightlife
    return mult;
  }

  double _clamp(double v) => v < min ? min : (v > max ? max : v);
}
