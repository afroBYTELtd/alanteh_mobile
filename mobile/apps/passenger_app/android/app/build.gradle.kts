import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The properties file holds storeFile, storePassword,
// keyAlias and keyPassword; it is never committed. android/key.properties
// (git-ignored) wins; otherwise ~/.config/alanteh/signing/passenger.properties,
// which lives outside every checkout so all worktrees on the Mac share it.
val releaseSigningFile: File? = listOf(
    rootProject.file("key.properties"),
    File(System.getProperty("user.home"), ".config/alanteh/signing/passenger.properties"),
).firstOrNull { it.isFile }
val releaseSigning = Properties().apply {
    releaseSigningFile?.let { file -> FileInputStream(file).use { load(it) } }
}

android {
    namespace = "io.alanteh.passenger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.alanteh.passenger"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningFile != null) {
            create("release") {
                storeFile = file(releaseSigning.getProperty("storeFile"))
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Never the debug key: Google Maps API keys are restricted to the
            // release certificate's SHA-1.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// Fail a release build up front, rather than producing an unsigned or
// debug-signed APK, when no release signing file is present.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { task ->
        task.project == project &&
            (task.name.startsWith("assemble") ||
                task.name.startsWith("bundle") ||
                task.name.startsWith("package")) &&
            task.name.endsWith("Release")
    }
    if (buildsRelease && releaseSigningFile == null) {
        throw GradleException(
            "No release signing configured. Create android/key.properties or " +
                "~/.config/alanteh/signing/passenger.properties (see DEVELOPMENT.md).",
        )
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
