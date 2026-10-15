# Original live-channel private transport

`live_channel_shim.h` follows the actual regular C emitted from
`f62f257ce0335982ae017a4e7b13f200cc9e1b3a`, SHA256
`7d29660add49c69be0e428d31d267890459cefb115f7dbe411777d927bc5025e`.
The normal provider recipe force-includes it while compiling generated C,
checking all twelve callback types against the actual component. It links one
bootstrap provider and the existing runtime, rather than another allocator/TLS.

Managed inputs are borrowed. Returned replies and original Host/domain/channel
getters own references; a no-channel preparation refusal has a nullable channel.
The trusted foreign caller retains inputs and persistent empty output slots
before calling. Results are stored before transport return. Partial extraction
retains already-published aliases; it never retries capture or reconstructs an
original from scalar DATA. These references stay inside the same component and
are not Wire values.

State and six limits are copied only from their exact successful typed operation
and matching originals. They are observations, not fresh current permission.
Missing/refused facts leave output values unchanged. Reporting delegates the
complete cumulative usage to Core; the C shim does not compute allowances.

Retirement validates the exact original `Retire/Ok` before clearing all owning
slots and decrementing references. No-channel preparation refusals have a
separate data-only finish. Foreign references, overlapping slots, pending
operations and unrelated success cannot retire data. No finish performs a
process stop, descriptor close, Store cleanup, physical acknowledgement, domain
close or backing-loan return. Those remain independent original responsibilities.

`live_channel_conformance.c` is a disposable 64-page/24-page-domain diagnostic
using invalid pipes and the real generated callbacks. Its initializer is called
once; it starts no worker or VM. It checks partial custody and reference returns,
including the existing backing-borrow fence before allocation retirement. It is
not a complete pre-spawn supplier, numerical profile, Python worker or installed
product acceptance.
