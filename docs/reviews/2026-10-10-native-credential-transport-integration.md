# Native credential transport integration review

Reviewed PR #1246 source 1bbfd4fd2 and normally integrated main 2953cd783.
Executed integration source: `d544d50578636059e7a89be723ffe06fea50fbd6`.

The installed verb, path and finite body bound are checked before a durable
credential-use claim. Installation and callback byte snapshots prevent caller
mutation from widening the operation. Current Host authorization and durable
grant revocation/lifetime are checked before physical I/O. The same HTTPS
engine preserves certificate verification, disabled redirects, finite response
capacity, and refusal of caller-supplied Authorization with operation credentials.

The existing credential-use record prevents replay after successful, refused
and unknown transport outcomes. A rejected write retains exact response status
and bytes. HTTP success does not establish semantic Effect completion or bypass
the separate Effect Ledger/Approval Owner.

Independent integration test: 11/11 actual Native/OpenSSL/libcurl/SQLite cases
passed in `run-m5aR2E`. Physical receipt
`native-salesforce-target-OKg6bV/physical-receipt.json` contains three GETs,
exactly two accepted PATCH writes, and one raw 409 rejection. The lost response,
reopen and invalid-authority cases did not add writes. The signed Resolution
regression remains registered. Whitespace checks passed.

This is a credential transport component review, not complete Cloud Effect,
public SDK approval/restart/release, full Native Core, packed cohort, retained
history, deployment-binary or Preview acceptance. Hosted CI was not started.
