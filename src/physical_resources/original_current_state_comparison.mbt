///|
// A bounded borrow of an existing parked Owner and decoded data, not another
// Owner, read/descriptor issuer, Store authenticator or restored Ledger.
// Its installing caller funds this four-field cursor and per-block temporary
// snapshots with the entire retained input tree before construction.
struct OriginalCurrentStateComparison[T] {
  mut park : OriginalResourcePark[T]?
  mut document : OriginalCurrentStateDocument?
  total : Int
  mut position : Int
}

///|
// The exact live cursor/park pairing, not another Owner or authority to
// restore/send. This read-only guard spends no work and changes no borrow.
pub fn[T] original_current_state_comparison_current(
  value : OriginalCurrentStateComparison[T],
  park : OriginalResourcePark[T],
) -> OriginalCurrentStateComparison[T]? {
  guard value.park is Some(original) &&
    physical_equal(original, park) &&
    value.document is Some(document) &&
    document.source is Some(_) &&
    park.origin is Some(origin) &&
    original_resource_park_current(park, origin) is Some(_) else {
    return None
  }
  Some(value)
}

///|
pub fn[T] start_original_current_state_comparison(
  park : OriginalResourcePark[T],
  origin : T,
  document : OriginalCurrentStateDocument,
  max_work : Int,
) -> Result[OriginalCurrentStateComparison[T], OriginalStateComparisonIssue] {
  guard original_resource_park_current(park, origin) is Some(_) &&
    document.source is Some(_) else {
    return Err(Original(ChangedOriginalState))
  }
  let inventory = park.fence.unwrap().identity.ledger.original_inventory.unwrap()
  let n = inventory.reservations.length()
  let h = inventory.holdings.length()
  let d = inventory.delegations.length()
  if n > 2147483645 || h > 2147483645 - n || d > 2147483645 - n - h {
    return Err(InvalidBounds)
  }
  // Bootstrap, each actual current record and final currentness. These local
  // comparison units are not a new grant or a conversion to Model work.
  let total = 2 + n + h + d
  if max_work < total {
    return Err(WorkLimit)
  }
  Ok({ park: Some(park), document: Some(document), total, position: 0, })
}

///|
fn[T] original_current_state_block_matches(
  park : OriginalResourcePark[T],
  document : OriginalCurrentStateDocument,
  position : Int,
) -> Result[Bool, OriginalReadIssue] {
  guard park.origin is Some(origin) &&
    original_resource_park_current(park, origin) is Some(_) &&
    document.source is Some(source) else {
    return Err(ChangedOriginalState)
  }
  let inventory = park.fence.unwrap().identity.ledger.original_inventory.unwrap()
  let ledger = inventory.identity.ledger
  let n = inventory.reservations.length()
  let h = inventory.holdings.length()
  let d = inventory.delegations.length()
  if document.state != original_ledger_snapshot(ledger) ||
    document.counts != (n, h, d) {
    return Ok(false)
  }
  let matched = (fn() -> Bool raise OriginalStateDocumentFailure {
    let header = document_at(source, 7)
    let phase = if park.previous is Some(ConsumerStopping(_)) {
      "stopping"
    } else {
      "parked"
    }
    if document_count(document_at(header, 0)) != inventory.max_reservations ||
      document_count(document_at(header, 1)) != inventory.max_holdings ||
      document_count(document_at(header, 2)) != inventory.max_delegations ||
      @decode.text(document_at(header, 6)) != Ok(phase) {
      return false
    }
    if position == 0 {
      document_reservation(document_at(source, 8)) ==
      original_reservation_snapshot(inventory.bootstrap.reservation)
    } else if position <= n {
      document_reservation(document_at(document_at(source, 9), position - 1)) ==
      original_reservation_snapshot(inventory.reservations[position - 1])
    } else if position <= n + h {
      let token = inventory.holdings[position - n - 1]
      let record = document_at(document_at(source, 10), position - n - 1)
      document_count(document_at(record, 0)) == token.serial &&
      document_int(document_at(record, 1)) == token.reservation_serial &&
      document_nonnegative(document_at(record, 2)) == token.bytes &&
      document_bool(document_at(record, 3)) == token.live
    } else if position <= n + h + d {
      let token = inventory.delegations[position - n - h - 1]
      let record = document_at(document_at(source, 11), position - n - h - 1)
      let observed = document_at(record, 2)
      document_count(document_at(record, 0)) == token.reservation.serial &&
      document_limits(document_at(record, 1)) == token.limits &&
      (
        document_count(document_at(observed, 0)),
        document_count(document_at(observed, 1)),
        document_count(document_at(observed, 2)),
        document_nonnegative(document_at(observed, 3)),
        document_nonnegative(document_at(observed, 4)),
        document_count(document_at(observed, 5)),
        document_count(document_at(observed, 6)),
        document_count(document_at(observed, 7)),
      ) ==
      original_delegation_snapshot(token)
    } else {
      true
    }
  })() catch {
    _ => return Err(IncompleteInventory)
  }
  Ok(matched)
}

///|
pub fn[T] cancel_original_current_state_comparison(
  value : OriginalCurrentStateComparison[T],
) -> Unit {
  value.park = None
  value.document = None
}

///|
pub fn[T] advance_original_current_state_comparison(
  value : OriginalCurrentStateComparison[T],
  quantum : Int,
) -> OriginalStateComparisonPoll {
  if quantum < 1 {
    return ComparisonFailed(InvalidQuantum, work=0)
  }
  guard value.park is Some(park) && value.document is Some(document) else {
    return ComparisonFailed(Terminal, work=0)
  }
  let mut work = 0
  while work < quantum && value.position < value.total {
    let matched = original_current_state_block_matches(
      park,
      document,
      value.position,
    )
    work += 1
    match matched {
      Err(issue) => {
        cancel_original_current_state_comparison(value)
        return ComparisonFailed(Original(issue), work~)
      }
      Ok(false) => {
        cancel_original_current_state_comparison(value)
        return ComparisonFailed(RecordMismatch, work~)
      }
      Ok(true) => value.position += 1
    }
  }
  if value.position == value.total {
    cancel_original_current_state_comparison(value)
    ComparisonComplete(work~)
  } else {
    ComparisonContinue(work~)
  }
}
