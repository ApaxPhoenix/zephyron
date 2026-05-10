# Flutter specific rules (keep Flutter engine bindings)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class io.flutter.plugin.editing.** { *; }

# Aggressive Obfuscation for custom code
-repackageclasses ''
-allowaccessmodification
-optimizationpasses 5
-overloadaggressively

# Strip all debug lines, source file attributes, and local variable names
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}