"""Idempotent configuration for Flutter 3.35+ generated Android/iOS projects."""
import plistlib
from pathlib import Path

root=Path(__file__).resolve().parent
gradle=root/'android/app/build.gradle.kts'
if not gradle.exists():
    raise SystemExit('未找到 Kotlin DSL Android 项目。请使用 Flutter 3.35+ 运行 bootstrap.sh。')
text=gradle.read_text()
if 'isCoreLibraryDesugaringEnabled' not in text:
    text=text.replace('compileOptions {','compileOptions {\n        isCoreLibraryDesugaringEnabled = true',1)
if 'desugar_jdk_libs' not in text:
    text+='\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
gradle.write_text(text)
manifest=root/'android/app/src/main/AndroidManifest.xml'
text=manifest.read_text()
for permission in ['INTERNET','RECEIVE_BOOT_COMPLETED','POST_NOTIFICATIONS']:
    if f'android.permission.{permission}' not in text:
        text=text.replace('<application',f'<uses-permission android:name="android.permission.{permission}"/>\n    <application',1)
text=text.replace('android:label="dentstudy"','android:label="齿间"')
if 'android:allowBackup' not in text:
    text=text.replace('<application','<application android:allowBackup="false"',1)
if 'ScheduledNotificationReceiver' not in text:
    text=text.replace('</application>','''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
    </application>''')
manifest.write_text(text)
# Allow local HTTP only for Android debug builds; release networking requires HTTPS.
debug=root/'android/app/src/debug/AndroidManifest.xml'
debug.parent.mkdir(parents=True,exist_ok=True)
debug.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET"/>
  <application android:usesCleartextTraffic="true"/>
</manifest>''')
keep=root/'android/app/src/main/res/raw/keep.xml'
keep.parent.mkdir(parents=True,exist_ok=True)
keep.write_text('<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@mipmap/ic_launcher" />')
info=root/'ios/Runner/Info.plist'
with info.open('rb') as f: data=plistlib.load(f)
data['CFBundleDisplayName']='齿间'
data['NSLocalNetworkUsageDescription']='在开发时连接您配置的局域网题库服务。'
# Local transport exception is scoped to local networking, never arbitrary Internet HTTP.
data.setdefault('NSAppTransportSecurity',{})['NSAllowsLocalNetworking']=True
with info.open('wb') as f:plistlib.dump(data,f)
delegate=root/'ios/Runner/AppDelegate.swift'
text=delegate.read_text()
if 'import UserNotifications' not in text:
    text='import UserNotifications\n'+text
if 'UNUserNotificationCenter.current().delegate' not in text:
    text=text.replace('GeneratedPluginRegistrant.register(with: self)',
      'UNUserNotificationCenter.current().delegate = self\n    GeneratedPluginRegistrant.register(with: self)')
delegate.write_text(text)
print('已配置通知接收器、desugaring、调试网络与应用名称。')
