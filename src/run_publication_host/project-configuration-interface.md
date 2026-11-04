# Project declaration metadata boundary

- Responsibility: the existing Project configuration Owner admits locators and
  the original profile choice. Existing connection and model-task registry
  bridge getters keep their original admitted metadata semantics. Catalog-file
  intake retains bounded declaration
  DATA for the selected reader; it does not admit a Catalog, infer a row schema,
  select an execution scenario or grant authority. The Node and generated RelA
  bridges expose these same Common operations without another semantic Owner.
- Inputs and outputs: `mock.catalog` is an optional nonempty project-relative
  locator beside `mock.data` and `mock.answers`. The catalog document has the
  closed root `{connections}`. Each named object entry is returned as its exact
  original JSON span, in original connection order. The selected reader must
  still validate every entry's complete declaration and binding fields. Existing
  connection getters return the logical name, Connector locator and original
  entry span; model registry getters return their admitted task/provider
  locators without reading credentials or installing providers.
- Identity: configuration text and catalog entry text retain exact Unicode and
  numeric spelling. Entry spans and the containing document are distinct
  originals. Profile getters require the same nominal retained selection and
  expose mock locators only for the original `mock` choice. Equal reconstructed
  configuration, copied selections and changed overrides do not replace it.
- Ownership: Common retains immutable metadata and the profile's original
  configuration references. The installed Node profile retains its captured
  callbacks, receiver and runtime until its existing retirement. File custody,
  Catalog publication, currentness and installed Source ownership remain with
  the existing Host and declaration readers.
- Synchronization: intake, getters and bridge calls are synchronous and perform
  no I/O. The Node view checks the original Project, runtime and receiver before
  exposing locators. Retired or copied views cannot acknowledge another view's
  managed retirement.
- Failure: malformed JSON, duplicate keys at any depth, invalid Unicode,
  unknown root/configuration fields, non-object connection entries, invalid
  names and invalid locator values refuse. Missing locators and out-of-range
  indexes remain explicit absence. Failure never selects a default file, a
  scenario-specific supplier or a source-free replacement.
- Cancellation: these pure calls have no asynchronous child to cancel. Profile
  retirement only drops managed references; it does not acknowledge a physical
  file close, Run stop, resource release or cleanup completion.
- Resources: configuration and catalog intake use the existing metadata bounds
  of 65536 UTF-8 bytes, 4096 nodes and depth 16. Profile selection charges its
  explicit work bound before retaining an override. These intake bounds are
  not physical reservations; the Host must account retained text, entry spans,
  parsed structures and overlapping read/decode workspace separately.
- Extension: the additive catalog locator preserves old data/answer-only
  configuration acceptance and supplies no default when absent. Declaration
  readers reuse existing Relation, SourceView, Mapping and Content contracts.
  New semantics require their own admitted contract change, not a permissive
  metadata parser or a bridge-local compiler.
- Verification: configuration/profile whitebox cases cover absence, exact
  text, malformed locators, foreign/copy/retired selections and existing input
  bounds. Catalog cases independently cover exact nested spans, duplicate and
  malformed unused members, empty ranges and exact/over-limit intake. Actual
  Node profile cases cover original receiver/runtime and legacy configuration.
  Wasm metadata and Python locator cases cover their same retained projection
  and file custody. These references do not claim installed mock execution,
  physical funding, artifact freshness or unexecuted target acceptance.
