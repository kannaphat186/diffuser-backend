// android/build.gradle.kts — v5.2.5 (Apr 2026)
// Root Android build script. Keep this MINIMAL.
//
// Fix scope:
// - Only fix reactive_ble_mobile JVM target mismatch
// - Do not mutate every plugin globally
// - Do not touch app/business logic
// - Do not refactor unrelated Android config

import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

rootProject.layout.buildDirectory.set(file("../build"))

subprojects {
    project.layout.buildDirectory.set(
        rootProject.layout.buildDirectory.dir(project.name)
    )

    // Fix ONLY the offending plugin.
    // We apply the override after that plugin finishes configuring itself,
    // so its own defaults cannot reset the task values back to 1.8.
    if (name == "reactive_ble_mobile") {
        afterEvaluate {
            tasks.withType<JavaCompile>().configureEach {
                sourceCompatibility = JavaVersion.VERSION_17.toString()
                targetCompatibility = JavaVersion.VERSION_17.toString()
                options.compilerArgs.add("-Xlint:-options")
            }

            tasks.withType<KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}