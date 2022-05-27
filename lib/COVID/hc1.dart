import 'dgc_v1.dart';

class Hc1 {
  String? issuer;
  int? issuedAt;
  int? expirationTime;
  DgcV1? certificate;

  Hc1({this.issuer, this.issuedAt, this.expirationTime, this.certificate});

  factory Hc1.defaultValues() {
    return Hc1();
  }

  factory Hc1.fromMap(Map data) {
    print("Making Hc1");
    return Hc1(
      issuer: data[1],
      issuedAt: data[6],
      expirationTime: data[4],
      certificate: DgcV1.fromMap(data[-260][1]),
    );
  }
}
