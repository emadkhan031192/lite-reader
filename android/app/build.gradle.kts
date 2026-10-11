plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.afzal.litereader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.afzal.litereader"
        minSdk = 24
        targetSdk = 35
        // Uses the version code from pubspec.yaml.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing: uses KEYSTORE_PATH / KEYSTORE_PASSWORD / KEY_ALIAS /
    // KEY_PASSWORD when they exist (CI decodes KEYSTORE_BASE64 there).
    // Falls back to the debug keystore so the build never fails.
    val keystorePath = System.getenv("KEYSTORE_PATH")
        ?: "${projectDir}/keystore.jks"
    val keystoreFile = file(keystorePath)
    val hasKeystore = keystoreFile.exists() &&
        !System.getenv("KEYSTORE_PASSWORD").isNullOrEmpty() &&
        !System.getenv("KEY_ALIAS").isNullOrEmpty() &&
        !System.getenv("KEY_PASSWORD").isNullOrEmpty()

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                storeFile = keystoreFile
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Shrink the release APK: R8 + resource shrinking.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
