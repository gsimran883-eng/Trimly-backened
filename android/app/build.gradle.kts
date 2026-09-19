plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val isReleaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
}

android {
    namespace = "com.clipsnap.editor"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.clipsnap.editor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        multiDexEnabled = true
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            val keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                ?: keystoreProperties.getProperty("keyAlias")
            val keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                ?: keystoreProperties.getProperty("keyPassword")
            val storeFilePath = System.getenv("ANDROID_STORE_FILE")
                ?: keystoreProperties.getProperty("storeFile")
            val storePassword = System.getenv("ANDROID_STORE_PASSWORD")
                ?: keystoreProperties.getProperty("storePassword")
            val hasPlaceholder =
                listOf(keyAlias, keyPassword, storeFilePath, storePassword).any {
                    it?.startsWith("REPLACE_WITH_") == true
                }

            if (
                !keyAlias.isNullOrBlank() &&
                    !keyPassword.isNullOrBlank() &&
                    !storeFilePath.isNullOrBlank() &&
                    !storePassword.isNullOrBlank() &&
                    !hasPlaceholder
            ) {
                signingConfig = signingConfigs.create("release") {
                    this.keyAlias = keyAlias
                    this.keyPassword = keyPassword
                    this.storeFile = file(storeFilePath)
                    this.storePassword = storePassword
                }
            } else if (isReleaseTaskRequested) {
                if (hasPlaceholder) {
                    throw GradleException(
                        "Release signing contains placeholder values. Replace REPLACE_WITH_* before building release.",
                    )
                }
                throw GradleException(
                    "Missing release signing config. Set ANDROID_KEY_PASSWORD and ANDROID_STORE_PASSWORD env vars, and set ANDROID_KEY_ALIAS/ANDROID_STORE_FILE env vars or android/key.properties.",
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.03")

    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.profileinstaller:profileinstaller:1.4.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    testImplementation("junit:junit:4.13.2")

    // Google ML Kit subject segmentation for masking subject/background.
    implementation("com.google.android.gms:play-services-mlkit-subject-segmentation:16.0.0-beta1")

    implementation("com.google.ads.mediation:facebook:6.18.0.0")

    // MediaPipe vision tasks for interactive masking/depth-related vision flows.
    implementation("com.google.mediapipe:tasks-vision:0.10.35")

    // Coil Compose for clean Compose thumbnail/image loading in Android-native UI.
    implementation("io.coil-kt:coil-compose:2.6.0")
}

flutter {
    source = "../.."
}
