# Distribution and Connector integration

Historical integration record: the fixed-input gaps and validation below are
not the current product checklist. Later public acquisition, Effect and
Frontend evidence is indexed in the
[current implementation map](current-product-status.md). No original result
or fixed input is changed by that supersession.

## Fixed inputs and ownership

- Distribution: `7dd5df6e6e69ac0593673083cfae4c1e30192624`.
- Connector: `846de335041efe07e46cf0dc727887de992e2334`.
- Common ancestor: `826fc49188cc184f5a9bedcfcd2b49ad6ae3e658`.
- Integration branch: `integration/distribution-connector`.
- Both original worktrees, branches, and uncommitted changes are preserved.
- The separate compiler extraction worktree is parked and is not an input.

Distribution owns shared compiler, Executable Plan, Bound Invocation Template,
and public Client contracts. Connector owns Effect application, provider
execution, and provider-specific Effect evidence. Shared logical request scope
uses one opaque owner; the Client CID accessor delegates to that owner.
Common Stage lowering retains the original checked Program, including Effects.
It does not strip Effects or run the Effect-free checker again.

## Merge decisions

The branches include shared changes with different commit identities. Exact
shared file content from both histories supplied three-way merge bases.
Declaration-level merges retained independent tests and operations. Final
source checks and regressions remain authoritative; automatic text merges
alone are not evidence of semantic correctness.

- Preserve Distribution's prepared-sequence reuse when using Connector's
  shared checked-stage lowering and physical task selection.
- Retain Connector's exact Effect source task/owner binding across split
  Stages and shared Result holding lifecycle.
- Preserve the standard Local provider entry and Distribution cancellation
  intent/physical-stop separation.
- Use the current row-bound Effect receipt schemas and remove obsolete
  aggregate receipt prose. Rebuild pins and protocol validators from source.
- Keep independently named tests for the installed Local kernel and shared
  Effect/publication borrows.
- Generate the RelA bridge with its declared DuckDB acquisition dependency;
  it rejects SGA selection and has no SGA provider registration.
- Remove superseded Salesforce acquisition and adapter copies; their current
  owners live in the Connector Host and connector-specific adapter tree.
- The Salesforce gate explicitly builds the Checkpoint runtime it imports,
  so it does not depend on artifacts left by another gate.

## Preexisting product connection gaps

These gaps existed at the fixed inputs and are not successful integration
acceptance claims:

1. Packed standard Local public submission is source-free. Packed acquisition
   tests exercise real input and compute through an internal Host boundary;
   they do not yet establish public Client acquisition-to-publication. The
   DuckDB Source Evidence issuer work remains in Distribution's preserved WIP.
2. The original Effectful checked owner is retained and can execute through
   the installed Host. Formal compiler Plan/Template issuance from that owner
   is not yet exposed. Existing Effect tests explicitly supply test evidence;
   they do not count as a completed compiler issuer.
3. Public Effect submit and Checkpoint resolution/resume still require the
   common owners to be connected through ingress. Connector owns physical
   apply; Distribution owns that public connection.

The integration does not authorize merging main, publishing packages, or
Cloud deployment. A common development base and merge-ready release status
remain separate decisions. Same-SHA hosted Linux CI must be recorded from
an actual run; local macOS checks are not Linux CI evidence.

## Validation scope

The packed Node/browser test installs actual tarballs in a clean directory
and exercises public Values Local/HTTP submission, Result reading, attach,
request lookup, and cancellation/restart. The packed Local assets test also
uses real acquired input through the internal Host boundary. Those tests
prove different scopes and must not be conflated.

The Salesforce integration gate uses local HTTPS provider responses, SQLite
journals, and real shared MoonBit owners. It covers multi-member/row execution,
uncertain outcomes without resend, response recovery, Store publication and
retirement. It is not a live Salesforce organization test.

Initial integration failures were resolved by carrying the prepared-sequence
argument through shared lowering, restoring moved dependencies/helpers,
including the mandatory Invocation Bindings CID in test-only evidence,
building the Checkpoint runtime for its independent gate, removing superseded
Salesforce copies, and regenerating canonical fixtures in generator order.
No native bundle per-dispatch rehash path was introduced. The Remote Site
bundle implementation is unchanged from the common ancestor.
