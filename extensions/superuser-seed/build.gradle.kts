plugins {
    `java-library`
}

dependencies {
    implementation(libs.edc.ih.spi)
    implementation(libs.edc.ih.spi.credentials)
}

edcBuild {
    publish.set(false)
}
