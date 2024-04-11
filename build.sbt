name := "projname"
version := "0.1"

// Environment variables for Android SDK path and target platform
val androidHome = sys.env.getOrElse("ANDROID_HOME", "/")
val androidTargetPlatform = sys.env.getOrElse("ANDROID_TARGET_PLATFORM", "29")

val androidJarPath = {
  val path = s"$androidHome/platforms/android-$androidTargetPlatform/android.jar"
  println(s"Android JAR Path: $path")  // Print the path for debugging
  path
}

// Include the Android JAR in the classpath for compilation
Compile / unmanagedClasspath += Attributed.blank(file(androidJarPath))
