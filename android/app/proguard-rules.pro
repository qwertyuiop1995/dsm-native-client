-keepattributes *Annotation*
-keep class kotlinx.serialization.** { *; }
-dontwarn org.conscrypt.**

# Lifecycle 2.8 在 Compose 1.6 上通过反射兼容旧版 LocalLifecycleOwner。
# 必须显式保留入口，否则 Release 的 R8 混淆会导致应用启动闪退。
-keep public class androidx.compose.ui.platform.AndroidCompositionLocals_androidKt {
    public static *** getLocalLifecycleOwner();
}

# androidx.security:security-crypto 依赖 com.google.crypto.tink，
# Tink 编译时引用了 errorprone 注解但运行时不需要这些类。
-dontwarn com.google.errorprone.annotations.**
-dontwarn com.google.crypto.tink.**
