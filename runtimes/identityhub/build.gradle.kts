import com.bmuschko.gradle.docker.tasks.image.DockerBuildImage
import com.github.jengelman.gradle.plugins.shadow.ShadowJavaPlugin

plugins {
    id("application")
    alias(libs.plugins.shadow)
    alias(libs.plugins.docker)
}

dependencies {
    runtimeOnly(project(":extensions:superuser-seed"))
    runtimeOnly(project(":extensions:did-example-resolver"))
    runtimeOnly(libs.edc.bom.identityhub)

    // Hashicorp Vault
    runtimeOnly(libs.edc.vault.hashicorp)
}

tasks.withType<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar> {
    exclude("**/pom.properties", "**/pom.xm")
    mergeServiceFiles()
    archiveFileName.set("${project.name}.jar")
}

application {
    mainClass.set("org.eclipse.edc.boot.system.runtime.BaseRuntime")
}

edcBuild {
    publish.set(false)
}

// configure the "dockerize" task
tasks.register("dockerize", DockerBuildImage::class) {
    val dockerContextDir = project.projectDir
    dockerFile.set(file("$dockerContextDir/src/main/docker/Dockerfile"))
    images.add("${project.name}:${project.version}")
    images.add("${project.name}:latest")
    // specify platform with the -Dplatform flag:
    if (System.getProperty("platform") != null)
        platform.set(System.getProperty("platform"))
    buildArgs.put("JAR", "build/libs/${project.name}.jar")
    inputDir.set(file(dockerContextDir))
    dependsOn(tasks.named(ShadowJavaPlugin.SHADOW_JAR_TASK_NAME))
}
