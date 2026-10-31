class HeartRateSample {
  final int durationInSec;
  final DateTime timestamp;
  final int heartRatePeak;
  final int peakAtSec;
  final int peakAtMin;
  final int peakAthour;

  HeartRateSample({
    required this.durationInSec,
    required this.timestamp,
    required this.heartRatePeak,
    required this.peakAthour,
    required this.peakAtMin,
    required this.peakAtSec,
  });

  Map<String, dynamic> toJson() => {
        'durationinsec': durationInSec,
        'timestamp': timestamp.toIso8601String(),
        'peak': heartRatePeak,
        'peakAthour': peakAthour,
        'peakAtMin': peakAtMin,
        'peakAtSec': peakAtSec,
      };

  factory HeartRateSample.fromJson(Map<String, dynamic> json) {
    return HeartRateSample(
      durationInSec: json['durationinsec'],
      timestamp: DateTime.parse(json['timestamp']),
      heartRatePeak: json['peak'],
      peakAthour: json['peakAthour'],
      peakAtMin: json['peakAtMin'],
      peakAtSec: json['peakAtSec'],
    );
  }
}
