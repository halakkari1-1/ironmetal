// Adjusts the generated Capacitor Android project for IronMetal:
// landscape lock, immersive full screen, release signing from environment variables, version from CI.
import { readFileSync, writeFileSync, copyFileSync, existsSync } from 'node:fs';

const must = (cond, msg) => { if (!cond) { console.error('patch-android: ' + msg); process.exit(1); } };

// 1) Manifest: landscape on phones and tablets (both landscape directions)
const manifestPath = 'android/app/src/main/AndroidManifest.xml';
let manifest = readFileSync(manifestPath, 'utf8');
if (!manifest.includes('screenOrientation')) {
  manifest = manifest.replace(/<activity(\s)/, '<activity android:screenOrientation="sensorLandscape"$1');
  must(manifest.includes('sensorLandscape'), 'could not set screenOrientation');
}
writeFileSync(manifestPath, manifest);

// 2) Immersive full-screen activity
const activityPath = 'android/app/src/main/java/com/alakkari/ironmetal/MainActivity.java';
must(existsSync(activityPath), `missing ${activityPath}`);
copyFileSync('android-template/MainActivity.java', activityPath);

// 3) Signing + versioning
const gradlePath = 'android/app/build.gradle';
let gradle = readFileSync(gradlePath, 'utf8');
gradle = gradle.replace(/versionCode\s+\d+/, 'versionCode Integer.parseInt(System.getenv("IM_VERSION_CODE") ?: "1")');
gradle = gradle.replace(/versionName\s+"[^"]*"/, 'versionName(System.getenv("IM_VERSION_NAME") ?: "0.4.0")');
must(gradle.includes('IM_VERSION_CODE'), 'could not set versionCode');
const signing = `
    signingConfigs {
        release {
            if (System.getenv("IM_KEYSTORE")) {
                storeFile file(System.getenv("IM_KEYSTORE"))
                storePassword System.getenv("IM_STORE_PASSWORD")
                keyAlias System.getenv("IM_KEY_ALIAS")
                keyPassword System.getenv("IM_KEY_PASSWORD")
            }
        }
    }
`;
gradle = gradle.replace(/android\s*\{/, (m) => m + signing);
gradle = gradle.replace(/buildTypes\s*\{\s*release\s*\{/, (m) => m + '\n            signingConfig System.getenv("IM_KEYSTORE") ? signingConfigs.release : signingConfigs.debug');
must(gradle.includes('signingConfigs.release : signingConfigs.debug'), 'could not set signingConfig');
writeFileSync(gradlePath, gradle);

console.log('android project patched');
