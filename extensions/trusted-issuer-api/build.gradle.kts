plugins {
    `java-library`
}

dependencies {
    implementation(libs.edc.spi.core)
    implementation(libs.edc.spi.identity.trust)
    implementation("org.eclipse.edc:web-spi:${libs.versions.edc.get()}")
    implementation("org.eclipse.edc:verifiable-credentials-spi:${libs.versions.edc.get()}")
    implementation("jakarta.ws.rs:jakarta.ws.rs-api:3.1.0")
}

edcBuild {
    publish.set(false)
}
