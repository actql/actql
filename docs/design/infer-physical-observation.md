# INFER physical diagnostic boundaries

The existing Model execution Owner retains the original durable Entry and
its issued one-shot gate across the `BeforeInvoke` diagnostic callback. That
callback is explicitly **unsent**. Cancellation, deadline, current dispatch
authority, egress and the original reservation are checked again after it.
Only then is the original gate consumed and the fixed invocation entered.
No diagnostic callback, await or request reconstruction occurs between final
consumption and invocation.

`InvokeStarted` reports that the installed invocation entry was crossed. It
does not prove network transmission, provider acceptance, response validity,
capture persistence or Run success. The synchronous interface delivers this
fact after the invocation returns; the subsequent return/failure/cancellation
fact describes that invocation's disposition only. An invocation that throws
or loses its response can leave the already retained durable Entry unresolved;
absence of a start diagnostic does not prove that no send happened. It grants
neither a new gate nor an automatic retry.

Diagnostic delivery timestamps cannot measure the synchronous invocation's
duration. The Node observation consumer therefore omits duration for these
facts. A conforming asynchronous physical adapter may separately measure its
actual boundaries; a missing measurement remains unknown, not zero. The
pre-gate diagnostic is not exported as a completed transport observation.

Both immediate and polled persistence use the same original final gate.
Saved acknowledgement custody is independent of current send permission.
Legacy non-durable calls also recheck their existing current authorities after
the diagnostic callback. No new Run, Ledger, approval or execution Owner is
introduced by these diagnostic boundaries.
