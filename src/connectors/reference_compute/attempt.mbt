///|
pub(all) struct NumericExecutionLimits {
  max_work : Int
  values : @execution.ValueLimits
  physical : @execution.FixedInputGuardMeasureLimits
  roots : @execution.FixedInputGuardMeasureLimits
  max_entries : Int
  max_name_bytes : Int
}

///|
struct NumericAttempt {
  compute : NumericCompute
  generated : @execution.GeneratedSequence
  limits : NumericExecutionLimits
  mut started : Bool
  mut closed : Bool
  mut settled : Bool
  mut completed : CompletedNumericOutput?
}

///|
/// Reservation accounting uses bounded allocation units, not process RSS:
/// 64 bytes per kernel work unit bounds selected positions, projected cells and
/// row bookkeeping; measurement writer storage is bounded by its byte ceilings.
/// Input storage is borrowed. The output budget remains held after scratch ends.
pub fn numeric_execution_capacity(
  limits : NumericExecutionLimits,
) -> Result[@connector.ExecutionCapacity, PlanIssue] {
  let p = limits.physical
  let r = limits.roots
  let v = limits.values
  if limits.max_work < 0 ||
    limits.max_entries < 0 ||
    limits.max_name_bytes < 0 ||
    p.max_work < 0 ||
    p.max_bytes < 0 ||
    p.max_nodes < 0 ||
    p.max_depth < 0 ||
    r.max_work < 0 ||
    r.max_bytes < 0 ||
    r.max_nodes < 0 ||
    r.max_depth < 0 ||
    v.max_work < 0 ||
    v.max_nodes < 0 ||
    v.max_text_bytes < 0 ||
    v.max_depth < 0 {
    return Err(Limit)
  }
  let retained = 64L * limits.max_work.to_int64()
  let scratch = retained +
    p.max_bytes.to_int64() +
    r.max_bytes.to_int64() +
    64L *
    (p.max_nodes.to_int64() + r.max_nodes.to_int64() + v.max_nodes.to_int64())
  Ok({
    transfer_bytes: 0L,
    retained_bytes: retained,
    scratch_bytes: scratch,
    execution_bytes: scratch,
  })
}

///|
/// Pure installed wiring. The SDK creates the attempt only after common start
/// admission. No engine executor, provider tag, cast or external I/O is used.
pub fn[E, P] prepare_numeric_execution(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[NumericCompute],
  generated : @execution.GeneratedSequence,
  limits : NumericExecutionLimits,
  issue : (PlanIssue) -> E,
) -> Result[@connector.PreparedExecution[NumericAttempt, E, P], PlanIssue] {
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(compute) &&
    physical_equal(
      @execution.generated_sequence_owner(generated),
      compute.plan.owner,
    ) else {
    return Err(Candidate(NotSelected))
  }
  let capacity = match numeric_execution_capacity(limits) {
    Ok(capacity) => capacity
    Err(issue) => return Err(issue)
  }
  @connector.bind_prepared_execution(choice, prepared, capacity, None, fn(
    compute,
  ) {
    let attempt = {
      compute,
      generated,
      limits,
      started: false,
      closed: false,
      settled: false,
      completed: None,
    }
    let close = fn() {
      attempt.closed = true
      if attempt.completed is Some(result) {
        close_numeric_output(result)
      }
    }
    let operations : @connector.ExecutionOperations[E, P] = {
      cancel: close,
      dispose: close,
      settled: fn() { attempt.settled = true },
      released: fn() {  },
      ready: fn() {
        if !attempt.closed && attempt.completed is Some(_) {
          Ok(())
        } else {
          Err(issue(Unsupported))
        }
      },
      finish: fn() {
        match attempt.completed {
          Some(result) if !attempt.closed =>
            Ok(numeric_completed_output(result))
          _ => Err(issue(Unsupported))
        }
      },
      publish: fn(_) { Ok(()) },
    }
    Ok((attempt, operations))
  }).map_err(issue => Candidate(issue))
}

///|
/// One synchronous execution, after the common driver returns the admitted
/// attempt. A failed or cancelled attempt cannot be retried or publish output.
pub fn execute_numeric_attempt(
  attempt : NumericAttempt,
) -> Result[Unit, PlanIssue] {
  if attempt.started || attempt.closed || attempt.settled {
    return Err(Unsupported)
  }
  attempt.started = true
  let capacity = @connector.fixed_compute_request_capacity(
    attempt.compute.request,
  )
  let input = @connector.fixed_compute_request_input(attempt.compute.request, 0).unwrap()
  let limits = attempt.limits
  let result = measure_numeric_output(
    attempt.compute.plan,
    input,
    limits.max_work,
    capacity.max_rows,
    capacity.max_value_bytes,
    limits.values,
    limits.physical,
    root_limits=limits.roots,
  ).bind(measured => {
    complete_numeric_output(
      attempt.generated,
      measured,
      limits.max_entries,
      limits.max_name_bytes,
    )
  })
  match result {
    Ok(result) => {
      attempt.completed = Some(result)
      Ok(())
    }
    Err(issue) => {
      attempt.closed = true
      Err(issue)
    }
  }
}
