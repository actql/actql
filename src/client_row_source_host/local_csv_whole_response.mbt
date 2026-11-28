///|
/// Codec failure versus the original RowRun's custody, capacity or admission.
pub(all) enum LocalCsvWholeResponseIssue {
  Csv(LocalCsvPageIssue)
  Row(RowHostIssue)
}

///|
priv enum LocalCsvWholeResponsePhase {
  BeforeRead
  ReadingFile(RowPageCharge)
  Settling(RowPageCharge, Int64?)
  Sealed
}

///|
/// One page for the existing cleanup-bound Whole read. The installed Project
/// owner supplies its exact selected table and declaration before opening the
/// original Root. This record grants no path, Source or file-read authority.
pub struct LocalCsvWholeResponse {
  priv borrow : RowRunResponseBorrow
  priv table : LocalCsvTable
  priv max_bytes : Int
  priv max_rows : Int
  priv max_page_bytes : Int
  priv mut phase : LocalCsvWholeResponsePhase
}

///|
/// The caller starts the original RowRun with this table's paid transport
/// quote. Check its effective geometry before the one physical read.
pub fn prepare_local_csv_whole_response(
  borrow : RowRunResponseBorrow,
  declaration : RowDeclaration,
  table : LocalCsvTable,
  quote : LocalCsvPageTransport,
  max_page_bytes : Int,
) -> Result[LocalCsvWholeResponse, LocalCsvWholeResponseIssue] {
  let (run, selected) = match row_run_response_original(borrow) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  guard selected is InputResponse(acquisition) &&
    row_input_acquisition_target_resource(acquisition) == table.view.resource &&
    !row_input_acquisition_is_listing(acquisition) else {
    return Err(Row(ForeignDeclaration))
  }
  match check_row_input_acquisition_declaration(acquisition, declaration) {
    Ok(_) => ()
    Err(issue) => return Err(Row(issue))
  }
  guard run.attempt.state is Reading(read) &&
    run.physical is Some(physical) &&
    run.page_charge is None &&
    read.pages == 0L &&
    row_input_read_current(run, read) else {
    return Err(Row(InvalidState))
  }
  guard max_page_bytes > 0 &&
    quote.transfer_bytes > 0L &&
    quote.transfer_bytes <= max_page_bytes.to_int64() &&
    quote.max_rows > 0L &&
    quote.max_rows <= 2147483647L &&
    quote.execution_bytes > 0L else {
    return Err(Csv(InvalidLocalCsvLimits))
  }
  guard physical.execution_scratch >= quote.execution_bytes &&
    max_page_bytes <= read.page_limits.max_bytes else {
    return Err(Row(Physical(InvalidLimits)))
  }
  Ok({
    borrow,
    table,
    max_bytes: quote.transfer_bytes.to_int(),
    max_rows: quote.max_rows.to_int(),
    max_page_bytes,
    phase: BeforeRead,
  })
}

///|
/// Mark the already funded physical attempt before opening the selected Root.
/// The existing RowRun page ticket excludes any other response or second read.
pub fn begin_local_csv_whole_response(
  response : LocalCsvWholeResponse,
) -> Result[Unit, LocalCsvWholeResponseIssue] {
  let (run, _) = match row_run_response_original(response.borrow) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  guard response.phase is BeforeRead &&
    run.attempt.state is Reading(read) &&
    run.physical is Some(physical) &&
    read.pages == 0L &&
    run.page_charge is None &&
    row_input_read_current(run, read) else {
    return Err(Row(InvalidState))
  }
  // Retain before the Ledger's current callback. A duplicate response cannot
  // enter while this same owner's debit is in progress or has failed.
  response.phase = Sealed
  let charge = { owner: run.attempt, received_bytes: 0L, consumed: false, }
  run.page_charge = Some(charge)
  match
    @resources.require_intact_transfer_reservation(
      physical.ledger,
      physical.reservation,
      response.max_bytes.to_int64(),
    ) {
    Err(issue) => {
      abort_row_run(run)
      return Err(Row(Physical(issue)))
    }
    Ok(_) => ()
  }
  match begin_row_run_response_attempt(response.borrow) {
    Err(issue) => {
      abort_row_run(run)
      return Err(Row(issue))
    }
    Ok(_) => ()
  }
  guard row_run_response_charge_current(response.borrow, charge) else {
    abort_row_run(run)
    return Err(Row(InvalidState))
  }
  response.phase = ReadingFile(charge)
  Ok(())
}

///|
/// Abort an entered physical read. An authenticated prefix counts as actual
/// transfer; absent observation retains its full uncertain envelope. Neither
/// case yields a page, a new physical attempt or a cleanup acknowledgement.
pub fn fail_local_csv_whole_response(
  response : LocalCsvWholeResponse,
  observed_bytes : Int64?,
) -> Result[Unit, LocalCsvWholeResponseIssue] {
  let (run, _) = match row_run_response_original(response.borrow) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  guard response.phase is ReadingFile(charge) &&
    row_run_response_charge_current(response.borrow, charge) &&
    valid_local_csv_observation(response, observed_bytes) else {
    return Err(Row(InvalidState))
  }
  match
    settle_local_csv_transfer(response, run, charge, observed_bytes, false) {
    Err(issue) => Err(issue)
    Ok(_) => {
      abort_row_run(run)
      Ok(())
    }
  }
}

///|
fn valid_local_csv_observation(
  response : LocalCsvWholeResponse,
  observed : Int64?,
) -> Bool {
  match observed {
    None => true
    Some(bytes) => bytes >= 0L && bytes <= response.max_bytes.to_int64()
  }
}

///|
// Settle the one actual transfer before decoding. The observation remains
// on this response if the original Ledger refuses or the host call unwinds.
fn settle_local_csv_transfer(
  response : LocalCsvWholeResponse,
  run : RowRun,
  charge : RowPageCharge,
  observed : Int64?,
  retiring : Bool,
) -> Result[Unit, LocalCsvWholeResponseIssue] {
  guard run.physical is Some(physical) &&
    run.page_charge is Some(held) &&
    physical_equal(held, charge) &&
    !charge.consumed else {
    return Err(Row(InvalidState))
  }
  response.phase = Settling(charge, observed)
  match
    @resources.settle_entered_transfer(
      physical.ledger,
      physical.reservation,
      response.max_bytes.to_int64(),
      observed,
    ) {
    Err(issue) => Err(Row(Physical(issue)))
    Ok(settled) => {
      if !settled && !retiring {
        return Err(Row(InvalidState))
      }
      response.phase = Sealed
      Ok(())
    }
  }
}

///|
/// Settle an abandoned response before retiring its original read. If a
/// response was observed, retain that same byte fact even after unwind.
pub fn retire_local_csv_whole_response(
  response : LocalCsvWholeResponse,
  observed_bytes : Int64?,
) -> Result[Unit, LocalCsvWholeResponseIssue] {
  let (charge, observed) = match response.phase {
    BeforeRead | Sealed => return Ok(())
    ReadingFile(charge) => {
      guard valid_local_csv_observation(response, observed_bytes) else {
        return Err(Row(InvalidState))
      }
      (charge, observed_bytes)
    }
    Settling(charge, original) => (charge, original)
  }
  let run = response.borrow.run
  match settle_local_csv_transfer(response, run, charge, observed, true) {
    Err(issue) => Err(issue)
    Ok(_) => {
      abort_row_run(run)
      Ok(())
    }
  }
}

///|
/// Charge the original raw body once, then consume that same ticket for the
/// checked Relation page. Failure seals this response, retaining RowRun and
/// physical cleanup on their original owners.
pub fn accept_local_csv_whole_response(
  response : LocalCsvWholeResponse,
  body : Bytes,
) -> Result[Int, LocalCsvWholeResponseIssue] {
  let (run, _) = match row_run_response_original(response.borrow) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  guard response.phase is ReadingFile(charge) &&
    row_run_response_charge_current(response.borrow, charge) &&
    run.attempt.state is Reading(read) &&
    read.pages == 0L &&
    row_input_read_current(run, read) else {
    return Err(Row(InvalidState))
  }
  let observed = body.length().to_int64()
  guard valid_local_csv_observation(response, Some(observed)) else {
    return Err(Csv(InvalidLocalCsvLimits))
  }
  match
    settle_local_csv_transfer(response, run, charge, Some(observed), false) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // This response reserved exactly one page; its settled raw bytes become
  // the charge for the typed page without another debit or provider attempt.
  guard row_run_response_charge_current(response.borrow, charge) &&
    row_input_read_current(run, read) else {
    return Err(Row(InvalidState))
  }
  charge.received_bytes = observed
  let table = response.table
  let page = match
    encode_local_csv_page(
      body,
      table.column_names,
      table.integer_columns,
      table.keys,
      response.max_bytes,
      response.max_bytes,
      response.max_rows,
      response.max_page_bytes,
    ) {
    Ok(value) => value
    Err(issue) => {
      abort_row_run(run)
      return Err(Csv(issue))
    }
  }
  accept_charged_row_run_page(run, charge, @utf8.encode(page)).map_err(issue => {
    Row(issue)
  })
}
