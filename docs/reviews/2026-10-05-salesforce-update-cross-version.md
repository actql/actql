# Salesforce update: resuming state saved before the move to the installed row Effect

This record covers the move of Salesforce record updates onto the Host's provider-neutral installed row Effect. It shows that Runs captured by the previous factory keep their identities, approval, Ledger claims and recovery responsibility when the new code resumes them.

## What was compared

| Item | Value |
| --- | --- |
| Generating checkout (product code) | `97209febbff2162c0b9552ac8d325c2434219b16` (`main` before the move). Only test tooling was added: `adapters/connectors/salesforce/test/cross-version/` and the test org's options. `git status` showed no product path changed. |
| Resuming checkout | The commit that adds this record, on top of the move (`4574f2732`). |
| Standard runtime | `sha256:e41b450ed4138cee7d035a3ae6d3021f6ba3bcb9939d0f73462b919c88104ca5`, the built `connectors_builtin_node.js`. It is identical in both checkouts because the move changes no MoonBit. |
| Generation | `node adapters/connectors/salesforce/test/cross-version/generate-update-state.mjs <output>` in the generating checkout, with its own `npm ci --ignore-scripts`, DuckDB's Node package and MoonBit build. |
| Resume | `ACTQL_UPDATE_CROSS_VERSION_STATE=<output> node --test adapters/connectors/salesforce/test/cross-version/update-state.resume.test.mjs` |

How the state was made:
- Every phase was driven only through the public Client, real Host processes and the stateful local org.
- No journal or Store was edited.
- Each phase was archived with `tar` after its Host stopped, so the Store's hard links are kept. Every restored file must match the digest recorded at generation.

## Phases and results

| Phase | How it was produced | Expected and observed on resume |
| --- | --- | --- |
| Held for approval | Submitted; the Set was held; the Host stopped. | No send before approval. After the reviewer's approval, exactly one PATCH and `succeeded`. |
| Approval saved | As above, then approved by a separate Host that stopped. | Exactly one PATCH and `succeeded`. A further restart sends nothing more. |
| Unknown after the send started | One row. A child Host resumed the approved Set; the org held the PATCH open; the Host process was killed (`SIGKILL`). | After the dead Host's lease expired, `needs_reconciliation` naming `save`, with no PATCH. |
| Response saved | Two rows. Row 1 was applied and answered; the org held row 2's PATCH; the Host process was killed. | `needs_reconciliation` with no PATCH. Row 1's saved response stands and the org's records are unchanged. |
| Changed Site binding | Approval saved, then the Site profile's `siteKey` changed. | Refused before any send. |
| Altered Effect input | Approval saved, then the durable Effect input object altered. | `failed` with no send. |

All seven resume tests passed: the six above plus the runtime-identity check. Saved archive digests (SHA-256, first 16 hex digits):

| Phase | Files | Archive |
| --- | --- | --- |
| held-for-approval | 37 | `5d17d9ce5b834974` |
| approval-saved | 35 | `b4275455794e0fab` |
| unknown-after-send | 46 | `fa39570705eed69c` |
| response-saved | 46 | `b379f6e498775a74` |

## Why this is a one-time record, not a permanent test

The saved state can only be resumed under the conditions it was made in, so it is not committed.

- **Host root and principal.** A Host's authority scope and its Store authority are derived from its absolute root and its principal (the operating-system user). The state therefore resumes only at its original root, on the machine and as the user that generated it.
- **Standard runtime.** Salesforce's capability binds the standard runtime. The existing design deliberately refuses a Run captured by another runtime (`…InstallationChanged`). Once `main` changes the MoonBit runtime, state saved by `97209febb` is refused by design.

What is committed instead:
- **Generator and resume test.** Running both again repeats this comparison.
- **Default behaviour.** The resume test skips unless it is given generated state.
- **Phase timing.** The killed-phase resumes wait for the dead Host's Checkpoint lease (10 s) before the next Host continues the Run.
