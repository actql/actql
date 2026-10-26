///|
/// A complete ordered set of borrowers for one task and one environment.
/// Individual reads are not exposed, so claimed task leases cannot be returned
/// independently by callers. Equal table contents never establish ownership.
struct ResidentInputs {
  owner : StrategyOfferOwner
  task : Int
  environment : ResidentEnvironment
  candidate : @connector.FixedComputeCandidate
  reads : Array[ResidentRead]
  mut claimed : Bool
  mut returned : Bool
}

///|
/// Exact claimed read lease for trusted representation-content reuse. Returned,
/// retired, foreign and unstarted leases cannot authorize this shortcut.
pub fn resident_input_content_available(
  run : CapturedDAG,
  value : ResidentInputs,
  port : Int,
  input : @execution.ProducerRead,
) -> Bool {
  guard !run.stopped &&
    value.claimed &&
    !value.returned &&
    physical_equal(value.owner, run.offer_owner) &&
    value.reads.get(port) is Some(read) else {
    return false
  }
  resident_read_matches(run, read, input)
}

///|
pub fn prepare_resident_inputs(
  run : CapturedDAG,
  env : ResidentEnvironment,
  task : Int,
  tables : Array[ResidentTable],
  candidate : @connector.FixedComputeCandidate,
  max_entries : Int,
  max_name_bytes : Int,
  max_representation_bytes : Int,
  prepare_view : (Int, ResidentTable, @execution.ProducerRead, Int) -> Result[
    Int,
    RunIssue,
  ],
) -> Result[ResidentInputs, RunIssue] {
  if next_captured_task(run) != Some(task) ||
    !resident_environment_available(run, env) {
    return Err(NotReady)
  }
  let request = @connector.fixed_compute_candidate_request(candidate)
  if !(graph_task_owner(run.graph, task) is Some(owner) &&
    physical_equal(owner, @connector.fixed_compute_request_owner(request))) {
    return Err(ForeignCandidate)
  }
  guard run.inputs.get(task) is Some(ports) &&
    tables.length() == ports.length() &&
    tables.length() == @connector.fixed_compute_request_input_count(request) &&
    !tables.is_empty() else {
    return Err(ForeignCandidate)
  }
  let reads : Array[ResidentRead] = []
  let mut remaining = max_representation_bytes
  for port in 0..<tables.length() {
    let measured = Ref(0)
    let result = if !physical_equal(tables[port].environment, env) {
      Err(ForeignCandidate)
    } else {
      borrow_resident_table(
        run,
        tables[port],
        task,
        max_entries,
        max_name_bytes,
        fn(table, input) {
          prepare_view(port, table, input, remaining).map(bytes => {
            measured.val = bytes
          })
        },
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
    guard @connector.fixed_compute_request_input(request, port)
      is Some(@execution.CompletedRelation(input)) &&
      physical_equal(input, read.input) else {
      for read in reads {
        return_resident_read(read) |> ignore
      }
      return Err(ForeignCandidate)
    }
    if measured.val < 0 || measured.val > remaining {
      for read in reads {
        return_resident_read(read) |> ignore
      }
      return Err(Physical(PlanningLimit))
    } else {
      remaining -= measured.val
    }
  }
  Ok({
    owner: run.offer_owner,
    task,
    environment: env,
    candidate,
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
  candidate : @connector.FixedComputeCandidate,
) -> Bool {
  if value.claimed ||
    value.returned ||
    value.task != task ||
    !physical_equal(value.owner, run.offer_owner) ||
    !physical_equal(value.candidate, candidate) {
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
