# Keep TensorFlow Lite GPU delegate classes
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Keep Google ML Kit Face Detection classes
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Keep ML Kit internal dependencies
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_vision_common.**

# Keep TensorFlow GPU backend classes (specific to error)
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory$Options { *; }
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory$Options$GpuBackend { *; }
