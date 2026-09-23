# `@actql/node` development assembly

This package exposes the same `connect(options)` Client API as `@actql/sdk`.
Connected Local, Remote and Hybrid modes use the lightweight Client Host
transport. Embedded Local or local-owned Hybrid without an endpoint selects
the one fixed `@actql/local-node` provider slot. The package neither imports
that provider for connected modes nor downloads it at connection time.

The embedded Local provider is not yet built in this development artifact.
Selecting it raises `LocalProviderNotInstalled` before Run admission. A
standard release must include the actual provider as an installed dependency
and prove an ordinary Program through the same Client, Execution and Result
methods. This package is not that completed standard release.
