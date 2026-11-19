import 'package:flutter/widgets.dart';

/// Pages d'étape d'une commande (paiement, validation du prix, aller chez le
/// client, terminer la prestation) : une seule à la fois par étape et par
/// commande, et fermée d'office quand l'étape est passée.
///
/// Sans ce registre, deux écrans de la même commande (ouverture par une
/// notification, par l'accueil…) ouvraient chacun leur page : deux pages
/// identiques l'une sous l'autre, il fallait appuyer deux fois (« Le prix a
/// déjà été validé », « Cette commande est déjà payée ») et les deux notes
/// vocales se coupaient l'une l'autre.
///
/// Identifiant : '<étape>:<commande>', ex. 'pay:123'.
class StepSheets {
  StepSheets._();

  /// Étapes dont la page est affichée ou va l'être.
  static final Set<String> _claimed = {};
  static final Map<String, Route<dynamic>> _routes = {};

  static String id(String step, String? orderId) => '$step:${orderId ?? ''}';

  /// Change à chaque fermeture : l'écran de la commande se redessine (bouton
  /// de secours, réouverture de la page si l'étape n'est pas finie).
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// Page affichée ou en cours d'ouverture.
  static bool isOpen(String id) => _claimed.contains(id);

  /// Réserve l'ouverture : false si la page est déjà là (ne pas la rouvrir).
  static bool claim(String id) => _claimed.add(id);

  /// Page fermée (quelle qu'en soit la raison). Avec [route] : seulement si
  /// c'est encore cette page-là (une nouvelle a pu la remplacer entre-temps).
  static void release(String id, {Route<dynamic>? route}) {
    if (route != null && _routes[id] != route) return;
    final had = _claimed.remove(id);
    _routes.remove(id);
    // Hors de la fermeture en cours (arbre des widgets verrouillé).
    if (had) Future.microtask(() => changes.value++);
  }

  /// Ferme la page de cette étape si elle est affichée (étape passée).
  static void close(String id) {
    final route = _routes[id];
    if (route == null || !route.isActive) return;
    _forceClosed.add(id);
    if (route.isCurrent) {
      route.navigator?.pop();
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  static final Set<String> _forceClosed = {};

  /// La page a été fermée d'office (étape passée), pas par l'utilisateur.
  static bool consumeForceClosed(String id) => _forceClosed.remove(id);
}

/// À placer dans la page d'étape : la relie au registre, pour qu'elle puisse
/// être fermée d'office.
class StepSheetScope extends StatefulWidget {
  final String? stepId;
  final Widget child;

  const StepSheetScope({super.key, required this.stepId, required this.child});

  @override
  State<StepSheetScope> createState() => _StepSheetScopeState();
}

class _StepSheetScopeState extends State<StepSheetScope> {
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = widget.stepId;
    final route = ModalRoute.of(context);
    if (id != null && route != null) {
      _route = route;
      StepSheets._claimed.add(id);
      StepSheets._routes[id] = route;
    }
  }

  @override
  void dispose() {
    final id = widget.stepId;
    if (id != null && _route != null) StepSheets.release(id, route: _route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
