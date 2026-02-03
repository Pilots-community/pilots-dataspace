plugins {
    `java-library`
}

dependencies {
    implementation(libs.edc.spi.core)
    implementation("org.eclipse.edc:data-plane-spi:${libs.versions.edc.get()}")
    implementation("org.eclipse.edc:web-spi:${libs.versions.edc.get()}")
    implementation("org.eclipse.edc:data-plane-http-spi:${libs.versions.edc.get()}")
    implementation("org.eclipse.edc:jersey-core:${libs.versions.edc.get()}")
    implementation("jakarta.ws.rs:jakarta.ws.rs-api:4.0.0")
}

edcBuild {
    publish.set(false)
}
