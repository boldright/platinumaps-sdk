pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Pin AGP and Kotlin to the same versions the Flutter plugin and
    // the Android sample declare, so all three projects compile against
    // the same toolchain. AGP 9.0.1 (preview) emits a
    // `fun Project.android()` deprecation warning under Kotlin DSL;
    // 8.12.0 is the latest stable.
    id("com.android.application") version "8.12.0" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
}

include(":app")
