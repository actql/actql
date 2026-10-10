# Native control replay of original Effect Checkpoint reports

The resident control loop now examines one existing durable dispatch per pass
for a saved Effect review report. The original Site journal and common report
Owner supply the dispatch, bytes and typed receipt. Cursor and backoff maps are
disposable scheduling hints, not another queue or custody ledger.

Before sending, the controller checks current operator delegation and Site
generation. The existing client also fences against the journal's current
durable Site binding. Missing reports produce no send; malformed custody stays
pending. Saved Accepted/Refused replies are inspected without HTTP redelivery.
An HTTP or ACK-storage failure retains the same original report for a later
pass or process reconstruction. Receipt acceptance never releases resources,
approves the Effect, or starts execution.

The focused test exercises the actual command helper with physical SQLite,
libcurl and an authenticated HTTPS peer. It covers a missing report, foreign
operator scope, bounded retry, lost HTTP response, ACK-save failure, journal
reopen, unchanged dispatch revision and no repeated send after ACK. Its review
is authored protocol evidence; it does not prove Provider Preview or encrypted
continuation persistence. The HTTP campaign registers this case with its own
fresh peer and the existing nonzero-test guard. Ordinary Core runs without the
HTTP fixture do not establish this acceptance.

Parent is #1209, ultimately main after its dependencies integrate. No wire,
stored format, package version, identity or public API is changed. The genuine
capture/Provider Preview/paired Checkpoint creation call in the resident holder
is still unfinished. This replay connection therefore does not establish the
public SDK waiting/approval path, resumed Native Effect, final release or
Preview acceptance. Cloud receiver integration is tracked separately in Cloud
#238. Hosted CI remains stopped; no deployment or merge is included.
