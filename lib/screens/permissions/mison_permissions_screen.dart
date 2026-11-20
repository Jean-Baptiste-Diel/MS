import 'package:booking_system_flutter/component/mison_app_bar.dart' show kMisonGold, kMisonDark, kMisonFieldBg;
import 'package:booking_system_flutter/main.dart';
import 'package:booking_system_flutter/utils/constant.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:permission_handler/permission_handler.dart';

/// Autorisations utiles à MISON, avec leur raison (affichée à l'utilisateur).
class _PermissionItem {
  final Permission permission;
  final IconData icon;
  final String title;
  final String reason;

  const _PermissionItem(this.permission, this.icon, this.title, this.reason);
}

List<_PermissionItem> _items() {
  final isArtisan = appStore.userType == USER_TYPE_PROVIDER;
  return [
    _PermissionItem(
      Permission.notification,
      Icons.notifications_active_outlined,
      'Notifications',
      isArtisan
          ? 'Recevoir les nouvelles commandes et les messages des clients.'
          : 'Être prévenu quand un ouvrier accepte, arrive ou vous écrit.',
    ),
    const _PermissionItem(
      Permission.microphone,
      Icons.mic_none_rounded,
      'Micro',
      'Les appels et les messages vocaux avec MISON et votre interlocuteur.',
    ),
    _PermissionItem(
      Permission.locationWhenInUse,
      Icons.location_on_outlined,
      'Localisation',
      isArtisan
          ? 'Trouver les commandes près de vous et montrer votre trajet au client.'
          : "Indiquer l'adresse de la prestation et suivre l'ouvrier en route.",
    ),
    const _PermissionItem(
      Permission.camera,
      Icons.photo_camera_outlined,
      'Appareil photo',
      'Envoyer des photos et des vidéos dans la discussion.',
    ),
  ];
}

bool _shownThisLaunch = false;

/// À l'ouverture de l'app (connecté ou non) : page « Autorisations » tant qu'il
/// en manque une. Conforme aux règles des stores : chaque autorisation est
/// expliquée, rien n'est forcé (« Plus tard »), et la page revient à
/// l'ouverture suivante tant que tout n'est pas autorisé.
Future<void> showPermissionsIfNeeded() async {
  if (_shownThisLaunch) return;
  _shownThisLaunch = true;
  final missing = await _missing();
  if (missing.isEmpty) return;
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const MisonPermissionsScreen()),
  );
}

Future<List<_PermissionItem>> _missing() async {
  final missing = <_PermissionItem>[];
  for (final item in _items()) {
    try {
      final status = await item.permission.status;
      if (!status.isGranted && !status.isLimited && !status.isProvisional) missing.add(item);
    } catch (_) {
      // Autorisation non gérée sur ce téléphone : ignorée.
    }
  }
  return missing;
}

class MisonPermissionsScreen extends StatefulWidget {
  const MisonPermissionsScreen({super.key});

  @override
  State<MisonPermissionsScreen> createState() => _MisonPermissionsScreenState();
}

class _MisonPermissionsScreenState extends State<MisonPermissionsScreen> with WidgetsBindingObserver {
  final Map<Permission, PermissionStatus> _status = {};
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Retour des Réglages du téléphone : statut relu, page fermée si tout est bon.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  bool _ok(PermissionStatus? s) => s != null && (s.isGranted || s.isLimited || s.isProvisional);

  bool get _allGranted => _items().every((i) => _ok(_status[i.permission]));

  /// Refusée pour de bon : seul le passage par les Réglages peut l'accorder.
  bool get _needsSettings => _items().any((i) {
        final s = _status[i.permission];
        return s != null && !_ok(s) && (s.isPermanentlyDenied || s.isRestricted);
      });

  Future<void> _refresh() async {
    for (final item in _items()) {
      try {
        _status[item.permission] = await item.permission.status;
      } catch (_) {
        _status[item.permission] = PermissionStatus.granted; // non géré : ne bloque pas
      }
    }
    if (!mounted) return;
    setState(() {});
    if (_allGranted) Navigator.of(context).maybePop();
  }

  Future<void> _askAll() async {
    if (_asking) return;
    setState(() => _asking = true);
    try {
      // Une demande à la fois : les fenêtres du système s'enchaînent.
      for (final item in _items()) {
        if (_ok(_status[item.permission])) continue;
        try {
          _status[item.permission] = await item.permission.request();
        } catch (_) {}
        if (mounted) setState(() {});
      }
    } finally {
      if (mounted) setState(() => _asking = false);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return Scaffold(
      backgroundColor: context.cardColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Image.asset('assets/logo/logo_transparent.png', height: 56)),
              24.height,
              Text('AUTORISATIONS', style: boldTextStyle(size: 15, color: kMisonGold, letterSpacing: 0.3)),
              6.height,
              Text('Pour que MISON fonctionne bien',
                  style: primaryTextStyle(size: 26, color: kMisonDark, weight: FontWeight.w600)),
              8.height,
              Text(
                'Ces autorisations servent uniquement aux fonctions ci-dessous. '
                'Vous pouvez les modifier à tout moment dans les réglages du téléphone.',
                style: secondaryTextStyle(size: 14, color: kMisonDark.withValues(alpha: 0.7)),
              ),
              20.height,
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => 10.height,
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final granted = _ok(_status[item.permission]);
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kMisonFieldBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(item.icon, color: kMisonGold, size: 26),
                          14.width,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title, style: boldTextStyle(size: 16, color: kMisonDark)),
                                4.height,
                                Text(item.reason, style: secondaryTextStyle(size: 13)),
                              ],
                            ),
                          ),
                          8.width,
                          Icon(
                            granted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: granted ? Colors.green : Colors.grey.shade400,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              12.height,
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _asking ? null : (_needsSettings ? openAppSettings : _askAll),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kMisonGold,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _needsSettings ? 'Ouvrir les réglages' : 'Tout autoriser',
                    style: boldTextStyle(color: Colors.white, size: 16),
                  ),
                ),
              ),
              if (_needsSettings) ...[
                8.height,
                Text(
                  'Une autorisation a été refusée : activez-la dans les réglages du téléphone, puis revenez ici.',
                  style: secondaryTextStyle(size: 13),
                ),
              ],
              4.height,
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text('Plus tard', style: secondaryTextStyle(size: 14, color: kMisonDark.withValues(alpha: 0.7))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
