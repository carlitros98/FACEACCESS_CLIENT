class Cliente {
  late int id;
  late String certificate_id;
  late String nombre;
  late String apellidos;
  late String fecha;
  late String puntos;

  Cliente(
      {required this.id,
      required this.certificate_id,
      required this.nombre,
      required this.apellidos,
      required this.fecha,
      required this.puntos});

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "certificate_id": certificate_id,
      "nombre": nombre,
      "apellidos": apellidos,
      "fecha": fecha,
      "puntos": puntos
    };
  }

  Cliente.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    certificate_id = map['certificate_id'];
    nombre = map['nombre'];
    apellidos = map['apellidos'];
    fecha = map['fecha'];
    puntos = map['puntos'];
  }

  factory Cliente.fromJson(dynamic json) {
    return Cliente(
        id: json['id'],
        certificate_id: json['certificate_id'].toString(),
        nombre: json['nombre'].toString(),
        apellidos: json['apellidos'].toString(),
        fecha: json['fecha'].toString(),
        puntos: json['puntos'].toString());
  }
}
