// Android-side build script for the Platinumaps Flutter plugin.
//
// Why Kotlin DSL (`build.gradle.kts`)? Flutter 3.44 ships AGP 9,
// which only reads the new `plugins { ... }` block. The Kotlin DSL
// is also accepted by AGP 8 (the Flutter 3.32-3.43 default), so
// using it here keeps the plugin compiling on both toolchains
// without conditional templating.
//
// The plugin wraps the existing native Android SDK
// (`Android/platinumaps-sdk/`). For in-repo development the SDK's
// Kotlin sources and resources are added to this plugin's
// `sourceSets` via relative paths, so the plugin compiles as a
// single library module without any pre-built AAR. The publish
// workflow (`scripts/prepublish.py`) copies those sources into
// `src/main/kotlin/` and `src/main/res/` so the published package
// stands on its own.

group = "jp.co.boldright.platinumaps.flutter"
version = "0.1.0"

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.12.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

// AGP 8 (Flutter 3.32-3.43) requires the Kotlin Android plugin to
// be applied explicitly. AGP 9+ (Flutter 3.44+) bundles Kotlin
// built-in, and applying `kotlin-android` alongside the built-in
// setup triggers the host's
//
//   "Future versions of Flutter will fail to build if your app uses
//    plugins that apply Kotlin Gradle Plugin (KGP)"
//
// warning. Branching on the AGP major version keeps the same
// plugin source working on both toolchains. See
// https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION
    .substringBefore('.').toInt()
if (agpMajor < 9) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

android {
    // The R / BuildConfig classes are generated under this namespace.
    // The Kotlin sources we pull in from `Android/platinumaps-sdk/`
    // live in `jp.co.boldright.platinumaps.sdk` and reach for `R` /
    // `BuildConfig` unqualified — so we keep the namespace aligned
    // with the SDK package even though the plugin's own glue lives
    // in `jp.co.boldright.platinumaps.flutter` (declared in
    // `pubspec.yaml` as the Flutter plugin package).
    namespace = "jp.co.boldright.platinumaps.sdk"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // The vendored SDK sources reach for `BuildConfig.DEBUG`.
        // AGP 8+ requires an explicit opt-in to generate the class.
        buildConfig = true
    }

    sourceSets {
        getByName("main") {
            java.srcDirs(
                "src/main/kotlin",
                // In-repo development: pull the SDK sources directly
                // so the single library module compiles them in. The
                // publish workflow copies these files into
                // `src/main/kotlin/` before uploading to pub.dev.
                "../../../Android/platinumaps-sdk/src/main/java",
            )
            res.srcDirs(
                "../../../Android/platinumaps-sdk/src/main/res",
            )
        }
    }
}

// Configure the Kotlin compile tasks directly instead of via the
// `kotlin { compilerOptions { … } }` extension block. The extension
// accessor is only statically resolved when the Kotlin plugin was
// loaded through `plugins { … }`; under AGP 8 (Flutter 3.32-3.43)
// the plugin is brought in via `apply(plugin = ...)` above, so the
// extension accessor disappears and the script fails to compile.
// `tasks.withType<KotlinCompile>` is a plain Gradle accessor and
// resolves on both AGP 8 and AGP 9.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // Same transitive dependencies the SDK module declares in
    // `Android/platinumaps-sdk/build.gradle`.
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.browser:browser:1.8.0")
    implementation("com.google.android.gms:play-services-location:21.3.0")

    testImplementation("junit:junit:4.13.2")
}
