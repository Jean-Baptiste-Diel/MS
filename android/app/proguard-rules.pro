# Règles ProGuard / R8 de l'app (les règles Stripe du modèle d'origine ont été retirées).

# Traces de plantage lisibles (Crashlytics / Play Console).
-keepattributes SourceFile,LineNumberTable,Signature,InnerClasses,EnclosingMethod,*Annotation*

# Code natif de l'app (canaux Flutter : audio des appels…).
-keep class com.mison.serviceuser.** { *; }

# Appels entrants : le plugin sérialise ses données avec Gson (réflexion).
-keep class com.hiennv.flutter_callkit_incoming.** { *; }

# Appels audio Agora (classes appelées depuis le code natif).
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# Gson : types génériques conservés.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Composants différés de Flutter (Play Core) non utilisés.
-dontwarn com.google.android.play.core.**
