# Native Effect current fence at the Credential send boundary

The Credential Resource Owner authorizes a credential use independently from
Effect approval and the original holder's execution fence. An Effect caller
checking its fence only before entering the resource Owner would miss a
revocation performed by the installed Host authorization callback or final
trusted clock observation.

## Connection

`call_native_credential_resource_guarded_request_at_path` uses the same checked
operation, request snapshot, durable use claim and physical HTTPS driver as the
existing request API. Its required installed caller guard runs after claim
authorization, before grant consumption, and again after send authorization
and the final trusted clock observation. Durable credential revocation is read
after that final guard; no authorization or clock callback follows it.

A failed pre-claim guard consumes no use. A failed final guard saves the existing
Credential Owner's technical failure and sends nothing. That technical record
is not an Effect outcome or cleanup proof, and does not authorize replay of an
already claimed Effect row. A callback's journal failure remains an error with
its existing claimed custody. The physical driver still checks its actual
deadline after resolving the configured secret file.

Existing credential-only readers and request callers retain their existing
entry points. This does not add a Ledger, approval issuer, permission fallback,
scheduler, delivery retry, or semantic Effect terminal transition.

## Focused evidence

The pre-integration working tree at source `716a07cc0c56404724afbeb1402f88638b117d02`
plus the recorded patch passed 15 actual Native tests with the existing local
HTTPS server, SQLite databases and signed credential fixture. Evidence:

`_build/effect-guarded-write-1791610324408/receipt.json`

The physical receipt checks two accepted write requests and one separately
classified Provider refusal, unchanged from the earlier transport selection.
The new denied calls add no physical requests. Tests cover:

- a false initial guard, repeated without creating a use record;
- Host send authorization revoking the independent execution fence;
- the final trusted clock revoking that fence;
- the final guard revoking the credential itself;
- a successful guarded write, plus the existing lost response and reconstruction
  refusal tests.

Native caller compilation, portable JS compilation, harness syntax, generated
interfaces and whitespace checks passed. Compilation is not caller execution.
The guard-clock test is physical-fixture-only; this harness supplies its endpoint
and executes its clock and guard count assertions. Unrelated Core selections
without that endpoint do not claim this physical coverage.

## Remaining Resident Effect work

The public original-Run approval, current independent reviewer authorization,
Cloud resume fence, common Effect dispatch claim, saved raw response, admitted
row outcome receipt, terminal Ledger transition and formal release still need
one original-holder integration. These transport tests supply no signed Effect
approval, Cloud waiting commit, current resume claim, actual Source/Compute
Run, formal package cohort, deployment or Preview acceptance.

The work continues under Cloud #138. Hosted CI remains stopped; this preparation
is submitted as Draft and no merge or deployment is performed by F.
