# Local Node runtime asset (development)

This artifact holds the installed MoonBit Node runtime bundles used by the
Local and DuckDB adapters. It has no application `connect` entry yet and is
not the standard embedded Local provider. `@actql/node` must not depend on
or advertise this artifact until the Host composition, native assets, and
ordinary Program acceptance are installed and tested from a clean package.

The bundles are built from the checked OSS source and checked for freshness.
Their package paths preserve the runtime URLs used by the installed Node
adapters. The lightweight `@actql/sdk` does not depend on this artifact.
