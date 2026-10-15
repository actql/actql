# Original live-child Root connection

Private ABI74 adds `actql_buffer_open_live`, `actql_buffer_report_live` and
`actql_buffer_stop_live`. This is separate from the retained scalar-open raw
diagnostic entry. The live entry receives no caller-supplied Ledger limits.

Before the first Host-import admission, the Wasm host retains the one original
`ImportedChildLedger` frame. After its one `take`, it retains the same Ledger
and two already funded VM/Host capacity tokens before opening the existing
buffer pool on that Ledger. Failed initialization cannot retry admission or
fall through to scalar open. The pool still reserves its own bounded transfer
allowance inside that same child Ledger; it does not reserve parent bytes.

The existing Resource Owner enforces lifecycle/current restrictions and local
limits. Report is an explicit flush of that Ledger's actual cumulative usage.
It belongs after the outer operation's Core mutations and before its successful
response, and at terminal cleanup boundaries, rather than on every byte read.
Lost report acknowledgement preserves the original immutable snapshot and
refuses automatic replay. Cleanup reporting remains distinct from logical stop.

Logical close stops new child work and closes the pool through the existing
Owner. It does not settle the two fixed capacity tokens or release the parent
ticket, read-use, domain, FD, Store or worker. Those require their original
separate physical acknowledgements. Initialization references remain resident
until Store destruction, including partial/error cases.

The Native wrapper projects `LiveOpen`/`LiveClosing` directly from the same
Resource Owner and original runtime record. It does not infer lifecycle from a
failed limits read or treat closing as physical retirement. The original Native
conformance adds five lifecycle counters to its retained21 cases; its runtime
identity remains a test `Ref`, not an actual VM/channel issuer.

The Python loader requires all six exact fixed imports and three new exports.
Its existing diagnostic constructor has no live parent supplier and returns
typed Unavailable for those imports after original Caller checks. This refusal
is deliberate: physical membership, an equal nonce, or a scalar capacity is
not live-child admission. The installed same-channel Native issuer and public
operation flush caller remain to be connected. This unit does not claim actual
VM, worker, installed wheel, public Local or normal numerical-profile acceptance.
