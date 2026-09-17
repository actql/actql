///|
/// One selected managed DuckDB task. The connector owns its query and typed
/// completion port; the common strategy owns reservation, cancellation and
/// publication. No legacy CID-bearing attempt or finisher is manufactured.
struct CapturedManagedDuckDBTask[T] {
  run : @strategy.CapturedDAG
  query : @duckdb.ManagedFixedQuery[T]
  completion : @compute.ManagedInputDuckDBCompletion[T]
  execution : @strategy.TaskExecution
  inputs : Array[@execution.ManagedProducerRead[T]]
  live : Ref[Bool]
  settled : Ref[Bool]
  disposed : Ref[Bool]
  authorize : () -> Bool
}

///|
/// Install the selected managed realization after common capacity admission.
/// This is synchronous preparation only: it opens no database and reads no
/// Store bytes. The returned task is the sole authority for later transport
/// settlement and managed completion.
pub fn[T] start_captured_managed_duckdb_task(
  run : @strategy.CapturedDAG,
  task : Int,
  choice : @connector.ManagedFixedComputeChoice[T],
  prepared : @connector.PreparedManagedCompute[T, @duckdb.ManagedFixedQuery[T]],
  generated : @execution.CompletionPreparation,
  profile : @execution.ManagedExecutionProfile,
  limits : @compute.DuckDBComputeLimits,
  capacity : @connector.ExecutionCapacity,
  join_output_ceilings : Array[(Int, Int64)],
  authorize : () -> Bool,
  transport_matches : (@execution.ManagedOutputValueReceipt) -> Bool,
  retention_released : () -> Bool,
) -> Result[CapturedManagedDuckDBTask[T], @strategy.RunIssue] {
  let live = Ref(true)
  let settled = Ref(false)
  let disposed = Ref(false)
  let completion : Ref[@compute.ManagedInputDuckDBCompletion[T]?] = Ref(None)
  let bound = match
    @connector.bind_prepared_managed_execution(
      choice,
      prepared,
      capacity,
      join_output_ceilings,
      fn(query) {
        let inputs = @duckdb.managed_fixed_query_inputs(query)
        let prepared_completion = match
          @compute.prepare_managed_input_duckdb_completion(
            query,
            generated,
            profile,
            limits,
            @connector.managed_fixed_compute_request_capacity(
              @connector.managed_fixed_compute_candidate_request(
                @connector.prepared_managed_compute_candidate(prepared),
              ),
            ).max_rows,
            @connector.managed_fixed_compute_request_capacity(
              @connector.managed_fixed_compute_candidate_request(
                @connector.prepared_managed_compute_candidate(prepared),
              ),
            ).max_value_bytes,
            fn() { live.val && !disposed.val && authorize() && live.val },
            fn(receipt) {
              live.val &&
              !disposed.val &&
              settled.val &&
              transport_matches(receipt) &&
              live.val
            },
          ) {
          Ok(value) => value
          Err(issue) => return Err(compute_failure(issue))
        }
        completion.val = Some(prepared_completion)
        let operations : @connector.ManagedExecutionOperations[
          @strategy.RunIssue,
        ] = {
          cancel: fn() {
            live.val = false
            @compute.cancel_managed_input_duckdb_completion(prepared_completion)
            |> ignore
          },
          dispose: fn() {
            disposed.val = true
            live.val = false
            @compute.cancel_managed_input_duckdb_completion(prepared_completion)
            |> ignore
          },
          settled: fn() { settled.val = true },
          retention_released,
          released: fn() { () },
          ready: fn() {
            if !live.val ||
              disposed.val ||
              !settled.val ||
              !authorize() ||
              !@duckdb.managed_fixed_query_matches_inputs(query, inputs) ||
              !live.val {
              Err(@strategy.RunIssue::NotReady)
            } else {
              Ok(())
            }
          },
        }
        Ok(((query, inputs), operations))
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Compute(issue))
  }
  match @strategy.start_captured_managed_execution(run, task, bound) {
    Err(issue) => Err(issue)
    Ok(((query, inputs), execution)) => {
      guard completion.val is Some(completion) else {
        return Err(Implementation(DuckDBFailure::Compute(InvalidState)))
      }
      guard @strategy.task_execution_managed_attempt(run, execution)
        is Some(attempt) &&
        @compute.bind_managed_input_duckdb_completion_attempt(
          completion, attempt,
        ) else {
        return Err(Implementation(DuckDBFailure::Compute(InvalidState)))
      }
      Ok({
        run,
        query,
        completion,
        execution,
        inputs,
        live,
        settled,
        disposed,
        authorize,
      })
    }
  }
}

///|
pub fn[T] captured_managed_duckdb_query(
  task : CapturedManagedDuckDBTask[T],
) -> @duckdb.ManagedFixedQuery[T] {
  task.query
}

///|
pub fn[T] captured_managed_duckdb_run(
  task : CapturedManagedDuckDBTask[T],
) -> @strategy.CapturedDAG {
  task.run
}

///|
pub fn[T] captured_managed_duckdb_completion(
  task : CapturedManagedDuckDBTask[T],
) -> @compute.ManagedInputDuckDBCompletion[T] {
  task.completion
}

///|
pub fn[T] captured_managed_duckdb_execution(
  task : CapturedManagedDuckDBTask[T],
) -> @strategy.TaskExecution {
  task.execution
}

///|
pub fn[T] captured_managed_duckdb_input(
  task : CapturedManagedDuckDBTask[T],
) -> @execution.ManagedProducerRead[T] {
  task.inputs[0]
}

///|
pub fn[T] captured_managed_duckdb_inputs(
  task : CapturedManagedDuckDBTask[T],
) -> Array[@execution.ManagedProducerRead[T]] {
  task.inputs.copy()
}

///|
pub fn[T] captured_managed_duckdb_input_count(
  task : CapturedManagedDuckDBTask[T],
) -> Int {
  task.inputs.length()
}

///|
pub fn[T] captured_managed_duckdb_input_at(
  task : CapturedManagedDuckDBTask[T],
  index : Int,
) -> @execution.ManagedProducerRead[T]? {
  task.inputs.get(index)
}

///|
/// Host-installed native settlement predicate for managed view issuance. It
/// does not grant Store access or replace common completion admission.
pub fn[T] captured_managed_duckdb_native_verified(
  task : CapturedManagedDuckDBTask[T],
) -> Bool {
  task.live.val &&
  task.settled.val &&
  !task.disposed.val &&
  (task.authorize)() &&
  @duckdb.managed_fixed_query_matches_inputs(task.query, task.inputs) &&
  task.live.val
}

///|
pub fn[T] settle_captured_managed_duckdb_task(
  task : CapturedManagedDuckDBTask[T],
  confirmed : Bool,
) -> Result[Unit, @resources.LedgerIssue] {
  @strategy.settle_task_execution(task.run, task.execution, confirmed)
}

///|
pub fn[T] close_captured_managed_duckdb_task(
  task : CapturedManagedDuckDBTask[T],
) -> Unit {
  @strategy.close_task_execution(task.run, task.execution)
}
