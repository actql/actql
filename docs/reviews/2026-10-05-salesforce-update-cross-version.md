# Salesforce update: resuming state saved before the move to the installed row Effect

This record covers the move of Salesforce record updates onto the Host's provider-neutral installed row Effect. It shows that Runs captured by the previous factory keep their identities, approval, Ledger claims and recovery responsibility when the new code resumes them.

## How it runs

`npm run test:salesforce-cross-version` (`adapters/connectors/salesforce/test/cross-version/run-cross-version.mjs`) runs the whole comparison in one temporary root:

1. Check out the pinned previous version (`97209febbff2162c0b9552ac8d325c2434219b16`, `main` before the move) in a temporary worktree.
2. Add only this checkout's test tooling: the generator, its state module, its Host and Local children, and the test org. The run refuses if `git status` shows any product path changed there.
3. Install that checkout's own dependencies and build its own MoonBit runtime. Build this checkout's runtime as well.
4. Compare the two standard runtime bundles (`connectors_builtin_node.js`). If they differ, the run fails and asks for a re-pin: Salesforce's capability binds the runtime, and a Run captured by another runtime is refused by design.
5. Generate every phase with the previous version, then resume it with this checkout, as the same user, at the same absolute roots, on the same machine. A Host's authority scope and Store authority come from its root and principal, so these must match.
6. Remove the temporary worktree and root.

The acceptance fails if any step fails. `update-state.resume.test.mjs` run without generated state also fails rather than skips.

How the state is made:
- Every phase is driven only through the public Client, real Host processes, Embedded Local processes and the stateful local org.
- No journal or Store is edited.
- Each phase is archived with `tar` after its Host stops, which keeps the Store's hard links. Every restored file must match the digest recorded at generation.
- Resumes of killed phases wait for the dead Host's Checkpoint lease (10 s) before the next Host continues the Run.

## Phases and expectations

| Path | Phase | How it is produced | Expected on resume |
| --- | --- | --- | --- |
| HTTPS | Held for approval | Submitted; the Set is held; the Host stops. | No send before approval. After the reviewer's approval, exactly one write and `succeeded`. |
| HTTPS | Approval saved | As above, then approved by a separate Host that stops. | Exactly one write and `succeeded`. A further restart sends nothing more. |
| HTTPS | Unknown after the send started | One row. A child Host resumes the approved Set; the org holds the write open; the Host process is killed (`SIGKILL`). | `needs_reconciliation`, with no write. |
| HTTPS | Response saved | Two rows. Row 1 is applied and answered; the org holds row 2's write; the Host process is killed. | `needs_reconciliation` with no write. Row 1's saved response stands and the org's records are unchanged. |
| HTTPS | Changed Site binding | Approval saved, then the Site profile's `siteKey` is changed. | Refused before any send. |
| HTTPS | Altered Effect input | Approval saved, then the durable Effect input object is altered. | `failed` with no send. |
| HTTPS | Create and upsert: held, approval saved, unknown after send | As for update, with a create-only or upsert-only Set. | As for update; one `POST` or one external-key `PATCH`. |
| Local | Approval saved | Embedded Local child processes submit the update and approve it as the local owner. | Exactly one write and `succeeded`. |
| Local | Unknown after the send started | As above. Then an Embedded Local child resumes it; the org holds the write; the child is killed. | `needs_reconciliation`, with no write. |

Each path resumes only state that path captured. An Embedded Local Host attached to a Run that an HTTPS Host captured was observed to stay `resuming`. That cross-path case is not part of this acceptance and is not claimed.

## Results

See the pull request for the run at its final commit.
