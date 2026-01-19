// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:math';

const double lightYearInM = 9460730472580800.0;
const double auInM = 149597870700.0;

String prettyTime(int time, { bool precise = true }) {
  final double days = time / (1000 * 60 * 60 * 24);
  final int day = days.truncate();
  final double hours = (days - day) * 24.0;
  final int hour = hours.truncate();
  final double minutes = (hours - hour) * 60.0;
  final int minute = minutes.truncate();
  if (precise)
    return 'Day $day ${hour.toString().padLeft(2, "0")}:${minute.toString().padLeft(2, "0")}';
  return 'Day $day';
}

abstract class Unit {
  const Unit();
  String get singular;
  String pretty(double value);
}

String prettyNumberWithExponent(double number) {
  if (number.isNaN)
    return 'NaN';
  if (number.isInfinite) {
    if (number > 0)
      return '∞';
    return '-∞';
  }
  if (number == 0.0) {
    return '0.0';
  }
  final String sign;
  if (number < 0) {
    sign = '-';
    number = -number;
  } else {
    sign = '';
  }
  final int exponent = (log(number) / log(10)).floor();
  final double mantissa = number / pow(10.0, exponent);
  return '$sign${mantissa.toStringAsFixed(1)}×10${_superscript("$exponent")}';
}

String prettyNumber(double number) {
  if (number < 0.0) {
    return '-${prettyNumber(-number)}';
  }
  if (number == 0.0) {
    return '0';
  }
  if (number < 1e-3) {
    return prettyNumberWithExponent(number);
  }
  if (number < 1) {
    return number.toStringAsFixed(4);
  }
  if (number < 1e6) {
    return number.toStringAsFixed(1);
  }
  if (number < 1e9) {
    return (number / 1e6).toStringAsFixed(2) + ' million';
  }
  if (number < 1e12) {
    return (number / 1e9).toStringAsFixed(2) + ' billion';
  }
  return prettyNumberWithExponent(number);
}

String prettyQuantity(int quantity, { String zero = '0', String singular = '', String plural = '' }) {
  if (quantity < 0)
    return prettyQuantity(-quantity, singular: singular, plural: plural);
  if (quantity < 1) {
    return zero;
  }
  if (quantity == 1) {
    return '$quantity$singular';
  }
  if (quantity < 1e6) {
    return '$quantity$plural';
  }
  if (quantity < 1e9) {
    return (quantity / 1e6).toStringAsFixed(2) + ' million$plural';
  }
  if (quantity < 1e12) {
    return (quantity / 1e9).toStringAsFixed(2) + ' billion$plural';
  }
  return '${prettyNumberWithExponent(quantity.toDouble())}$plural';
}

class Quantity extends Unit {
  const Quantity(this.singular, this.plural);
  @override
  final String singular;
  final String plural;
  @override
  String pretty(double value) {
    if (value.toInt() == value) {
      return prettyQuantity(value.toInt(), singular: singular, plural: plural);
    }
    return '${prettyNumber(value)} $plural';
  }
}

String prettyHp(double hp) {
  if (hp == 0.0) {
    return '0';
  }
  if (hp < 1) {
    return prettyNumberWithExponent(hp);
  }
  if (hp < 1e6) {
    return hp.round().toString();
  }
  if (hp < 1e9) {
    return (hp / 1e6).toStringAsFixed(2) + ' million';
  }
  if (hp < 1e12) {
    return (hp / 1e9).toStringAsFixed(2) + ' billion';
  }
  return prettyNumberWithExponent(hp);
}

class Hp extends Unit {
  const Hp();
  @override
  String get singular => 'hp';
  @override
  String pretty(double value) => '${prettyHp(value)} hp';
}

String prettyIterations(double value) {
  if (value.toInt() == value) {
    return prettyQuantity(value.round(), singular: 'iteration', plural: 'iterations');
  }
  return '${prettyNumber(value)} iterations';
}

class Iterations extends Unit {
  const Iterations();
  @override
  String get singular => 'iteration';
  @override
  String pretty(double value) => prettyIterations(value);
}

String prettyHappiness(double happiness) {
  if (happiness <= 0.0) {
    return '☹ ' + prettyNumber(happiness);
  }
  return '☺ ' + prettyNumber(happiness);
}

String prettyMass(double mass) {
  if (mass == 0.0) {
    return '0.0 kg';
  }
  if (mass < 0.003) {
    return (mass * 1000000).toStringAsFixed(1) + ' mg';
  }
  if (mass < 3) {
    return (mass * 1000).toStringAsFixed(1) + ' g';
  }
  if (mass < 1900) {
    return mass.toStringAsFixed(1) + ' kg';
  }
  if (mass < 1900000) {
    return (mass / 1000).toStringAsFixed(1) + ' tonnes';
  }
  if (mass < 1000000000) {
    return (mass / 1000000).toStringAsFixed(1) + ' megatonnes';
  }
  return '${prettyNumberWithExponent(mass)} kg';
}

class Mass extends Unit {
  const Mass();
  @override
  String get singular => 'kg';
  @override
  String pretty(double value) => prettyMass(value);
}

String prettyVolume(double cubicMeters) {
  if (cubicMeters == 0.0) {
    return '0.0 L';
  }
  if (cubicMeters < 1e-6) {
    return (cubicMeters * 1e9).toStringAsFixed(1) + ' μL';
  }
  if (cubicMeters < 1e-3) {
    return (cubicMeters * 1e6).toStringAsFixed(1) + ' mL';
  }
  if (cubicMeters < 1) {
    return (cubicMeters * 1e3).toStringAsFixed(1) + ' L';
  }
  if (cubicMeters < 1e3) {
    return cubicMeters.toStringAsFixed(1) + ' m³'; // or kL
  }
  if (cubicMeters < 1e6) {
    return (cubicMeters * 1e-3).toStringAsFixed(1) + ' ML'; // or dam³
  }
  if (cubicMeters < 1e9) {
    return (cubicMeters * 1e-6).toStringAsFixed(1) + ' GL'; // or hm³
  }
  return '${prettyNumberWithExponent(cubicMeters)} m³';
}

class Volume extends Unit {
  const Volume();
  @override
  String get singular => 'm³';
  @override
  String pretty(double value) => prettyVolume(value);
}

String prettyLength(double m, { int sigfig = 3 }) {
  final double ly = m / lightYearInM;
  double value;
  String units;
  if (ly > 0.9) {
    value = ly;
    units = 'ly';
  } else {
    final double au = m / auInM;
    if (au > 0.1) {
      value = au;
      units = 'AU';
    } else {
      final double km = m / 1000.0;
      if (km > 0.9) {
        value = km;
        units = 'km';
      } else {
        if (m > 0.9) {
          value = m;
          units = 'm';
        } else {
          final double cm = m / 10.0;
          if (cm > 0.9) {
            value = cm;
            units = 'cm';
          } else {
            final double mm = m * 1000.0;
            if (mm > 0.9) {
              value = mm;
              units = 'mm';
            } else {
              final double um = m * 1e6;
              if (um > 0.9) {
                value = um;
                units = 'μm';
              } else {
                final double nm = m * 1e9;
                if (nm > 0.9) {
                  value = nm;
                  units = 'nm';
                } else {
                  final double A = m * 1e10;
                  if (A > 0.1) {
                    value = A;
                    units = 'Å';
                  } else {
                    final double fm = m * 1e15;
                    if (fm > 0.9) {
                      value = fm;
                      units = 'fm';
                    } else {
                      final double am = m * 1e18;
                      if (am > 0.9) {
                        value = am;
                        units = 'am';
                      } else {
                        final double zm = m * 1e21;
                        if (zm > 0.9) {
                          value = zm;
                          units = 'zm';
                        } else {
                          final double ym = m * 1e24;
                          if (ym > 0.9) {
                            value = ym;
                            units = 'ym';
                          } else {
                            final double rm = m * 1e27;
                            if (rm > 0.9) {
                              value = rm;
                              units = 'rm';
                            } else {
                              final double rm = m * 1e30;
                              if (rm > 0.1) {
                                value = rm;
                                units = 'qm';
                              } else {
                                final double lp = m / 1.616255e-35;
                                if (lp > 0.9) {
                                  value = lp;
                                  units = 'ℓₚ';
                                } else {
                                  return '${prettyNumberWithExponent(m)} m';
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  final double scale = pow(10, sigfig - (log(value) / ln10).ceil()).toDouble();
  final double roundValue = (value * scale).round() / scale;
  return '${roundValue.toStringAsFixed(1)} $units';
}

class Length extends Unit {
  const Length();
  @override
  String get singular => 'm';
  @override
  String pretty(double value) => prettyLength(value);
}

String prettyDuration(double time) {
  if (time <= 0.001) {
    return '${(time * 1000000).toStringAsFixed(1)} ns';
  }
  if (time < 1.0) {
    return '${(time * 1000).toStringAsFixed(1)} μs';
  }
  if (time < 1200.0) {
    return '${time.toStringAsFixed(1)} ms';
  }
  time /= 1000;
  if (time <= 90.0) {
    return '${time.toStringAsFixed(1)} s';
  }
  time /= 60;
  if (time <= 90.0) {
    return '${time.toStringAsFixed(1)} min';
  }
  time /= 60;
  if (time <= 36.0) {
    return '${time.toStringAsFixed(1)} h';
  }
  time /= 24;
  final double days = time;
  if (time == 1.0) {
    return '${time.toStringAsFixed(1)} day';
  }
  if (time <= 9.0) {
    return '${time.toStringAsFixed(1)} days';
  }
  time /= 7;
  if (time == 1.0) {
    return '${time.toStringAsFixed(1)} week';
  }
  if (time <= 52.0) {
    return '${time.toStringAsFixed(1)} weeks';
  }
  time = days / 365;
  if (time == 1.0) {
    return '${time.toStringAsFixed(1)} year';
  }
  return '${time.toStringAsFixed(1)} years';
}

String prettyRate(double rate, Unit units) {
  if (rate == 0.0)
    return 'stopped';
  final double perHour = rate * 1000.0 * 60.0 * 60.0;
  return '${units.pretty(perHour)} per hour (1 ${units.singular} every ${prettyDuration(1.0 / rate)})';
}

String prettyFraction(double value) {
  assert(value >= 0.0);
  assert(value <= 1.0);
  return '${(value * 100.0).toStringAsFixed(1)}%';
}

String _superscript(String value) {
  final List<String> result = <String>[];
  for (int rune in value.runes) {
    result.add(String.fromCharCode(switch (rune) { // based on NamesList-16.0.0.txt (as of May 2025)
      0x0028 => 0x207D,
      0x0029 => 0x207E,
      0x002B => 0x207A,
      0x002D => 0x207B, // not in Unicode (0x207B wants to be the superscript of U+2212 MINUS SIGN; this is U+002D HYPHEN-MINUS)
      0x0030 => 0x2070,
      0x0031 => 0x00B9,
      0x0032 => 0x00B2,
      0x0033 => 0x00B3,
      0x0034 => 0x2074,
      0x0035 => 0x2075,
      0x0036 => 0x2076,
      0x0037 => 0x2077,
      0x0038 => 0x2078,
      0x0039 => 0x2079,
      0x003D => 0x207C,
      0x0041 => 0x1D2C,
      0x0042 => 0x1D2E,
      0x0043 => 0xA7F2,
      0x0044 => 0x1D30,
      0x0045 => 0x1D31,
      0x0046 => 0xA7F3,
      0x0047 => 0x1D33,
      0x0048 => 0x1D34,
      0x0049 => 0x1D35,
      0x004A => 0x1D36,
      0x004B => 0x1D37,
      0x004C => 0x1D38,
      0x004D => 0x1D39,
      0x004E => 0x1D3A,
      0x004F => 0x1D3C,
      0x0050 => 0x1D3E,
      0x0051 => 0xA7F4,
      0x0052 => 0x1D3F,
      0x0054 => 0x1D40,
      0x0055 => 0x1D41,
      0x0056 => 0x2C7D,
      0x0057 => 0x1D42,
      0x0061 => 0x00AA,
      // 0x0061 => 0x1D43,
      0x0062 => 0x1D47,
      0x0063 => 0x1D9C,
      0x0064 => 0x1D48,
      0x0065 => 0x1D49,
      0x0066 => 0x1DA0,
      0x0067 => 0x1D4D,
      0x0068 => 0x02B0,
      0x0069 => 0x2071,
      0x006A => 0x02B2,
      0x006B => 0x1D4F,
      0x006C => 0x02E1,
      0x006D => 0x1D50,
      0x006E => 0x207F,
      0x006F => 0x00BA,
      // 0x006F => 0x1D52,
      0x0070 => 0x1D56,
      0x0071 => 0x107A5,
      0x0072 => 0x02B3,
      0x0073 => 0x02E2,
      0x0074 => 0x1D57,
      0x0075 => 0x1D58,
      0x0076 => 0x1D5B,
      0x0077 => 0x02B7,
      0x0078 => 0x02E3,
      0x0079 => 0x02B8,
      0x007A => 0x1DBB,
      0x00C6 => 0x1D2D,
      0x00E6 => 0x10783,
      0x00F0 => 0x1D9E,
      0x00F8 => 0x107A2,
      0x0126 => 0xA7F8,
      0x0127 => 0x10795,
      0x014B => 0x1D51,
      0x0153 => 0xA7F9,
      0x018E => 0x1D32,
      0x01AB => 0x1DB5,
      0x01C0 => 0x107B6,
      0x01C1 => 0x107B7,
      0x01C2 => 0x107B8,
      0x0222 => 0x1D3D,
      0x0250 => 0x1D44,
      0x0251 => 0x1D45,
      0x0252 => 0x1D9B,
      0x0253 => 0x10785,
      0x0254 => 0x1D53,
      0x0255 => 0x1D9D,
      0x0256 => 0x1078B,
      0x0257 => 0x1078C,
      0x0258 => 0x1078E,
      0x0259 => 0x1D4A,
      0x025B => 0x1D4B,
      0x025C => 0x1D4C,
      // 0x025C => 0x1D9F,
      0x025E => 0x1078F,
      0x025F => 0x1DA1,
      0x0260 => 0x10793,
      0x0261 => 0x1DA2,
      0x0262 => 0x10792,
      0x0263 => 0x02E0,
      0x0264 => 0x10791,
      0x0265 => 0x1DA3,
      0x0266 => 0x02B1,
      0x0267 => 0x10797,
      0x0268 => 0x1DA4,
      0x0269 => 0x1DA5,
      0x026A => 0x1DA6,
      0x026B => 0xAB5E,
      0x026C => 0x1079B,
      0x026D => 0x1DA9,
      0x026E => 0x1079E,
      0x026F => 0x1D5A,
      0x0270 => 0x1DAD,
      0x0271 => 0x1DAC,
      0x0272 => 0x1DAE,
      0x0273 => 0x1DAF,
      0x0274 => 0x1DB0,
      0x0275 => 0x1DB1,
      0x0276 => 0x107A3,
      0x0277 => 0x107A4,
      0x0278 => 0x1DB2,
      0x0279 => 0x02B4,
      0x027A => 0x107A6,
      0x027B => 0x02B5,
      0x027D => 0x107A8,
      0x027E => 0x107A9,
      0x0280 => 0x107AA,
      0x0281 => 0x02B6,
      0x0282 => 0x1DB3,
      0x0283 => 0x1DB4,
      0x0284 => 0x10798,
      0x0288 => 0x107AF,
      0x0289 => 0x1DB6,
      0x028A => 0x1DB7,
      0x028B => 0x1DB9,
      0x028C => 0x1DBA,
      0x028D => 0xAB69,
      0x028E => 0x107A0,
      0x028F => 0x107B2,
      0x0290 => 0x1DBC,
      0x0291 => 0x1DBD,
      0x0292 => 0x1DBE,
      0x0295 => 0x02E4,
      0x0298 => 0x107B5,
      0x0299 => 0x10784,
      0x029B => 0x10794,
      0x029C => 0x10796,
      0x029D => 0x1DA8,
      0x029F => 0x1DAB,
      0x02A1 => 0x107B3,
      0x02A2 => 0x107B4,
      0x02A3 => 0x10787,
      0x02A4 => 0x1078A,
      0x02A5 => 0x10789,
      0x02A6 => 0x107AC,
      0x02A7 => 0x107AE,
      0x02A8 => 0x107AB,
      0x02A9 => 0x10790,
      0x02AA => 0x10799,
      0x02AB => 0x1079A,
      0x02D0 => 0x10781,
      0x02D1 => 0x10782,
      0x03B2 => 0x1D5D,
      0x03B3 => 0x1D5E,
      0x03B4 => 0x1D5F,
      0x03B8 => 0x1DBF,
      0x03C6 => 0x1D60,
      0x03C7 => 0x1D61,
      0x0430 => 0x1E030,
      0x0431 => 0x1E031,
      0x0432 => 0x1E032,
      0x0433 => 0x1E033,
      0x0434 => 0x1E034,
      0x0435 => 0x1E035,
      0x0436 => 0x1E036,
      0x0437 => 0x1E037,
      0x0438 => 0x1E038,
      0x043A => 0x1E039,
      0x043B => 0x1E03A,
      0x043C => 0x1E03B,
      0x043D => 0x1D78,
      0x043E => 0x1E03C,
      0x043F => 0x1E03D,
      0x0440 => 0x1E03E,
      0x0441 => 0x1E03F,
      0x0442 => 0x1E040,
      0x0443 => 0x1E041,
      0x0444 => 0x1E042,
      0x0445 => 0x1E043,
      0x0446 => 0x1E044,
      0x0447 => 0x1E045,
      0x0448 => 0x1E046,
      0x044A => 0xA69C,
      0x044B => 0x1E047,
      0x044C => 0xA69D,
      0x044D => 0x1E048,
      0x044E => 0x1E049,
      0x0456 => 0x1E04C,
      0x0458 => 0x1E04D,
      0x04AB => 0x1E06B,
      0x04AF => 0x1E04F,
      0x04B1 => 0x1E06D,
      0x04CF => 0x1E050,
      0x04D9 => 0x1E04B,
      0x04E9 => 0x1E04E,
      0x10DC => 0x10FC,
      0x1D02 => 0x1D46,
      0x1D16 => 0x1D54,
      0x1D17 => 0x1D55,
      0x1D1C => 0x1DB8,
      0x1D1D => 0x1D59,
      0x1D25 => 0x1D5C,
      0x1D7B => 0x1DA7,
      0x1D85 => 0x1DAA,
      0x1D91 => 0x1078D,
      0x1DF04 => 0x1079C,
      0x1DF05 => 0x1079F,
      0x1DF06 => 0x107A1,
      0x1DF08 => 0x107A7,
      0x1DF0A => 0x107B9,
      0x1DF1E => 0x107BA,
      0x2212 => 0x207B,
      0x2C71 => 0x107B0,
      0x2D61 => 0x2D6F,
      0x4E00 => 0x3192,
      0x4E01 => 0x319C,
      0x4E09 => 0x3194,
      0x4E0A => 0x3196,
      0x4E0B => 0x3198,
      0x4E19 => 0x319B,
      0x4E2D => 0x3197,
      0x4E59 => 0x319A,
      0x4E8C => 0x3193,
      0x4EBA => 0x319F,
      0x56DB => 0x3195,
      0x5730 => 0x319E,
      0x5929 => 0x319D,
      0x7532 => 0x3199,
      0xA651 => 0x1E06C,
      0xA689 => 0x1E04A,
      0xA727 => 0xAB5C,
      0xA76F => 0xA770,
      0xA78E => 0x1079D,
      0xAB37 => 0xAB5D,
      0xAB52 => 0xAB5F,
      0xAB66 => 0x10788,
      0xAB67 => 0x107AD,
     _ => rune,
    }));
  }
  return result.join();
}
