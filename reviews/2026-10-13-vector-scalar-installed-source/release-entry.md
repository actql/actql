# Vector scalar: development Harness versus normal release installation

Inspection baseline: main `d676dc5c85fbbcba23d85659777d2ccdf975c526`.
This follow-up depends on the verified observation collector/auditor in #1877.
It keeps the original 12 normal and 8 refusal fixtures unchanged.

| Qualification | Existing development Harness | Prepared normal release consumer |
| --- | --- | --- |
| Packages | `client-wire,sdk,run-host-core,local-node,node`, development versions | `client-wire,sdk,local-node,node`, selected `release/client-cohort.json` version |
| Producer | `packed-client-packages.mjs`, ordinary prepack, development manifest | `preparePackageRelease`, ordinary prepack followed by metadata/license-only release staging and verified release manifest |
| Installation | Existing tarball quickstart | Empty directory, private test registry serving exact frozen RC bytes, `npm install @actql/node@<selected-version>` resolving the four-package closure |
| Runtime | Installed package exports | The same official installed package exports; no checkout runtime, adapter overlay or extra fifth package |
| Qualification transfer | None to a release RC | Exact same clean source, unchanged package/source digest fences and independent fixture audit |

The fifth development package is `run-host-core`, not `provider-ai-sdk`.
Neither the Vector fixture nor the inspected Node Host adapter files import
`@actql/run-host-core`; the actual installed graph must still pass
`auditPackedPackages` before and after public execution. Export existence alone
does not establish a runnable Vector task.

## Existing public API path

The original fixture already uses `@actql/local-node/connector-installation` to
create the trusted RowSource and its authorization/credential Site, and
`@actql/local-node/runtime` to restore the checked full schema declaration.
It registers that Source through `createInstalledConnectorTable` and publishes
the original `vectors` alias via its explicit Source profile. These are exported
by the normal `local-node` payload, not imported from repository adapters.

Local connects through `@actql/node.connect` with the explicit installation's
`sourceProfilePath` and `connectorTable`. HTTPS uses the existing
`@actql/local-node/http-host` factory and the public Node Client. The same
`packed-vector-scalar-source.mjs` performs all original assertions. Its physical
JSON page is a Source transport, not another frontend JSON input. Text cases
require one acquisition each; JSON Values controls require zero. Existing
attach/resend/lookup/reread must retain the original Run without reacquisition.

The new release consumer delivers only eight test modules, preserving their
bytes and relative import closure, outside `node_modules`. It reuses the
existing transport worker custody/deadline/output owner and existing independent
auditor. It does not patch Program, schema, expected values, driver behavior or
the installed product. The child environment omits inherited ACTQL/Moon
configuration, Node loader hooks and checkout compiler paths. A retained scratch
directory preserves actual Run/Source/Result custody and complete or incomplete
receipts. No cleanup claim follows just from a missing shared lock.

## Prepared commands, not executed

After review, normal integration and a concrete shared-window allocation, use
one clean fixed Source for both steps; the exact original 300-second / TERM-five
bounds remain. `<fresh-RC>` must not be an old development/partial cohort.

```sh
node reviews/2026-10-13-vector-scalar-installed-source/prepared-release-public.mjs \
  --producer <full-clean-SHA> /private/tmp/<fresh-RC>
node reviews/2026-10-13-vector-scalar-installed-source/prepared-release-public.mjs \
  --consumer <same-full-clean-SHA> /private/tmp/<same-RC> /absolute/new-release-vector-receipt.json
```

The old five-package recipe remains separate preparation. A successful producer
is not an E2E. No four-package RC, registry install, Host task, Local/HTTPS Run or
new external E2E has been executed here. Normal public npm publication and
Hosted CI remain zero. Calendar and max/weighted runtime gaps remain separate.

## Executed limited checks

At clean `b91ae23f6dda57a9460dc8d2f7846d16514a48b1`, tree
`f8aeb7202e8c40e95929ab0ea639e15a93767349`, the release import-closure/syntax
controls and original synthetic auditor controls passed 6/6 in `run-5h3s4q`.
After the environment isolation change, clean
`6317a8baed03301bb74ab4357069f07c940ccf31`, tree
`d22086d3aa37aea4369cde5e7bbffd944d4e0f27`, passed the four affected controls
in `run-xudUJK`. Both used pinned Node 22.22.0 and the existing 60-second / TERM-
five nonHeavy guard. Owner 91738 and 93531, both groups and the own lock were
observed absent. Subsequent documentation is not new runtime test evidence.

```sh
node scripts/local-checks.mjs test node --timeout-seconds 60 --kill-grace-seconds 5 -- \
  scripts/release-vector-scalar-fixtures.test.mjs
```

The second selection executes closure, missing-supplier refusal, entry syntax
and inherited-loader/config isolation only. It does not execute npm, artifact
production, Source admission or public APIs. Raw receipts are retained under
the workspace `reviews/2026-10-13-b-vector-release-consumer-evidence` directory.
