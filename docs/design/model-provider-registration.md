# Exclusive Model Provider registration

The existing ModelProvider Owner distinguishes a synchronous fixture callback
from an asynchronous installed physical Provider. The variants are exclusive:
async registration retains no dummy synchronous callback and has no synchronous
fallback. A physical preflight plan must match its registered variant before
Entry preparation or transport. Existing synchronous fixtures retain their
original callback semantics.

The private Node installation chooses async by `entryPersistence: 'async'` and
omits `invoke` entirely. It must supply physical preflight, finite quantity
capacity, original provider binding bodies and the trusted raw-capture selection.
Missing originals or an unavailable async runtime refuse during registration,
without provider I/O. Common separately checks the response profile, Task and
installation binding, durable Entry requirement and finite request/response
limits before adopting the original async physical plan. Registration does not
prove current authorization, raw-capture permission or resource funding.

The original Entry, final send gate, raw-response custody, response decoder,
attempt settlement and cleanup owners remain authoritative. The same registered
Provider cannot silently switch invocation kind during preflight. In particular,
async startup without its durable preflight and quantity envelope refuses before
acquiring Model input uses or constructing a Model Ledger. Unsupported Decision transport
continues to refuse; neither variant supplies fabricated generation settings.

This representation does not advertise normal numerical startup, an installable
public Provider package or live Model support. Host-specific layout and all
simultaneous holdings still require the original resource supplier. Public
execution and package acceptance remain separate from private registration.
