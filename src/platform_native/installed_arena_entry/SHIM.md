# Original control callback shim

This is uncompiled private source, derived from actual regular C emission at
`a3123a056fcece67636a8332de13d1a75b13d396`, digest
`9a3bafc1b6d79b70c622d5f2f34685998d9427e7e7c3f02da472de027ceb063a`.
The eight callback signatures use opaque generated Host/Reply tags. There is no
struct/enum field inspection, fabricated Option layout, copied Ledger, pointer
wire or permission registry. The static callback table holds code references;
registration neither adopts a supplier nor creates Root/Run/VM authority.

The actual generated forwarding functions borrow their managed inputs. The
original accessor returns NULL for None and increments a present original.
An operation reply itself retains its original Host. The caller owns returned
Host/Reply/String references, keeps inputs alive across calls, and uses only
the pinned matching MoonBit runtime for reference drops. These observations
apply to this exact emitted callback set, not every MoonBit FFI convention.

`drop_reply` requires the caller to independently retain that same original
when the reply contains one. It compares opaque identity through the actual
typed accessor, drops its temporary ref, then drops only the reply data ref.
It does not close the arena. The private trusted caller must actually own its
retained Host reference; a copied pointer value is not ownership or a public
input. The later Python holder must hide pointers and reject copies/reentry.

`try_close_and_drop` calls the existing typed Host Close operation. A nonempty
pending output slot is rejected before the operation, so earlier cleanup
custody is not overwritten. Failure keeps the same Host slot and returns the
exact typed reply. Only observed Close/Ok permits data reference drops and
clearing the Host slot. It does not call the physical provider's close directly,
retry acquisition or treat disappearance as retirement. Existing Native Owner
rules continue to decide borrowed children, physical munmap and settlement.

Null/Unavailable shim results are private transport failures, not evidence of
unstarted I/O or Program invalidity. Prepare/Ok is still an unacquired intent.
Neither issue-family zero nor a code table creates VM/publish/read permission,
Store ACK, cancellation confirmation, a numerical profile or a Run outcome.

There is no loader constructor or automatic initialization. The recorded C
main performs runtime initialization and then code registration; a future
reviewed recipe must bind its exact initialization entry without substituting
the Source675 test driver. A repeated registration retains the first callback
set so existing cleanup remains callable. An incomplete first registration
remains unavailable. Only trusted matching component code can register; this
is not an API for supplied callback pointers.

The shim includes no capacity implementation and creates no physical TLS.
The selected component must link the original Bootstrap C provider exactly
once. Later Wasmtime imports that same provider. Its symbols, dependency and
install-name closure, runtime initialization and same original Python holder
remain to be validated under separately allocated bounded windows. This source
is not added as an automatic native stub and is not a link-ready installed
library or normal Python package. Initial control/loader/VM numerical domains
remain unadopted, not zero. Compiler/link/init/Engine/VM/worker/wheel/public E2E
for this shim are all zero.
