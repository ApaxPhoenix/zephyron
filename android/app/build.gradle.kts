import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystore = Properties().apply {
    val source = rootProject.file("key.properties")
    if (source.exists()) load(FileInputStream(source))
}

android {
    namespace = "com.aveloux.zephyron"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aveloux.zephyron"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        val signature = System.getenv("SHA256_SIGNATURE") ?: "YOUR_DEBUG_HEX_HASH"
        buildConfigField("String", "SHA256_SIGNATURE", "\"$signature\"")
    }

    signingConfigs {
        create("release") {
            if (!keystore.isEmpty) {
                keyAlias = keystore.getProperty("keyAlias")
                keyPassword = keystore.getProperty("keyPassword")
                storeFile = file(keystore.getProperty("storeFile"))
                storePassword = keystore.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (keystore.isEmpty) "debug" else "release"
            )

            // Enable R8 code shrinking, obfuscation, and optimization
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Ensures Gradle picks up libtor.so binaries from src/main/jniLibs/<abi>/
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    packaging {
        jniLibs {
            // Extracts .so binaries to disk on install so dlopen/Dart FFI can access them
            useLegacyPackaging = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        )
    }
}

flutter {
    source = "../.."
}