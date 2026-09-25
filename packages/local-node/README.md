# Local Node Host artifact (development)

This artifact holds the installed MoonBit Node runtime bundles and the
reachable Host adapter graph used by Local and DuckDB execution. It has no
application `connect` entry yet and is not the standard embedded Local
provider. `@actql/node` must not depend on or advertise this artifact until
the Host composition and ordinary Program acceptance are installed and
tested from a clean package.

The bundles and adapters are built from checked OSS source and checked for
freshness. Their package paths preserve the runtime URLs used by the Node
adapters. The lightweight `@actql/sdk` does not depend on this artifact.
