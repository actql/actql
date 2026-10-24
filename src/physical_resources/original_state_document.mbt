///|
// Private codec data, NOT an authenticated original-state descriptor. This
// document has no Ledger, reservation, restore, handoff or send authority.
// The caller funds source admission, the borrowed tree and this control before
// starting; bounds must come from its original owner, never the document.
struct OriginalStateDocument {
  mut source : @decode.Cursor?
  state : OriginalLedgerSnapshot
  counts : (Int, Int, Int)
}

///|
struct OriginalStateDocumentRead {
  mut document : OriginalStateDocument?
  total : Int
  mut position : Int
}

///|
pub(all) enum OriginalStateDocumentIssue {
  InvalidBounds
  InvalidQuantum
  WorkLimit
  InvalidRecord
  Terminal
} derive(Eq, Debug)

///|
pub enum OriginalStateDocumentPoll {
  DocumentContinue(work~ : Int)
  DocumentComplete(OriginalStateDocument, work~ : Int)
  DocumentFailed(OriginalStateDocumentIssue, work~ : Int)
}

///|
priv suberror OriginalStateDocumentFailure {
  BadDocument
}

///|
fn document_array(
  c : @decode.Cursor,
  count : Int,
) -> Unit raise OriginalStateDocumentFailure {
  if @decode.array_length(c) != Some(count) {
    raise BadDocument
  }
}

///|
fn document_at(
  c : @decode.Cursor,
  index : Int,
) -> @decode.Cursor raise OriginalStateDocumentFailure {
  match @decode.element_at(c, index) {
    Some(value) => value
    None => raise BadDocument
  }
}

///|
fn document_long(
  c : @decode.Cursor,
) -> Int64 raise OriginalStateDocumentFailure {
  let text = @decode.text(c).unwrap_or("")
  let value = match @decode.decimal_int64(c) {
    Ok(value) => value
    Err(_) => raise BadDocument
  }
  // Reject noncanonical signs, whitespace, leading zeroes and negative zero.
  // Parsing a JSON number or using Double would lose large original usage.
  if text != value.to_string() {
    raise BadDocument
  }
  value
}

///|
fn document_nonnegative(
  c : @decode.Cursor,
) -> Int64 raise OriginalStateDocumentFailure {
  let value = document_long(c)
  if value < 0L {
    raise BadDocument
  }
  value
}

///|
fn document_int(c : @decode.Cursor) -> Int raise OriginalStateDocumentFailure {
  let value = document_long(c)
  if value < -2147483648L || value > 2147483647L {
    raise BadDocument
  }
  value.to_int()
}

///|
fn document_count(c : @decode.Cursor) -> Int raise OriginalStateDocumentFailure {
  let value = document_int(c)
  if value < 0 {
    raise BadDocument
  }
  value
}

///|
fn document_bool(c : @decode.Cursor) -> Bool raise OriginalStateDocumentFailure {
  match @decode.boolean(c) {
    Ok(value) => value
    Err(_) => raise BadDocument
  }
}

///|
fn document_optional_int(
  c : @decode.Cursor,
) -> Int? raise OriginalStateDocumentFailure {
  if @decode.is_null(c) {
    None
  } else {
    Some(document_int(c))
  }
}

///|
fn document_quantities(
  c : @decode.Cursor,
) -> QuantityAmounts raise OriginalStateDocumentFailure {
  document_array(c, 3)
  {
    tokens: document_nonnegative(document_at(c, 0)),
    cost_units: document_nonnegative(document_at(c, 1)),
    duration_ms: document_nonnegative(document_at(c, 2)),
  }
}

///|
fn document_optional_quantities(
  c : @decode.Cursor,
) -> QuantityAmounts? raise OriginalStateDocumentFailure {
  if @decode.is_null(c) {
    None
  } else {
    Some(document_quantities(c))
  }
}

///|
fn document_limits(
  c : @decode.Cursor,
) -> LedgerLimits raise OriginalStateDocumentFailure {
  document_array(c, 6)
  {
    planning_work: document_count(document_at(c, 0)),
    attempts: document_count(document_at(c, 1)),
    holdings: document_count(document_at(c, 2)),
    transfer_bytes: document_nonnegative(document_at(c, 3)),
    retained_bytes: document_nonnegative(document_at(c, 4)),
    execution_bytes: document_nonnegative(document_at(c, 5)),
  }
}

///|
fn document_usage(
  c : @decode.Cursor,
) -> LedgerUsage raise OriginalStateDocumentFailure {
  document_array(c, 13)
  {
    planning_work: document_count(document_at(c, 0)),
    attempts: document_count(document_at(c, 1)),
    holdings: document_count(document_at(c, 2)),
    transferred_bytes: document_nonnegative(document_at(c, 3)),
    uncertain_transfer_bytes: document_nonnegative(document_at(c, 4)),
    reserved_transfer_bytes: document_nonnegative(document_at(c, 5)),
    held_bytes: document_nonnegative(document_at(c, 6)),
    reserved_retention_bytes: document_nonnegative(document_at(c, 7)),
    reserved_execution_bytes: document_nonnegative(document_at(c, 8)),
    peak_retention_bytes: document_nonnegative(document_at(c, 9)),
    reserved_attempts: document_count(document_at(c, 10)),
    live_reservations: document_count(document_at(c, 11)),
    live_delegations: document_count(document_at(c, 12)),
  }
}

///|
fn document_reservation(
  c : @decode.Cursor,
) -> OriginalReservationSnapshot raise OriginalStateDocumentFailure {
  document_array(c, 12)
  let observed = document_at(c, 8)
  document_array(observed, 3)
  let completed = document_at(c, 9)
  let completed_output = if @decode.is_null(completed) {
    None
  } else {
    document_array(completed, 3)
    let holding = document_optional_int(document_at(completed, 0))
    if holding is Some(value) && value < 0 {
      raise BadDocument
    }
    Some(
      (
        holding,
        document_nonnegative(document_at(completed, 1)),
        document_nonnegative(document_at(completed, 2)),
      ),
    )
  }
  {
    serial: document_int(document_at(c, 0)),
    transfer: document_nonnegative(document_at(c, 1)),
    retention: document_nonnegative(document_at(c, 2)),
    execution: document_nonnegative(document_at(c, 3)),
    open: document_bool(document_at(c, 4)),
    attempt_reserved: document_bool(document_at(c, 10)),
    attempt_started: document_bool(document_at(c, 11)),
    cleanup_pending: document_bool(document_at(c, 5)),
    quantities: document_optional_quantities(document_at(c, 6)),
    uncertain_quantities: document_optional_quantities(document_at(c, 7)),
    observed_quantities: (
      document_bool(document_at(observed, 0)),
      document_bool(document_at(observed, 1)),
      document_bool(document_at(observed, 2)),
    ),
    completed_output,
  }
}

///|
fn document_header(
  c : @decode.Cursor,
  bounds : (Int, Int, Int),
  phase? : String = "reading",
) -> OriginalLedgerSnapshot raise OriginalStateDocumentFailure {
  document_array(c, 12)
  if @decode.text(document_at(c, 0)) != Ok("actql-original-ledger-state/0.1") {
    raise BadDocument
  }
  let delegated = document_at(c, 3)
  document_array(delegated, 3)
  let quantities = document_at(c, 5)
  document_array(quantities, 3)
  let inventory = document_at(c, 7)
  document_array(inventory, 8)
  if (
      document_count(document_at(inventory, 0)),
      document_count(document_at(inventory, 1)),
      document_count(document_at(inventory, 2)),
    ) !=
    bounds ||
    !document_bool(document_at(inventory, 3)) ||
    !document_bool(document_at(inventory, 4)) ||
    document_bool(document_at(inventory, 5)) ||
    @decode.text(document_at(inventory, 6)) != Ok(phase) ||
    !document_bool(document_at(inventory, 7)) {
    raise BadDocument
  }
  let issuance = document_at(c, 6)
  document_array(issuance, 3)
  let next = document_optional_int(document_at(issuance, 0))
  let next_attempt = document_optional_int(document_at(issuance, 1))
  let next_holding = document_optional_int(document_at(issuance, 2))
  if (next_attempt is Some(value) && value < 0) ||
    (next_holding is Some(value) && value < 0) {
    raise BadDocument
  }
  if next is Some(value) && value > -2 {
    raise BadDocument
  }
  {
    limits: document_limits(document_at(c, 1)),
    usage: document_usage(document_at(c, 2)),
    delegated: (
      document_count(document_at(delegated, 0)),
      document_count(document_at(delegated, 1)),
      document_count(document_at(delegated, 2)),
    ),
    quantity_limits: document_optional_quantities(document_at(c, 4)),
    quantities: {
      reserved: document_quantities(document_at(quantities, 0)),
      uncertain: document_quantities(document_at(quantities, 1)),
      consumed: document_quantities(document_at(quantities, 2)),
    },
    next_capacity_serial: next,
    next_attempt_serial: next_attempt,
    next_holding_serial: next_holding,
  }
}

///|
// Shape ceilings only. They are not byte coefficients, authentication or a
// capacity grant. Indexed access borrows the admitted tree: no elements() copy,
// detached token arrays or duplicate body map is made by this codec.
pub fn start_original_state_document_read(
  source : @decode.Cursor,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  max_work : Int,
) -> Result[OriginalStateDocumentRead, OriginalStateDocumentIssue] {
  if max_reservations < 1 || max_holdings < 0 || max_delegations < 0 {
    return Err(InvalidBounds)
  }
  let nodes = 85L +
    25L * max_reservations.to_int64() +
    5L * max_holdings.to_int64() +
    18L * max_delegations.to_int64()
  if nodes > 2147483647L {
    return Err(InvalidBounds)
  }
  start_original_state_document_read_in_owned_tree(
    source,
    max_reservations,
    max_holdings,
    max_delegations,
    max_work,
    {
      max_nodes: nodes.to_int(),
      max_depth: 6,
      max_string_bytes: 64,
      max_total_string_bytes: 2147483647,
    },
  )
}

///|
// Indexed child cursors retain the entire admitted tree and its original usage.
// A checked wrapping owner supplies that whole tree's structural envelope;
// it must not report only the child usage or allocate another admission tree.
// These limits are input shape limits, NOT physical-byte grants or authenticity.
// The resource record grammar/count/work checks are shared with the standalone
// reader. This candidate has no production Model caller or restoration power.
pub fn start_original_state_document_read_in_owned_tree(
  source : @decode.Cursor,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  max_work : Int,
  owned_tree_limits : @decode.Limits,
) -> Result[OriginalStateDocumentRead, OriginalStateDocumentIssue] {
  if max_reservations < 1 ||
    max_holdings < 0 ||
    max_delegations < 0 ||
    owned_tree_limits.max_nodes < 0 ||
    owned_tree_limits.max_depth < 0 ||
    owned_tree_limits.max_string_bytes < 0 ||
    owned_tree_limits.max_total_string_bytes < 0 {
    return Err(InvalidBounds)
  }
  let nodes = 85L +
    25L * max_reservations.to_int64() +
    5L * max_holdings.to_int64() +
    18L * max_delegations.to_int64()
  if nodes > 2147483647L {
    return Err(InvalidBounds)
  }
  let usage = @decode.admission_usage(source)
  if usage.nodes > owned_tree_limits.max_nodes ||
    usage.depth > owned_tree_limits.max_depth ||
    usage.largest_string_bytes > owned_tree_limits.max_string_bytes ||
    usage.total_string_bytes > owned_tree_limits.max_total_string_bytes {
    return Err(InvalidBounds)
  }
  let bounds = (max_reservations, max_holdings, max_delegations)
  let document = (fn() -> OriginalStateDocument raise OriginalStateDocumentFailure {
    let state = document_header(source, bounds)
    let n = @decode.array_length(document_at(source, 9)).unwrap_or(-1)
    let h = @decode.array_length(document_at(source, 10)).unwrap_or(-1)
    let d = @decode.array_length(document_at(source, 11)).unwrap_or(-1)
    if n < 1 ||
      n > max_reservations ||
      h < 0 ||
      h > max_holdings ||
      d < 0 ||
      d > max_delegations {
      raise BadDocument
    }
    { source: Some(source), state, counts: (n, h, d), }
  })() catch {
    _ => return Err(InvalidRecord)
  }
  let (n, h, d) = document.counts
  // Header/start and completion are fixed units; every record is another unit.
  let total = 2 + n + h + d
  if max_work < total {
    return Err(WorkLimit)
  }
  Ok({ document: Some(document), total, position: 0, })
}

///|
pub fn retire_original_state_document(document : OriginalStateDocument) -> Unit {
  document.source = None
}

///|
pub fn cancel_original_state_document_read(
  read : OriginalStateDocumentRead,
) -> Unit {
  if read.document is Some(document) {
    retire_original_state_document(document)
  }
  read.document = None
}

///|
pub fn advance_original_state_document_read(
  read : OriginalStateDocumentRead,
  quantum : Int,
) -> OriginalStateDocumentPoll {
  if quantum < 1 {
    return DocumentFailed(InvalidQuantum, work=0)
  }
  guard read.document is Some(document) && document.source is Some(source) else {
    return DocumentFailed(Terminal, work=0)
  }
  let (n, h, d) = document.counts
  let mut work = 0
  while work < quantum && read.position < read.total {
    (fn() -> Unit raise OriginalStateDocumentFailure {
      let step = read.position
      if step == 0 {
        let bootstrap = document_reservation(document_at(source, 8))
        if bootstrap.serial != -1 ||
          !bootstrap.open ||
          bootstrap.retention <= 0L ||
          bootstrap.execution <= 0L ||
          bootstrap.cleanup_pending ||
          bootstrap.transfer != 0L ||
          bootstrap.quantities is Some(_) ||
          bootstrap.uncertain_quantities is Some(_) ||
          bootstrap.completed_output is Some(_) ||
          bootstrap.observed_quantities != (false, false, false) {
          raise BadDocument
        }
      } else if step <= n {
        let record = document_reservation(
          document_at(document_at(source, 9), step - 1),
        )
        if step == n &&
          (
            record.serial >= -1 ||
            !record.open ||
            record.cleanup_pending ||
            record.retention <= 0L ||
            record.execution < 0L ||
            record.transfer != 0L ||
            record.quantities is Some(_) ||
            record.uncertain_quantities is Some(_) ||
            record.completed_output is Some(_) ||
            record.observed_quantities != (false, false, false)
          ) {
          raise BadDocument
        }
      } else if step <= n + h {
        let record = document_at(document_at(source, 10), step - n - 1)
        document_array(record, 4)
        document_count(document_at(record, 0)) |> ignore
        document_int(document_at(record, 1)) |> ignore
        document_nonnegative(document_at(record, 2)) |> ignore
        document_bool(document_at(record, 3)) |> ignore
      } else if step <= n + h + d {
        let record = document_at(document_at(source, 11), step - n - h - 1)
        document_array(record, 3)
        document_count(document_at(record, 0)) |> ignore
        document_limits(document_at(record, 1)) |> ignore
        let observed = document_at(record, 2)
        document_array(observed, 8)
        for index in 0..<3 {
          document_count(document_at(observed, index)) |> ignore
        }
        for index in 3..<5 {
          document_nonnegative(document_at(observed, index)) |> ignore
        }
      }
    })() catch {
      _ => {
        cancel_original_state_document_read(read)
        return DocumentFailed(InvalidRecord, work=work + 1)
      }
    }
    read.position += 1
    work += 1
  }
  if read.position == read.total {
    read.document = None
    DocumentComplete(document, work~)
  } else {
    DocumentContinue(work~)
  }
}

///|
pub fn original_state_document_usage(
  document : OriginalStateDocument,
) -> LedgerUsage? {
  if document.source is Some(_) {
    Some(document.state.usage)
  } else {
    None
  }
}

///|
pub fn original_state_document_quantities(
  document : OriginalStateDocument,
) -> QuantityUsage? {
  if document.source is Some(_) {
    Some(document.state.quantities)
  } else {
    None
  }
}

///|
pub fn original_state_document_capacity_cursor(
  document : OriginalStateDocument,
) -> Int?? {
  if document.source is Some(_) {
    Some(document.state.next_capacity_serial)
  } else {
    None
  }
}
