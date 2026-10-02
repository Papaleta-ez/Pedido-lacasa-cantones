import '../../core/firebase_connection.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../pos/pos_page.dart';
import '../kitchen/kitchen_page.dart';
import '../owner/owner_page.dart';

class AccessGate extends StatefulWidget {
  final String mode;
  const AccessGate({super.key, required this.mode});
  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate> {
  final auth = posAuth;
  late final tokenStream = auth.idTokenChanges();
  late final Future<void> start = initialize();
  Future<void> initialize() async {
    if (widget.mode != 'dueno') {
      if (auth.currentUser != null && !auth.currentUser!.isAnonymous) {
        await auth.signOut();
      }
      await auth.signInAnonymouslyIfNeeded();
      await repository.call('registerDevice', {
        'mode': widget.mode,
        'name': 'Terminal ${widget.mode}',
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: start,
    builder: (c, s) {
      if (s.hasError) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText('${s.error}'),
                const Text(
                  'Activá autenticación anónima y desplegá las funciones.',
                ),
              ],
            ),
          ),
        );
      }
      if (s.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return StreamBuilder<User?>(
        stream: tokenStream,
        builder: (c, user) {
          if (widget.mode == 'dueno') {
            if (user.data == null || user.data!.isAnonymous) {
              return const OwnerLogin();
            }
            return FutureBuilder<IdTokenResult>(
              future: user.data!.getIdTokenResult(),
              builder: (c, t) {
                if (!t.hasData) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (t.data!.claims?['owner'] != true) {
                  return Scaffold(
                    body: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                            'Esta cuenta no tiene claim owner.\nUID: ${user.data!.uid}',
                          ),
                          FilledButton(
                            onPressed: () async {
                              await auth.currentUser!.getIdToken(true);
                              setState(() {});
                            },
                            child: const Text('Actualizar autorización'),
                          ),
                          TextButton(
                            onPressed: auth.signOut,
                            child: const Text('Salir'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const OwnerPage();
              },
            );
          }
          if (user.data == null) {
            return const Scaffold(
              body: Center(child: Text('Sesión perdida. Reiniciá la app.')),
            );
          }
          return StreamBuilder<Json?>(
            stream: repository.document('devices', user.data!.uid),
            builder: (c, d) {
              if (d.hasError) {
                return Scaffold(
                  body: Center(child: SelectableText('${d.error}')),
                );
              }
              if (d.data?['active'] != true || d.data?['role'] != widget.mode) {
                return Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_clock, size: 72, color: gold),
                          const SizedBox(height: 24),
                          const Text(
                            'Esperando autorización del dueño',
                            style: TextStyle(fontSize: 24),
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            'UID: ${user.data!.uid}\nModo solicitado: ${widget.mode}',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return widget.mode == 'cocina'
                  ? const KitchenPage()
                  : const PosPage();
            },
          );
        },
      );
    },
  );
}

extension on FirebaseAuth {
  Future<void> signInAnonymouslyIfNeeded() async {
    if (currentUser == null) await signInAnonymously();
  }
}

class OwnerLogin extends StatefulWidget {
  const OwnerLogin({super.key});
  @override
  State<OwnerLogin> createState() => _OwnerLoginState();
}

class _OwnerLoginState extends State<OwnerLogin> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() => busy = true);
    try {
      await posAuth.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
    } catch (e) {
      if (mounted) notice(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              Image.asset('assets/images/logo_casa_cantones.png', height: 120),
              const SizedBox(height: 24),
              const Text('Administración', style: TextStyle(fontSize: 28)),
              const SizedBox(height: 24),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : login,
                child: Text(busy ? 'Conectando…' : 'Entrar'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
