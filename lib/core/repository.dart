import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_connection.dart';
import 'catalog_payload.dart';

import 'models.dart';

class PosRepository {
  final db = posFirestore;
  final functions = posFunctions;
  String newId() => db.collection('identifiers').doc().id;
  Stream<List<Json>> watch(String collection, {String? field, Object? equal}) {
    Query<Json> query = db.collection(collection);
    if (field != null) query = query.where(field, isEqualTo: equal);
    return query.snapshots().map(
      (s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
    );
  }

  Stream<Json?> document(String collection, String id) => db
      .collection(collection)
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? {'id': d.id, ...d.data()!} : null);
  Future<Json> call(String name, Json data) async {
    final result = await functions
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
        )
        .call(data);
    return json(result.data);
  }

  Future<void> save(String type, String id, Json value) async {
    await call('saveCatalog', {
      'type': type,
      'id': id,
      'value': catalogPayload(type, value),
    });
  }
}

final repository = PosRepository();
