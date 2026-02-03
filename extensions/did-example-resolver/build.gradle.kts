plugins {
    `java-library`
}

dependencies {
    implementation(libs.edc.did.core)
    implementation(libs.edc.ih.spi.did)
}

edcBuild {
    publish.set(false)
}
