import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

const localFirebase = bool.fromEnvironment('LOCAL', defaultValue: false);
const localHost = String.fromEnvironment(
  'LOCAL_HOST',
  defaultValue: '127.0.0.1',
);
const localFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSy000000000000000000000000000000000',
  appId: kIsWeb
      ? '1:123456789:web:0000000000000000000000'
      : '1:123456789:android:0000000000000000000000',
  messagingSenderId: '123456789',
  projectId: 'demo-cantones',
  authDomain: 'demo-cantones.firebaseapp.com',
);
FirebaseApp get posFirebaseApp =>
    Firebase.app(localFirebase ? 'cantones-local' : '[DEFAULT]');
FirebaseAuth get posAuth => FirebaseAuth.instanceFor(app: posFirebaseApp);
FirebaseFirestore get posFirestore =>
    FirebaseFirestore.instanceFor(app: posFirebaseApp);
FirebaseFunctions get posFunctions =>
    FirebaseFunctions.instanceFor(app: posFirebaseApp, region: 'us-central1');

Future<void> connectLocalFirebase() async {
  if (!localFirebase) return;
  if (kReleaseMode) {
    throw StateError('LOCAL solo está disponible para pruebas en debug.');
  }
  if (localHost.isEmpty ||
      localHost.contains('://') ||
      localHost.contains('/')) {
    throw StateError('LOCAL_HOST debe ser la IP de la PC, sin http ni puerto.');
  }
  await posAuth.useAuthEmulator(localHost, 9099, automaticHostMapping: false);
  posFirestore.settings = const Settings(persistenceEnabled: false);
  posFirestore.useFirestoreEmulator(
    localHost,
    8080,
    automaticHostMapping: false,
  );
  posFunctions.useFunctionsEmulator(localHost, 5001);
}
