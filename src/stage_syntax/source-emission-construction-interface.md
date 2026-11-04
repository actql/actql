# Admitted Source traversal construction

- Responsibility: Decode owns the existing shallow value-view constructor;
  Stage owns the existing admitted-source emitter traversal. The quantities
  describe those implementations without introducing a second encoder.
- Inputs and outputs: nonnegative array/object widths produce shallow-view
  collection units; positive node counts produce emitter traversal units.
  Invalid counts refuse. Neither operation reads or admits a value.
- Identity: quantities do not identify a Cursor, Source, Writer or Program.
  Callers retain their original immutable backing and normal identity checks.
- Ownership: Decode counts the detached array and its child Cursors, the
  existing object Map/view, closure and ValueView carriers. Branch envelopes
  are co-counted. Stage counts Emit/ArrayNext/ObjectNext and the pending stack,
  then composes Decode's shared view and child/field accessor inventories.
  Strings and indexed tree backing are borrowed and not duplicated here.
- Synchronization: only one shallow view is evaluated at a time. Pending
  emitter work and its Cursors coexist with that view. An enclosing caller
  separately retains the original Source and Writer for the whole traversal.
- Failure: these constructor descriptions do not guarantee successful output.
  Existing Writer capacity/depth failures and closed-writer behavior remain.
  Failed prefixes cannot mutate the original admitted Source.
- Cancellation: no reservation, cleanup acknowledgement or cancellation owner
  is created. Synchronous return does not assert physical memory release.
- Resources: all Map/Array growth and representation units come from the
  original shared collection owners. Byte pricing and preconstruction funding
  belong to the caller's existing preparation owner. The described traversal
  excludes Writer text/control, Source/index backing and quotation frames.
- Extension: changing the underlying view or emitter must update the same
  owner inventory and its callers. No semantic checker, policy or executable
  authority follows from this DATA. New lowerer traversal behavior requires
  a separate review of its retained-copy lifetime composition.
- Verification: an independent expanded shallow-view vector checks concrete
  families, and actual views prove detached arrays cannot mutate the original.
  Dense and deep emission tests compare full exact output, refused prefixes,
  node geometry and continued readability of the original Source. Lowerer
  tests separately exercise full-prefix/member/demand-copy overlap.
