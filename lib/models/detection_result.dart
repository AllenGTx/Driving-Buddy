enum DriverStatus { awake, sleep, yawn, drowsy, noFace }

class DetectionResult {
  final DriverStatus status;
  final String subStatus;
  final double ear;
  final double mar;
  final int blinkCount; // kedipan dalam 60 detik terakhir
  final int yawnCount; // menguap dalam 5 menit terakhir
  final double rollAngle; // derajat kemiringan kepala (tilt)
  final double pitchRatio; // rasio menunduk kepala (pitch)
  final int headBobCount; // jumlah head bobbing dalam 5 menit terakhir
  final bool isHeadTiltAlert; // sedang trigger head tilt
  final bool isHeadBobAlert; // sedang trigger head bob

  const DetectionResult({
    required this.status,
    required this.subStatus,
    required this.ear,
    required this.mar,
    required this.blinkCount,
    required this.yawnCount,
    this.rollAngle = 0.0,
    this.pitchRatio = 0.5,
    this.headBobCount = 0,
    this.isHeadTiltAlert = false,
    this.isHeadBobAlert = false,
  });

  static const initial = DetectionResult(
    status: DriverStatus.awake,
    subStatus: 'Menunggu wajah...',
    ear: 0,
    mar: 0,
    blinkCount: 0,
    yawnCount: 0,
    rollAngle: 0.0,
    pitchRatio: 0.5,
    headBobCount: 0,
    isHeadTiltAlert: false,
    isHeadBobAlert: false,
  );
}
