import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'classes/Cliente.dart';

class BBDD {
  late Database _db;

  initDB() async {
    _db = await openDatabase(
      'databaseLocal.db',
      version: 1,
      onCreate: (Database db, int version) {
        db.execute(
            "CREATE TABLE cliente (certificate_id VARCHAR(20) PRIMARY KEY, id INTEGER NOT NULL UNIQUE, nombre VARCHAR(20) NOT NULL, apellidos VARCHAR(50) NOT NULL, fecha VARCHAR(10) NOT NULL, puntos TEXT NOT NULL);");
      },
    );
  }

  insertAllCliente(List<Cliente> c) {
    for (Cliente ind in c) {
      insertCliente(ind);
    }
  }

  Future<List<Cliente>> getAllClientes() async {
    List<Map<String, dynamic>> results = await _db.query("cliente");
    return results.map((map) => Cliente.fromMap(map)).toList();
  }

  insertCliente(Cliente c) async {
    _db.insert("cliente", c.toMap());
  }

  Future<void> deleteCliente(String certificate_id) async {
    await _db.delete(
      'cliente',
      where: "certificate_id = ?",
      whereArgs: [certificate_id],
    );
  }

  updatePoints(Cliente c) async {
    await _db.update(
      'cliente',
      c.toMap(),
      where: "certificate_id = ?",
      whereArgs: [c.certificate_id],
    );
  }

  deleteAllClientes() async {
    await _db.delete('cliente');
  }

  Future<String> get _localPath async {
    Directory? directory = await getExternalStorageDirectory();
    return directory!.path;
  }
}
