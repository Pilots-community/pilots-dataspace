plugins {
    `java-library`
}

dependencies {
    implementation(libs.edc.ih.spi)
    implementation(libs.edc.ih.spi.credentials)
    implementation(libs.edc.ih.spi.did)
    implementation(libs.edc.spi.identity.did)
}

edcBuild {
    publish.set(false)
}
