/// Taille des photos envoyées au serveur. Une photo d'appareil moderne pèse
/// 3 à 8 Mo : envoyée telle quelle, elle mettait longtemps à s'afficher partout
/// où elle apparaît (avatars, listes, détail de commande).

/// Photo de profil : affichée en petit (avatar), ~100 Ko.
const double kProfilePhotoMaxSide = 800;
const int kProfilePhotoQuality = 80;

/// Pièce d'identité, preuve de profession : doit rester lisible, ~300 Ko.
const double kDocumentMaxSide = 1600;
const int kDocumentQuality = 85;

/// Photo envoyée dans le chat, ~300 Ko.
const double kChatPhotoMaxSide = 1600;
const int kChatPhotoQuality = 80;
