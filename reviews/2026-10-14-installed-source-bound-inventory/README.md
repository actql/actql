# Ordinary installed Source inventory binding

## Adopted boundary

Base: `50fe456697ce0612fc39dde8fcef236f01666831` (normal adoption
after `3d00b6cad973d7a071a0d7d1853920a7aac01beb`). The fixed `35b919c`
diagnostic, original artifacts, Unknown requests and databases remain unchanged.
The observed journal guard rejects an installed row target because the legacy
ordinary inventory admits only three connector-specific target shapes. It is
not a keyed acquisition, and changing its target into a builtin target is invalid.

Add a separate Host-private initial-0.1 form:
`actql-client-bound-source-inventory/0.1`. Its closed envelope contains
`version`, `environmentCid`, and exactly two `acquisitions`. Each acquisition
contains exactly `stage`, `input`, `task`, `checkedSource`, `readTuple`,
`physicalBinding`, and `installationBinding`. Ordinary coordinates retain
`stage = task = occurrence index` and `input = 0`. The original nine-field
checked Source and three-field read tuple remain unchanged. The physical target
is opaque nonempty JSON owned and rechecked by the installed connector, not by
another journal provider dispatcher. The closed installation binding contains
exactly `connectorId`, `connectorRegistration`, `connectorRevision`, `bindingCid`.
All identifiers are retained exactly; the binding CID uses its existing domain.

The new form uses existing value-preserving canonical JSON (`dataKeys: true`),
including physical target strings. The old ordinary form, its settings-canonical
wire and closed target checks are unchanged. Keyed inventory remains separate.
There is no catch-and-retry conversion between forms. An installed row adapter
issues its binding only for a preparation retained by its existing WeakMap
owner. The producer chooses the bound form when both acquisitions provide this
owner capability. A partially bound pair is rejected before definition admission.
Adapters without that capability retain the explicitly declared legacy form;
missing registration/revision is never filled with invented values.

Held bound requests use a distinct closed
`actql-remote-bound-source-submission/0.1` capture. Original descriptors and
installation bindings survive checkpoint persistence. Restore compares the
new preparation with the original captured bytes and refuses changed installation,
revision, target or checked Source. It never adds a binding to a legacy capture.
The dispatch owner passes this original binding to the installed row owner;
the owner verifies its preparation, original target, coordinates and installation
before authority/physical action and across authority awaits. Existing request
identity comparison and journal atomic admission are reused unchanged.

## Finite implementation and evidence

Edit boundaries: journal inventory validation; ordinary descriptor/capture
production; checkpoint capture/approval projection; dispatch occurrence binding;
installed row preparation/physical verification. No new Checker, Evaluator,
Source provider, Scope or authority. Installed table Sources already reuse the
row owner. Existing role, work, holding, cancellation and cleanup remain intact.

Independent cases cover two bound Sources, missing/extra/replaced fields,
noncanonical wire, unchanged legacy rejection, changed installation/revision/
binding/target, same-request original comparison, and retained restore. Expected
values come from declared synthetic materials, not product output. Pure shape
and descriptor controls need no compiler. Existing journal/row/checkpoint cases
need an explicitly qualified retained runtime; missing runtime is not a pass.
Host, package producer/consumer, Provider and Heavy execution are not allocated.

This main-based repair is independent of the unpublished test stack:
`#1996` (`6c38c67ab152abc20e7ab683fdb8296c64cc3498`) → `#1999`
(`a42431f6012d9220a6c56d4bad5b9e537dfa5107`). Neither owns these journal/producer
hunks. Their author heads remain fixed. Their public acceptance will consume the
repaired normal release separately; this PR does not claim that acceptance.
