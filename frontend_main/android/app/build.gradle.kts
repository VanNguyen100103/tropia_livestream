plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    // ĐÃ SỬA: Cập nhật namespace theo file JSON mới
    namespace = "com.thienhai.tropia_mobile_app_android"
    
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        
        // Bắt buộc để dùng thư viện java.time trên Android cũ
        isCoreLibraryDesugaringEnabled = true 
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // ĐÃ SỬA: Cập nhật ID ứng dụng theo file JSON mới
        applicationId = "com.thienhai.tropia_mobile_app_android"
        
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        multiDexEnabled = true 
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Thư viện hỗ trợ Java 8 features (bản 2.1.4 để fix lỗi build)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}