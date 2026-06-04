# Building with Java VicarIO

This Docker image uses the Java-based VicarIO library for VICAR image format conversion. The Java version provides better image quality with proper dynamic range rescaling compared to the Python implementation.

## Obtaining vicario.jar

### Option 1: Build from Source (Recommended)

1. Clone the VicarIO repository:
   ```bash
   git clone git@github.jpl.nasa.gov:MIPL/vicario.git
   cd vicario
   ```

2. Build the FAT JAR (includes all dependencies):
   ```bash
   mvn -U -Pshade clean install
   ```

3. Copy the JAR to the Docker build context:
   ```bash
   cp target/vicario-*-FAT.jar /path/to/tig/terrain-intelligence-generator/docker/vicario.jar
   ```

### Option 2: Download from Artifactory (JPL Internal)

If you have access to JPL's Artifactory:

```bash
# Download the latest release
curl -o vicario.jar "https://cae-artifactory.jpl.nasa.gov/artifactory/maven-libs-release-local/gov/nasa/jpl/ammos/ids/vicario/2.7.0/vicario-2.7.0-FAT.jar"
```

## Building the Docker Image

Once `vicario.jar` is in place:

```bash
cd terrain-intelligence-generator/docker
docker build -t terrain-intelligence-generator:latest .
```

## Why Java VicarIO?

The Java implementation provides:

- **Correct dynamic range handling**: Automatically rescales 16-bit VICAR images to 8-bit with `oform=byte rescale=true`
- **Better image quality**: Preserves full dynamic range during conversion
- **Native VICAR support**: Direct parsing of VICAR labels and binary data
- **Format flexibility**: Supports PNG, JPEG, TIFF output formats

The wrapper script automatically applies the correct rescaling parameters for standard 2-argument usage:
```bash
vicario input.vic output.png
```

For advanced usage, pass parameters directly:
```bash
vicario inp=input.vic out=output.png format=png oform=byte rescale=true
```
