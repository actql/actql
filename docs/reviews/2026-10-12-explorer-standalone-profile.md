# Finite standalone Explorer distribution profile

This unit supplies the existing E1 Local distribution seam: one separately
installed `@actql/explorer`, built read-only SPA, bounded frozen assets and the
nonconflicting `actql-explorer` launcher. It does not complete the entire E1
Cloud route or Full Explorer design. The initial Node/SDK four-package cohort
and production dependencies are unchanged.

The explicit optional recipe `release/explorer-cohort.json` adds the shared UI
library and standalone entry after the existing four packages. It uses the
existing clean-HEAD normal-prepack flow, source receipt, original tarball
digests, metadata/license-only staging and public archive verification. Internal
dependencies and peers are rewritten to the exact cohort package version.
React/React DOM remain peers of the UI library; the standalone app supplies the
selected runtime and built CSS. No consumer build or development reference is
required. Third-party packages resolve through normal npm dependency metadata.

The public launcher API borrows an existing public Client. It opens no Host and
does not close that Client. The explicit Local owning API loads assets first,
calls the existing `@actql/node.open` once in its process, and closes that same
lease through its awaited close contract. The original Node Store lock, shared
lease, authority and recovery Owners remain authoritative. Startup refusal is
not a reason to open another Host or retry with another Store. Closing a browser
or Gateway cannot cancel/resume a Run or release a retained Result.

The asset loader reads only its own package-relative manifest, validates the
closed inventory, bytes and SHA-256, and refuses symlinks or duplicate/escaping
paths. Existing bounds stay 32 assets / 2 MiB; the Gateway copies admitted bytes
and retains exact loopback Host/Origin, one-use bootstrap, expiry, CSRF, current
Host authorization and stale-scope refusal. A terminal bootstrap is manually
entered into the page, never persisted or placed in query URLs. A new bootstrap
requires an explicit operator action; no automatic session renewal is added.

The SPA performs only existing public `plan`, `attach`/`inspect` and Result
`describe` reads. Static Plan keeps original occurrences, port roles, map and
plan identities; unavailable source origins are not inferred. Run views remain
non-atomic original Owner observations. Named Result output is metadata only.
Controls, Samples, Result payload, physical projections, Timeline and complete
Cloud navigation remain unavailable. Scope invalidation discards displayed
data; response errors never become invented computation facts.

Acceptance for this finite unit consists of normal one-entry installation into
an empty external consumer, real built HTML/JS/CSS, Host/token-free source-free
`SELECT 1`, static Plan/original ports, original Run and Result metadata, absent
unsupported capabilities, and closure while the borrowed Client and retained
Run remain usable. Component fixtures, TypeScript and HTTP delivery are
distinguished from interactive browser or Cloud acceptance. The original
comprehensive design remains in the workspace review bundle; it is not an
expanded release gate for this unit. Formal publication/deployment needs a
separate GO.
