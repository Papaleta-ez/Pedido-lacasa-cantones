import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'firebase_web_options.dart';

import 'package:firebase_core/firebase_core.dart';

import 'core/theme.dart';
import 'core/firebase_connection.dart';
import 'features/auth/access_gate.dart';

const mode = String.fromEnvironment('MODO', defaultValue: 'mesero');
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? error;
  try {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    await Firebase.initializeApp(
      name: localFirebase ? 'cantones-local' : null,
      options: localFirebase
          ? localFirebaseOptions
          : apiKey.isEmpty
          ? (kIsWeb ? webFirebaseOptions : null)
          : const FirebaseOptions(
              apiKey: apiKey,
              appId: String.fromEnvironment('FIREBASE_APP_ID'),
              messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
              projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
              authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
              storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
            ),
    );
    await connectLocalFirebase();
    if (!['mesero', 'cocina', 'dueno'].contains(mode)) {
      throw StateError('MODO inválido');
    }
  } catch (e) {
    error = '$e';
  }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'La Casa Cantones',
      theme: posTheme,
      home: error == null
          ? (localFirebase
                ? const Banner(
                    message: 'PRUEBA LOCAL',
                    location: BannerLocation.topEnd,
                    child: AccessGate(mode: mode),
                  )
                : const AccessGate(mode: mode))
          : Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText(
                    'No se pudo conectar Firebase.\n$error\nRevisá la guía de instalación.',
                  ),
                ),
              ),
            ),
    ),
  );
}
