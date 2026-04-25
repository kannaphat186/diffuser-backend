import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // v6.0.0: Firebase / FCM
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val allowDebugSigningForRelease =
    (project.findProperty("allowDebugSigningForRelease")?.toString()?.toBooleanStrictOrNull() == true)

val hasRealReleaseKeystore = keystorePropertiesFile.exists()

if (hasRealReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
} else if (!allowDebugSigningForRelease) {
    throw GradleException(
        """
        Missing android/key.properties for release signing.

        Create:
          app/android/key.properties
        from:
          app/android/key.properties.example

        Then fill in:
          storeFile=...
          storePassword=...
          keyAlias=...
          keyPassword=...

        If you intentionally want a throwaway local APK signed with the debug key,
        re-run with:
          -PallowDebugSigningForRelease=true

        This escape hatch is for local testing only. Do NOT distribute that APK.
        """.trimIndent()
    )
} else {
    logger.warn(
        """
        WARNING: Building RELEASE with DEBUG signing because:
          - android/key.properties is missing
          - -PallowDebugSigningForRelease=true was supplied

        This APK is for local testing only and must NOT be distributed.
        """.trimIndent()
    )
}

android {
    namespace = "com.diffuser.app"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // v6.0.0: aligned with the existing google-services.json which
        // was provisioned for com.diffuser.app in the diffuser-ea88
        // Firebase project. If you prefer to keep com.scent.sense you
        // must register a new Android app under that package name in
        // the Firebase Console and replace google-services.json.
        applicationId = "com.diffuser.app"
        minSdk = 24
        targetSdk = 34
        versionCode = 36
        versionName = "6.0.0"
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (hasRealReleaseKeystore) {
                val storeFileValue = keystoreProperties["storeFile"]?.toString()
                    ?: throw GradleException("Missing 'storeFile' in android/key.properties")
                storeFile = file(storeFileValue)
                storePassword = keystoreProperties["storePassword"]?.toString()
                    ?: throw GradleException("Missing 'storePassword' in android/key.properties")
                keyAlias = keystoreProperties["keyAlias"]?.toString()
                    ?: throw GradleException("Missing 'keyAlias' in android/key.properties")
                keyPassword = keystoreProperties["keyPassword"]?.toString()
                    ?: throw GradleException("Missing 'keyPassword' in android/key.properties")
            } else {
                initWith(getByName("debug"))
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }

        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
}
