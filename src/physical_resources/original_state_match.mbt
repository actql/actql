///|
// Fixed-record comparison on the existing read/codec, not a new Owner. The
// existing caller owns document/claim lifetime and must fund its existing
// census guard plus every compared record. funded_read_available scans the
// original census on each call: one compared block does not mean one total
// unit of work, nor does it cover the bootstrap/authentication workspace.
// No Store authentication, restored Ledger, token issuance or Model-send
// authority follows from a true result.
// Public adoption remains gated on the original authenticated Store/Run binding
// and complete overlapping read/control profile.
pub fn[T] original_state_document_block_matches(
  claim : FundedReadClaim[T],
  origin : T,
  document : OriginalStateDocument,
  position : Int,
) -> Result[Bool, OriginalReadIssue] {
  let descriptor = claim.descriptor
  let n = descriptor.reservations.length()
  let h = descriptor.holdings.length()
  let d = descriptor.delegations.length()
  if n > 2147483644 ||
    h > 2147483644 - n ||
    d > 2147483644 - n - h ||
    position < 0 ||
    position >= 2 + n + h + d {
    return Err(IncompleteInventory)
  }
  if !(claim.phase is Written) || !funded_read_available(claim, origin) {
    return Err(ChangedOriginalState)
  }
  guard document.source is Some(source) else {
    return Err(ChangedOriginalState)
  }
  if document.state != claim.admitted || document.counts != (n + 1, h, d) {
    return Ok(false)
  }
  let matched = (fn() -> Bool raise OriginalStateDocumentFailure {
    // Reader ceilings are supplied by its caller. A well-formed body can use
    // different census ceilings while retaining identical records and usage.
    // Compare to this live original Owner, not merely those parsing ceilings.
    guard descriptor.ledger.original_inventory is Some(inventory) else {
      raise BadDocument
    }
    let saved_inventory = document_at(source, 7)
    if document_count(document_at(saved_inventory, 0)) !=
      inventory.max_reservations ||
      document_count(document_at(saved_inventory, 1)) != inventory.max_holdings ||
      document_count(document_at(saved_inventory, 2)) !=
      inventory.max_delegations {
      return false
    }
    if position == 0 {
      document_reservation(document_at(source, 8)) == descriptor.bootstrap_state
    } else if position <= n + 1 {
      let actual = document_reservation(
        document_at(document_at(source, 9), position - 1),
      )
      let expected = if position == n + 1 {
        claim.read_state
      } else {
        descriptor.reservations[position - 1].1
      }
      actual == expected
    } else if position <= n + 1 + h {
      let index = position - n - 2
      let record = document_at(document_at(source, 10), index)
      let (token, live) = descriptor.holdings[index]
      document_count(document_at(record, 0)) == token.serial &&
      document_int(document_at(record, 1)) == token.reservation_serial &&
      document_nonnegative(document_at(record, 2)) == token.bytes &&
      document_bool(document_at(record, 3)) == live
    } else {
      let index = position - n - h - 2
      let record = document_at(document_at(source, 11), index)
      let (token, expected) = descriptor.delegations[index]
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
      expected
    }
  })() catch {
    _ => return Err(IncompleteInventory)
  }
  Ok(matched)
}
