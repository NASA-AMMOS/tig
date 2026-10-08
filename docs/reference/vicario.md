# Building with Java VicarIO

This Docker image uses the Java-based VicarIO library for VICAR image format conversion. The Java version provides better image quality with proper dynamic range rescaling compared to the Python implementation.

## Failure mode: check the output file

VicarIO is a Java tool and the wrapper cannot tell a failed conversion from a
successful one: it **exits 0 even when it writes nothing**, printing the Java
exception on stdout. `set -e` and `&&` chains therefore do not catch its
errors — test for the output file instead:

```bash
tig vicario input.vic output.png
[ -f output.png ] || { echo "conversion failed"; exit 1; }
```

The usual way to hit this is keyword syntax with only two arguments: the
wrapper supplies `format`/`oform`/`rescale` for 2-argument calls and passes
the two arguments through positionally, so `vicario inp=input.vic
out=output.png` is read as a file literally named `inp=input.vic`, converts
nothing, and still exits 0. Use the positional form, or pass three or more
parameters if you want keywords (see [Usage](#usage)).

## Obtaining vicario

VicarIO is open source at [NASA-AMMOS/vicario](https://github.com/NASA-AMMOS/vicario)
and published to Maven Central as
[`gov.nasa.jpl.ammos.ids:vicario`](https://central.sonatype.com/artifact/gov.nasa.jpl.ammos.ids/vicario).
The image build resolves it, so nothing needs to be built or downloaded by
hand to use `vicario` through `tig` or the container.

The version is pinned in `terrain-intelligence-generator/docker/vicario/pom.xml`.
A `vicario` stage in the Dockerfile copies that version and its runtime
dependencies to `/usr/local/lib/vicario/`, and the `vicario` wrapper runs
`jpl.mipl.io.jConvertIIO` on that classpath with Java 17. To move to a new
release, change `version.vicario` in that POM and rebuild the image.

## Building the Docker Image

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

## Usage

The wrapper script automatically applies the correct rescaling parameters for standard 2-argument usage, which is positional — input first, output second:
```bash
vicario input.vic output.png
```

For advanced usage, pass parameters directly. Keyword syntax is only parsed
when three or more parameters are given:
```bash
vicario inp=input.vic out=output.png format=png oform=byte rescale=true
```

Either way, check that the output file exists — see [Failure mode](#failure-mode-check-the-output-file).
