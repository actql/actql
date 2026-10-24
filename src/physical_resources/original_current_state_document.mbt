///|
// Data only: this borrows the ENTIRE admitted source tree, not a Ledger,
// restoration token, Store authenticator or Model-send permission.
struct OriginalCurrentStateDocument {
  mut source : @decode.Cursor?
  state : OriginalLedgerSnapshot
  counts : (Int, Int, Int)
}

///|
struct OriginalCurrentStateDocumentRead {
  mut document : OriginalCurrentStateDocument?
  total : Int
  mut position : Int
}

///|
pub enum OriginalCurrentStateDocumentPoll {
  CurrentDocumentContinue(work~ : Int)
  CurrentDocumentComplete(OriginalCurrentStateDocument, work~ : Int)
  CurrentDocumentFailed(OriginalStateDocumentIssue, work~ : Int)
}

///|
// Existing decimal/record grammar, with a SEPARATE current-cut entry. The
// initial reading-only API remains unchanged. These shape/work ceilings are
// not byte funding; its installing Owner funds admission/tree/control first.
pub fn start_original_current_state_document_read(
  source : @decode.Cursor,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  max_work : Int,
  owned_tree_limits : @decode.Limits,
) -> Result[OriginalCurrentStateDocumentRead, OriginalStateDocumentIssue] {
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
  let document = (fn() -> OriginalCurrentStateDocument raise OriginalStateDocumentFailure {
    let state = match @decode.text(document_at(document_at(source, 7), 6)) {
      Ok("parked") => document_header(source, bounds, phase="parked")
      Ok("stopping") => document_header(source, bounds, phase="stopping")
      _ => raise BadDocument
    }
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
  let total = 2 + n + h + d
  if max_work < total {
    return Err(WorkLimit)
  }
  Ok({ document: Some(document), total, position: 0, })
}

///|
pub fn retire_original_current_state_document(
  document : OriginalCurrentStateDocument,
) -> Unit {
  document.source = None
}

///|
pub fn cancel_original_current_state_document_read(
  read : OriginalCurrentStateDocumentRead,
) -> Unit {
  if read.document is Some(document) {
    retire_original_current_state_document(document)
  }
  read.document = None
}

///|
pub fn advance_original_current_state_document_read(
  read : OriginalCurrentStateDocumentRead,
  quantum : Int,
) -> OriginalCurrentStateDocumentPoll {
  if quantum < 1 {
    return CurrentDocumentFailed(InvalidQuantum, work=0)
  }
  guard read.document is Some(document) && document.source is Some(source) else {
    return CurrentDocumentFailed(Terminal, work=0)
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
        // Current census order is NOT an initial snapshot with an appended
        // read token. Validate every record, never privilege the last record.
        document_reservation(document_at(document_at(source, 9), step - 1))
        |> ignore
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
        for index in [0, 1, 2, 5, 6, 7] {
          document_count(document_at(observed, index)) |> ignore
        }
        for index in 3..<5 {
          document_nonnegative(document_at(observed, index)) |> ignore
        }
      }
    })() catch {
      _ => {
        cancel_original_current_state_document_read(read)
        return CurrentDocumentFailed(InvalidRecord, work=work + 1)
      }
    }
    read.position += 1
    work += 1
  }
  if read.position == read.total {
    read.document = None
    CurrentDocumentComplete(document, work~)
  } else {
    CurrentDocumentContinue(work~)
  }
}
