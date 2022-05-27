import 'package:capacity_access_device/BBDD/classes/Cliente.dart';

class Utils {
  static List<Cliente> clientes = [];

  static String id_actual = "0";

  static insertCliente(Cliente c) {
    clientes.add(c);
  }

  static insertAllCliente(List<Cliente> c) {
    clientes = [];
    clientes = c;
  }

  static deleteAllCliente() {
    clientes = [];
  }
}
