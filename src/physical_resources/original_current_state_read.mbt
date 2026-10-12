///|
// A transient data projection of the actual parked census, not another Owner,
// generation, grant or restore descriptor. The installing original bootstrap
// funds this seven-scalar record and matching frames before the getter.
pub(all) struct OriginalCurrentStateReadBounds {
  max_reservations : Int
  max_holdings : Int
  max_delegations : Int
  reservations : Int
  holdings : Int
  delegations : Int
  reader_work : Int
} derive(Eq, Debug)

///|
pub(all) enum OriginalCurrentStateReadIssue {
  Original(OriginalReadIssue)
  Document(OriginalStateDocumentIssue)
} derive(Eq, Debug)

///|
// Actual ceilings and live counts come from the SAME existing census under
// its exact current fence. Packet fields and caller aggregates are not inputs.
// reader_work is the existing local 2+N+H+D count, not planning/Model work or
// physical bytes. This read-only projection changes no usage or spent serial.
pub fn[T] original_current_state_read_bounds(
  park : OriginalResourcePark[T],
  origin : T,
) -> Result[OriginalCurrentStateReadBounds, OriginalReadIssue] {
  if park.origin is Some(original) && !physical_equal(original, origin) {
    return Err(ForeignOrigin)
  }
  guard original_resource_park_current(park, origin) is Some(_) else {
    return Err(ChangedOriginalState)
  }
  let inventory = park.fence.unwrap().identity.ledger.original_inventory.unwrap()
  let n = inventory.reservations.length()
  let h = inventory.holdings.length()
  let d = inventory.delegations.length()
  if n > inventory.max_reservations ||
    h > inventory.max_holdings ||
    d > inventory.max_delegations ||
    n > 2147483645 ||
    h > 2147483645 - n ||
    d > 2147483645 - n - h {
    return Err(IncompleteInventory)
  }
  Ok({
    max_reservations: inventory.max_reservations,
    max_holdings: inventory.max_holdings,
    max_delegations: inventory.max_delegations,
    reservations: n,
    holdings: h,
    delegations: d,
    reader_work: 2 + n + h + d,
  })
}

///|
// Installing the generic data Reader uses original Owner ceilings, never a
// packet's self-reported maxima. Parsing/comparison still do not authenticate
// the Store, journal, current cut or permission to send. This adds no field to
// the existing Reader: its document/tree lifetime remains explicit data custody.
pub fn[T] start_original_current_state_document_read_for_park(
  park : OriginalResourcePark[T],
  origin : T,
  source : @decode.Cursor,
  max_work : Int,
  owned_tree_limits : @decode.Limits,
) -> Result[OriginalCurrentStateDocumentRead, OriginalCurrentStateReadIssue] {
  let bounds = match original_current_state_read_bounds(park, origin) {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  if max_work < bounds.reader_work {
    return Err(Document(WorkLimit))
  }
  let read = match
    start_original_current_state_document_read(
      source,
      bounds.max_reservations,
      bounds.max_holdings,
      bounds.max_delegations,
      max_work,
      owned_tree_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Document(issue))
  }
  let document = read.document.unwrap()
  if document.counts !=
    (bounds.reservations, bounds.holdings, bounds.delegations) {
    cancel_original_current_state_document_read(read)
    return Err(Document(InvalidRecord))
  }
  Ok(read)
}
