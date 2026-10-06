# Completed Native Runtime owner restoration

## Ownership handoff

`NativeRemoteRuntime.restore_completed` takes the exact original dispatch and
input binding, a trusted current authority/slot port and the physical
restoration port. It reads the existing Site journal and accepts only a typed
NativeSettled completion with exact managed evidence and saved file custody.
The installed checked-task registration and original budget remain mandatory.
Actual Site identity, generation and runtime revision are checked separately
from the trusted authority port.

Before physical restoration, the existing Runtime owner map retains the
original responsibility. The existing Site owner charges the original
retained-byte amount; the existing bundle Store reuses the original dispatch
holding ID. Retry cannot allocate another holding or invoke the executor.
New dispatch admission is refused while historical restoration remains
pending. Capacity failure attempts no physical restore. A close request during
that phase preserves the retry entry instead of permanently closing it.

The standard-host adapter supplies its generation/content-verified output to
Runtime. Runtime rechecks the saved subject, manifest, measurement, exact file
generation/content and Source observation. It retains a rejected adapter's
physical cleanup callback. It never issues another completion or start claim.
CompletedRuntimeReady permits the existing bounded output readers; the stored
trusted current port also guards later completion and new-reader admission.

## Cleanup and concurrent observation

An unavailable original output becomes a cleanup-only Runtime responsibility.
Its completion is not rewritten as failed or unknown execution. No reader or
new execution is admitted. Physical cleanup must confirm before the existing
Site holding is returned, then the existing bundle holding is released and the
common owner commits formal release. Failed cleanup retains capacity and the
same callback for retry.

Journal state is read again after physical restoration. A release transition
committed during I/O cannot be overwritten by a cached success projection.
An independent SQLite connection exposed that normal reconstruction refuses
refreshing a nonzero cached record. The explicit completed-cleanup observation
port accepts only higher nonterminal cleanup revisions with unchanged original
NativeSettled execution, evidence, material and authority. Normal reconstruction
remains strict; regressed, foreign, changed-material and terminal snapshots are
refused. The Native test uses separate connections and in-memory controls.
`confirm_remote_runtime_completed_cleanup_restoration` binds the original
request, subject, evidence and measurement, checks the current NativeSettled
record and reconstructed resource handles, and permits cleanup-only handoff.
It changes no durable state and itself confirms neither release nor readable
success. Terminal, quarantined, mismatched and incomplete records are refused.

## Evidence scope

Native-only blackbox tests reuse the output fixture with real files and reopened
SQLite. A signed bundle is admitted by the real bundle Store; a registered
executor counter stays zero throughout restoration, exact retry, material
failure, cleanup retry and concurrent release. Normal restoration returns the
independent bytes `[{"id":3}]`, charges one 10-byte holding and formally releases
it to zero. Foreign input/generation and missing current authority reach no
physical restoration callback. Capacity rejection and a rejected close can
retry without double accounting. Cleanup failure keeps 10 bytes until the same
callback succeeds; later retries do not repeat cleanup. A concurrent release
uses the current record and remains unreadable until formal cleanup completes.

The completion fixture is synthesized through the existing transition and
evidence owners. These tests do not prove the original Source execution, an
exclusive recreated resident holder, real authorization, consumer execution or
public Cloud acceptance. The cached JS manifest issuer is used only to sign a
diagnostic component; its digest is recorded by the local runner. It is not a
formal five-package or Native binary adoption.

## Remaining execution boundary

The resident holder must call this Runtime restoration under its actual
exclusive slot, reconstruct trusted current Run/authority/lifetime facts,
reconnect the original independent Transfer destination holding and consumer
borrow, and resume the consumer from the checked edge. Restoration pending
before physical custody is acquired still requires retaining the Runtime and
reconciling current authority; it grants no permission to discard obligations.

Creation/seal-before-journal-commit interruption, actual holder recreation,
generation-changing Site restart, public Cloud two-task execution and real
interruption acceptance remain open. The parent retained-consumer diagnostic
timeout is unresolved. No deployment, formal Cloud adoption, merge or old #88
Run resolution is included.
