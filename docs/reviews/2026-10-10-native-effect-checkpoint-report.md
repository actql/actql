# Native Effect review reporting boundary

The retained consumer keeps its original admitted dispatch inside the existing
Native computation Owner. Its paired Checkpoint custody can now issue an exact
remote review report after reconfirming the original capture, Provider Preview,
continuation/Checkpoint Store readback and live retained-input borrow. The report
contains the canonical Checkpoint wire and original dispatch CID. Private
continuation bytes and values remain in the encrypted Site Store.

The common parser checks the canonical report, original dispatch, Run Definition
and Commit/EffectSet review shape. Receiving a report is not a proof of remote
persistence or current authorization. The receiving Cloud Run Owner must still
validate the exact original Run/unit and checked consumer, current Site generation,
authority and custody before committing waiting. A typed ACK binds the original
report CID, Checkpoint CID and dispatch CID. Accepted can only be emitted after
the corresponding waiting commit; it does not approve an Effect or retire custody.

Partial persistence retains the same Native custody and reservations and cannot
issue a report. Store reopening confirms the original pair and produces identical
report bytes. Retired custody cannot report. This reuses the existing physical
Store, borrow and Ledger; no new execution state machine or cleanup ledger exists.

## Integration sequence and limits

This change depends on the original Native evidence/custody and Run binding chain
(#1201, #1202, #1204), with main as the final merge destination. It supplies the
Native report issuer and portable wire admission/ACK. It does not yet install the
report in the resident CLI, retain its receipt in the Site journal, send it over
the authenticated observations route, or connect the Cloud Run waiting commit.
Those are the next connection boundary, using the existing Site journal and
Cloud Run Owner (#237). Formal package/binary adoption follows main integration.

No Host restart, public SDK approval/resume, physical Effect application, Result
publication/release or Preview acceptance is claimed by this component change.
The Native fixture uses real capture, Provider Preview, SQLite and crypto while
keeping the live Ledger; Store reopen is not Host restart.
