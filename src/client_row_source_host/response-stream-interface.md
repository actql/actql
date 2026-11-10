# Original RowRun response stream accounting

`begin_row_run_response_attempt` and `extend_row_run_page_charge` are Common
RowRun accounting ports. The provider still owns physical I/O and the ordered
original response. These ports neither dispatch I/O nor admit source data.

- Responsibility: the existing RowRun owns its response borrow, attempt,
  outstanding page ticket and physical reservation. Begin spends the reserved
  attempt before I/O; extend charges another physically received byte chunk to
  that same ticket. Neither operation creates a second acquisition or owner.
- Inputs and outputs: begin accepts the original `RowRunResponseBorrow` and
  returns Unit or `RowHostIssue`. Extend accepts the original RowRun, outstanding
  `RowPageCharge` and received Bytes, returning Unit or the existing typed issue.
  The response owner retains chunk order and original whole-body correspondence.
- Identity: the ticket belongs to the exact RowAttempt and must be the stored
  outstanding, unconsumed ticket. The original acquisition/borrow and same
  Ledger reservation are unchanged; foreign or equal-looking handles cannot
  charge another run or replace its original ticket.
- Ownership: the same bound physical-cleanup observer remains responsible for
  the response, including a partial prefix and failed read. Extending a ticket
  transfers no body ownership and retains no new response buffer. The provider
  keeps all response/parse overlap within its already admitted declaration.
- Synchronization: begin rechecks the original borrow after Resource current.
  Extend rechecks the same Reading state and unconsumed ticket after its debit.
  A synchronous current callback may abort or close; spent work remains spent
  but the stale borrow/ticket cannot resume I/O or admission. Reservation attempt
  consumption is idempotent and there is only one outstanding page ticket.
- Failure: invalid state, missing cleanup binding, foreign/consumed ticket and
  original Resource limit failures retain their typed refusals. Page overflow
  charges actual received bytes before refusing. Checked subtraction precedes
  the cumulative byte addition, and no transfer ceiling is raised or replenished.
- Cancellation: cancellation keeps already received prefix bytes and the spent
  attempt. Logical abort/close consumes the ticket but cannot refund transfer or
  acknowledge physical retirement. Failed close retains the original cleanup
  debt until the same provider's observer confirms stop.
- Resources: begin uses `consume_reserved_attempt` on the existing Ledger and
  reservation, including zero-byte I/O. Extend uses `charge_transfer` for the
  actual chunk length before parsing. The final ticket's cumulative received
  byte count must still match the complete document at its existing admission
  entrance; counting a prefix is not permission to parse it as the whole body.
- Extension: trusted file, network or other provider readers may use these ports
  only with their existing original borrow, physical observation and funding.
  No policy/scope issuer, caller Boolean authority, retry mechanism, transport
  selection or Native CLI mock enablement follows from this interface.
- Verification: `row_stream_accounting_wbtest.mbt` covers original ticket reuse,
  foreign/consumed tickets, cumulative limits, prefix cancellation and zero-byte
  attempt cleanup. `row_stream_current_js_wbtest.mbt` covers synchronous original
  Resource-current closure after a debit. These are test references, not result
  receipts, physical I/O acceptance or a normal installed-profile success claim.


## Growable listing construction

An original installed listing starter may select response-capacity construction
while retaining its SAME supplementary report declaration and bound cleanup
observer. The default entrance retains its prior full declaration. This typed
constructor selection grants neither Source authorization nor another attempt.

The existing charged-response grow uses the listing sum, including report and
encoding overlap, for an actual listing acquisition. Other Query acquisitions
retain the ordinary provider sum. It preserves the original response ticket,
reservation and current/reentry fences, and holds the successful grown allowance
through final cleanup. The direct nonlisting workspace-return entrance still
excludes listing; an inert transport or logical page completion cannot return a
live listing report's backing.
