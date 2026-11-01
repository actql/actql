# Resident command initial control

The selected Resident producer binds the exact compiled source and the complete
private `initial_control_recipe.json` digest into its command entry. This is an
installation precondition, not a public SDK profile, a Request or a Run grant.
An ordinary compiler invocation without that selection refuses before copying
arguments or constructing the command parser. There is no system-library or
unscoped compiler fallback in this entry.

The command first captures its actual process, main thread, executable identity,
bounded original arguments and supported loader environment. Observation and
capture use fixed initial-control storage. The installer declares the finite
control envelope for this storage, the original runtime control objects and
bootstrap wrappers; it does not infer loader or VM funding from the arena.
Argument observation precedes copying, and copying independently rechecks its
bound before each read and write. The original is never reconstructed from a
parsed bundle, Site, identity string, serialized record or numeric CLI option.

The existing generic bootstrap reserves capacity before acquiring its mapping,
claims that same original once, and lends its backing through the original
in-process region, view, domain and scoped Read owners. The command retains
every partial carrier before inspecting its result. Only after the same Read
is entered may it construct the parser or continue into Store/controller work.
The child uses the existing Owner's actual remaining arena capacity after its
charged control allocation, rather than an unrelated smaller byte declaration.
The same physical domain supplies the Read ceiling. These bounds cover only
this command allocation domain;
they grant no independent process, FD, loader, Run, permission or publication
capacity. Existing child owners and their limits remain authoritative.

Normal command completion consumes managed failure diagnostics on stderr,
preserving stdout for existing progress records, and lets parser and
command aliases unwind inside that same Read. Cleanup then leaves and closes
the Read through the same domain Owner, closes the domain and view, settles the original region loan, closes
the region, returns the original backing borrow and closes the bootstrap.
Every confirmed stage is latched separately. An unconfirmed stage retains its
same carrier and prevents later retirement. Normal input/current refusal cannot
discard the original cleanup duty. A non-returning existing holder failure
continues to retain its original operation and backing.

Successful bootstrap retirement acknowledges only this command's selected
mapping and accounting. It is not a child process stop, Site release, Host close,
Run cancellation, durable COMMIT or whole-Run cleanup acknowledgment.

The domain Owner alone selects cleanup of its published `read_use`. A failed
preparation before publication has no fabricated reader to close; a failed
preparation after publication retains that same reader until actual retirement.
The command's successful entry latch is used only to leave its acknowledged
scope, and supplies no read, retirement or process-stop authority.
