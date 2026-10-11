# Original holder Catalog grant installation

This change adds the native installation/read entry used by a future holder
Review-policy callback. It does not install that callback in `run_holder`,
activate a CLI flag, or establish public Effect acceptance.

## Parent and existing Owners

The source uses main `1be54e6e47083d8df2b8ed1672ea1cc57cdf7639`, which
contains the original policy context (#1448), lazy write installation (#1449),
Catalog response custody (#1454), and read/save connection (#1459). All final
integration targets are main. The submitted parent heads remain unchanged.

`open_holder_effect_catalog_installation` requires a genuine
`HolderEffectOriginalPolicyContext`. Its original completed producer issues the
Invocation from saved original Source evidence; no Source query, reprepare or
future captured Invocation is assumed. The actual consumer dispatch supplies
Site, generation, runtime and attempt. Fixed operator files independently select
workspace, Provider principal, environment, Connector registration/revision and
resource origin. None of these expectations come from proposed Catalog bytes.

The existing signature Owner admits the grant before its projection is compared
with those expectations. The only accepted operation is
`salesforce:catalog:describe`. Source grants, Effect write grants and Reviewer
permission cannot satisfy it. Current original custody and the exact retained
configuration snapshot are checked before opening service handles and through
the existing credential authorization/read callbacks. Grant expiry and
revocation remain with the existing credential Owner.

## Configuration and responsibility

The root contains fixed bounded files (never chosen by a Program):
workspace-id, provider-principal, environment, effect-connector-registration,
effect-connector-revision, provider-origin, connection-revision,
credential-org-id, catalog-occurrence, catalog-resource, catalog-api-version,
catalog-use-id, credential-issuer, credential-key-id, credential-public-key,
catalog-grant-cid, catalog-grant, catalog-grant-signature, provider-token-path,
provider-ca-path and credential-db-path. The implementation specifies `.txt`,
`.pem` and `.json` names exactly. Secret contents must not be logged.

The installer borrows the existing HTTP client, SQLite credential journal and
credential resource service. Setup failure closes those same acquired handles;
a failed close retains them for retry. Installation performs no credential use
or Provider send.

`HolderEffectCatalogInstallation.observe` calls the existing named Catalog
read/save/readback entry with the exact original binding. The caller must retain
every returned raw response and pending Store custody. A failed/unknown use does
not authorize another read. Save retry uses the returned Store custody, without
service/grant/transport arguments. Closing service handles does not retire the
Catalog custody or release a task; those obligations remain separate.

## Validation and remaining connection

Three new scope groups cover exact original routing, each foreign independently
selected field, incomplete routes, and Source/write/Reviewer operation
substitution. They are compile-only in this native executable package. Matching
Native holder/caller type checking is selected; no native test executable,
cryptographic grant verification, HTTP call or Provider mutation is executed.

The installer, observe and close methods are not yet called from the production
Review callback and therefore produce unused-function warnings. The next change
must assemble the checked Mapping/retention policy, retain the installation and
read/save failure in the existing holder responsibility, and connect cleanup.
No helper/compile success is reported as actual Catalog I/O, public approval,
Result publication, recovery or formal release.
