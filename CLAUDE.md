# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a downstream project template based on Eclipse Dataspace Components (EDC). It provides two runtimes (Control Plane and Data Plane) and an extensible architecture for building custom dataspace solutions using EDC's service extension model.

## Build Commands

```bash
./gradlew build                              # Build all modules
./gradlew dockerize                          # Build Docker images
./gradlew dockerize -Dplatform="linux/amd64" # Build Docker images for specific platform
```

Run runtimes locally with config files:

```bash
java -Dedc.fs.config=config/controlplane.properties -jar runtimes/controlplane/build/libs/controlplane.jar
java -Dedc.fs.config=config/dataplane.properties -jar runtimes/dataplane/build/libs/dataplane.jar
```

There are no tests in this project currently.

## Architecture

The project follows EDC's **service extension model** with two module types:

- **Extensions** (`extensions/`): Custom functionality implementing `ServiceExtension` interface. Extensions are discovered via Java SPI (service loader files in `META-INF/services/`). Lifecycle: `prepare()` → `initialize()` → `start()` → `shutdown()`.
- **Runtimes** (`runtimes/`): Executable applications that compose extensions into deployable units. Each runtime produces a Shadow (fat) JAR and a Docker image. The main class for all runtimes is `org.eclipse.edc.boot.system.runtime.BaseRuntime`.

### Control Plane (`runtimes/controlplane/`)
Handles catalog, negotiation, and transfer process management. Ports: management (19193), protocol/DSP (19194), control (19192).

### Data Plane (`runtimes/dataplane/`)
Handles actual data transfer. Ports: base API (38181), control (38182).

## Key Configuration

- **Version catalog**: `gradle/libs.versions.toml` — EDC BOM version and plugin versions
- **Gradle properties**: `gradle.properties` — group ID, version, annotation processor versions
- **Runtime configs**: `config/*.properties` — per-component EDC configuration
- **Root build.gradle.kts**: Applies EDC build plugin, Checkstyle, Shadow, and Docker plugins to all subprojects

## Adding a New Extension

1. Create a new directory under `extensions/`
2. Add a `build.gradle.kts` with `java-library` plugin and EDC SPI dependency
3. Implement `ServiceExtension` interface with `@Extension` annotation
4. Register via SPI: create `src/main/resources/META-INF/services/org.eclipse.edc.spi.system.ServiceExtension` containing the fully qualified class name
5. Add the extension as a dependency in the target runtime's `build.gradle.kts`
6. Include the module in `settings.gradle.kts`

## Build System Notes

- Gradle Kotlin DSL with version catalog (`libs.*` accessors)
- EDC build plugin (`org.eclipse.edc.edc-build`) provides annotation processing for `@Extension` metadata
- Docker images use `eclipse-temurin` JRE Alpine base with built-in health checks (`/api/check/health`)
- Optional dependencies for Hashicorp Vault and PostgreSQL persistence are commented out in runtime build files
