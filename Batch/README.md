# PhantomStamp Batch Runner

This directory contains the benchmark-only command-line boundary for PhantomStamp.

`BenchmarkWatermarkService` calls the production `WatermarkAlgorithmCore` and the same DCT, DFT,
FEC, alignment, and voting extensions used by the iOS app. It intentionally does not compile or
call the production `WatermarkService`, SwiftData history, `UserSettingsStore`, notifications,
progress overlays, views, or view models.

Build the Mac Catalyst executable:

```sh
Batch/build.sh
```

The default output is `.build/phantomstamp-batch`. The process reads one JSON object per line on
standard input and writes one JSON response per line on standard output. Supported operations are
`capabilities`, `embed`, and `extract`. Images cross the boundary as lossless PNG files. Embed
requests must provide the exact `sync_template_512.bin` path; the runner does not fall back to an
app bundle or generate a replacement template.

The benchmark repository owns process lifetime, temporary transport files, parameter validation,
source and binary fingerprints, attacks, metrics, and reporting.
