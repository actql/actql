///|
// A comparison cursor borrowing existing claim/document owners. It is not a
// Ledger, a Store authenticator, a restoration token or Model-send authority.
// The original caller funds this six-field control and every census scan
// before construction; field/record counts do not establish a byte grant.
struct OriginalStateComparison[T] {
  mut claim : FundedReadClaim[T]?
  mut origin : T?
  mut document : OriginalStateDocument?
  total : Int
  mut position : Int
  mut terminal : Bool
}

///|
pub(all) enum OriginalStateComparisonIssue {
  InvalidBounds
  InvalidQuantum
  WorkLimit
  Original(OriginalReadIssue)
  RecordMismatch
  Terminal
} derive(Eq, Debug)

///|
pub enum OriginalStateComparisonPoll {
  ComparisonContinue(work~ : Int)
  ComparisonComplete(work~ : Int)
  ComparisonFailed(OriginalStateComparisonIssue, work~ : Int)
}

///|
pub fn[T] start_original_state_comparison(
  claim : FundedReadClaim[T],
  origin : T,
  document : OriginalStateDocument,
  max_work : Int,
) -> Result[OriginalStateComparison[T], OriginalStateComparisonIssue] {
  let descriptor = claim.descriptor
  let n = descriptor.reservations.length()
  let h = descriptor.holdings.length()
  let d = descriptor.delegations.length()
  if n > 2147483644 || h > 2147483644 - n || d > 2147483644 - n - h {
    return Err(InvalidBounds)
  }
  // Bootstrap, every original token and the read token, then a final current
  // census check. These are local comparison steps, NOT Model KernelStep or
  // a claim that one complete census scan costs one planning-work unit.
  let total = 3 + n + h + d
  if max_work < total {
    return Err(WorkLimit)
  }
  if !funded_read_available(claim, origin) ||
    !(claim.phase is Written) ||
    document.source is None {
    return Err(Original(ChangedOriginalState))
  }
  Ok({
    claim: Some(claim),
    origin: Some(origin),
    document: Some(document),
    total,
    position: 0,
    terminal: false,
  })
}

///|
// Drop only this cursor's borrows. Neither the original document tree nor
// original read/Store reservations are retired by cancellation/comparison.
pub fn[T] cancel_original_state_comparison(
  value : OriginalStateComparison[T],
) -> Unit {
  value.claim = None
  value.origin = None
  value.document = None
  value.terminal = true
}

///|
pub fn[T] advance_original_state_comparison(
  value : OriginalStateComparison[T],
  quantum : Int,
) -> OriginalStateComparisonPoll {
  if quantum < 1 {
    return ComparisonFailed(InvalidQuantum, work=0)
  }
  guard !value.terminal &&
    value.claim is Some(claim) &&
    value.origin is Some(origin) &&
    value.document is Some(document) else {
    return ComparisonFailed(Terminal, work=0)
  }
  let mut work = 0
  while work < quantum && value.position < value.total {
    let matched = if value.position == value.total - 1 {
      if funded_read_available(claim, origin) && document.source is Some(_) {
        Ok(true)
      } else {
        Err(ChangedOriginalState)
      }
    } else {
      original_state_document_block_matches(
        claim,
        origin,
        document,
        value.position,
      )
    }
    work += 1
    match matched {
      Err(issue) => {
        cancel_original_state_comparison(value)
        return ComparisonFailed(Original(issue), work~)
      }
      Ok(false) => {
        cancel_original_state_comparison(value)
        return ComparisonFailed(RecordMismatch, work~)
      }
      Ok(true) => value.position += 1
    }
  }
  if value.position == value.total {
    cancel_original_state_comparison(value)
    ComparisonComplete(work~)
  } else {
    ComparisonContinue(work~)
  }
}
