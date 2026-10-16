# Original native VM callback observation

The private installed-image path captures one `_OriginalVMObservation` after
`LocalCore` observes its selected 16 MiB VM span in the original physical
holding. The observation retains the same Core identity, nonce, Store context,
instance exports, Memory, holding, provider library, recipe, and generation.
It does not acquire, fund, reserve, adopt, or transfer another holding.

Every subsequent physical Core call checks this original again before guest
execution. The private callback check additionally requires a live selected
Wasmtime `Caller`, its original Store context and the same Memory backing.
A fresh wrapper for the same exported Memory is allowed; a copied nonce,
different Store/instance, foreign process, changed generation or Unknown
holding is refused. No nominal object or native pointer is serialized.

The observation adds no thread ownership rule. Existing Core locking serializes
Store use; the original provider scope enforces its own thread/TLS restrictions.
In particular, a Core's original physical work thread is not another Store.

For a genuine borrowed child holding, `_project_original_span` asks that same
provider to validate the original transferred holding and active physical scope,
then return the observed Memory's offset relative to its payload. The projection
contains original source/recipe/material, nonce, offset and length only; no native
pointer or Store object crosses the channel. The provider checks one live
allocation and does not join adjacent extents. Invalid or lost replies retain
the same borrow/holding; the Python adapter never retries an Unknown query.
Raw diagnostic holdings cannot supply this child projection. The private
installed channel must still bind it to its own original provisioning access;
neither a copy nor equal metadata supplies admission or cleanup authority.

Closing lifecycle remains observable for the original Owner's report/cleanup;
it does not permit new work. Store retirement immediately fences execution.
Failed Store or holding cleanup retains the same observation and original
cleanup carrier. Only successful Store-last and holding retirement breaks the
observation's references, without issuing a separate physical ACK.

This is an observation seam for the live-child port, not its admission supplier.
The parent must still bind the original provisioning ticket/read-use to the
actual original channel and child VM before the Common Owner admits its bounded
child Ledger. The scalar buffer-open path does not become live-child admission.
The fixed host imports and prepaid VM/Host capacity projection are a subsequent
connection. Outside-process/control/FD/Store funding remains independent.

The focused tests use handle, Caller and FFI doubles. They establish neither
actual Wasmtime/VM execution nor installed wheel/public Local acceptance.
The numerical profile remains unavailable; 100M fuel, 12 MiB transfer and
16 MiB VM limits are unchanged.
