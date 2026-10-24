# Only the Latin text recognizer is bundled; the plugin references the other script options optionally.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# ML Kit registrars are instantiated reflectively from manifest meta-data by
# firebase-components (ComponentDiscovery). Its consumer rule keeps the classes
# but not their no-arg constructors, which R8 full mode then removes.
-keepclassmembers class com.google.mlkit.common.internal.CommonComponentRegistrar {
    public <init>();
}
-keepclassmembers class com.google.mlkit.vision.common.internal.VisionCommonRegistrar {
    public <init>();
}
-keepclassmembers class com.google.mlkit.vision.text.internal.TextRegistrar {
    public <init>();
}
