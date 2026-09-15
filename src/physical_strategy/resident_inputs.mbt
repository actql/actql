///|
/// A complete ordered set of borrowers for one task and one environment.
/// Individual reads are not exposed, so claimed task leases cannot be returned
/// independently by callers. Equal table contents never establish ownership.
struct ResidentInputs {
  owner : StrategyOfferOwner
  task : Int
  environment : ResidentEnvironment
  compute : @duckdb.FixedCompute
  reads : Array[ResidentRead]
  mut claimed : Bool
  mut returned : Bool
}

///|
pub fn prepare_resident_inputs(
  run : CapturedDAG,
  env : ResidentEnvironment,
  task : Int,
  tables : Array[ResidentTable],
  compute : @duckdb.FixedCompute,
  max_entries : Int,
  max_name_bytes : Int,
  max_representation_bytes : Int,
  prepare_view : (Int, @duckdb.ResidentImport, @execution.ProducerRead, Int) -> Result[
    @duckdb_compute.DuckDBResidentRead,
    RunIssue,
  ],
) -> Result[ResidentInputs, RunIssue] {
  if next_captured_task(run) != Some(task) ||
    !resident_environment_available(run, env) {
    return Err(NotReady)
  }
  guard run.inputs.get(task) is Some(ports) &&
    tables.length() == ports.length() &&
    tables.length() == @duckdb.fixed_compute_import_count(compute) &&
    !tables.is_empty() else {
    return Err(ForeignCandidate)
  }
  let reads : Array[ResidentRead] = []
  let mut remaining = max_representation_bytes
  for port in 0..<tables.length() {
    let result = if !physical_equal(tables[port].environment, env) {
      Err(ForeignCandidate)
    } else {
      borrow_resident_table(
        run,
        tables[port],
        task,
        max_entries,
        max_name_bytes,
        fn(imported, input) { prepare_view(port, imported, input, remaining) },
        input_index=port,
      )
    }
    let read = match result {
      Ok(read) => read
      Err(issue) => {
        for read in reads {
          return_resident_read(read) |> ignore
        }
        return Err(issue)
      }
    }
    reads.push(read)
    guard @duckdb.fixed_compute_import(compute, port) is Some(imported) &&
      physical_equal(@duckdb.fixed_import_input(imported), read.input) else {
      for read in reads {
        return_resident_read(read) |> ignore
      }
      return Err(ForeignCandidate)
    }
    // View SQL is built under the remaining UTF-8 allowance.
    match @duckdb_compute.duckdb_resident_read_bytes(read.view, remaining) {
      Some(bytes) => remaining -= bytes
      None => {
        for read in reads {
          return_resident_read(read) |> ignore
        }
        return Err(Physical(PlanningLimit))
      }
    }
  }
  Ok({
    owner: run.offer_owner,
    task,
    environment: env,
    compute,
    reads,
    claimed: false,
    returned: false,
  })
}

///|
fn resident_inputs_match(
  run : CapturedDAG,
  value : ResidentInputs,
  task : Int,
  compute : @duckdb.FixedCompute,
) -> Bool {
  if value.claimed ||
    value.returned ||
    value.task != task ||
    !physical_equal(value.owner, run.offer_owner) ||
    !physical_equal(value.compute, compute) {
    return false
  }
  for read in value.reads {
    if !resident_read_matches(run, read, read.input) {
      return false
    }
  }
  true
}

///|
pub fn resident_inputs_read_plans(
  value : ResidentInputs,
) -> Array[@duckdb_compute.DuckDBResidentRead] {
  value.reads.map(read => read.view)
}

///|
/// Only unstarted preparation may be cancelled by the caller. Once claimed,
/// native settlement owns release, including after cancellation or failure.
pub fn cancel_resident_inputs(
  value : ResidentInputs,
) -> Result[Unit, @resources.LedgerIssue] {
  if value.claimed || value.returned {
    return Err(InvalidCharge)
  }
  return_resident_inputs(value)
}

///|
fn return_resident_inputs(
  value : ResidentInputs,
) -> Result[Unit, @resources.LedgerIssue] {
  if value.returned {
    return Err(InvalidCharge)
  }
  for read in value.reads {
    match return_resident_read(read) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  value.returned = true
  Ok(())
}
