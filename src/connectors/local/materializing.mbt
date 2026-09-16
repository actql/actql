///|
/// Bounded full-producer conversion, not only the receiving projection. Each
/// converted input gets its own allowance; equal content does not share a copy.
pub(all) struct LocalImportLimits {
  max_rows : Int
  values : @execution.ValueLimits
  wire : @execution.RowWireLimits
  row : @execution.RetainedRowDecodeLimits
  max_batch_bytes : Int
}

///|
pub(all) enum LocalMaterializingIssue {
  State
  Capacity
  Candidate(@connector.FixedComputeIssue)
  Import(@execution.CompletedImportIssue)
  Export(@execution.CompletedExportIssue)
}

///|
struct LocalMaterializingAttempt {
  inputs : Array[@execution.ProducerRead]
  imports : Array[@execution.CompletedOutputImport?]
  copies : Array[@execution.CompletedOutput?]
  limits : LocalImportLimits
  execute : (Array[@execution.CompletedOutput?]) -> Result[
    @execution.CompletedOutput,
    @connector.FixedComputeIssue,
  ]
  mut started : Bool
  mut closed : Bool
  mut settled : Bool
  mut output : @execution.CompletedOutput?
  output_limits : LocalExportLimits?
  mut exported : Bool
  mut export_stream : @execution.CompletedOutputExport?
  mut export_receipt : @execution.CompletedOutputExportReceipt?
  mut release_check : (() -> Bool)?
}

///|
/// Conservative allocation units, not RSS: 64 bytes per admitted/decoded/wire
/// node and row/column slot; 8 bytes per text/wire/frame byte. Imported storage
/// is retained with the result because a Local result can share input buffers.
pub fn local_import_retention_capacity(limits : LocalImportLimits) -> Int64? {
  let v = limits.values
  let w = limits.wire
  let r = limits.row
  if limits.max_batch_bytes < 1 || r.max_bytes < 1 {
    return None
  }
  for
    value in [
      limits.max_rows,
      limits.max_batch_bytes,
      v.max_nodes,
      v.max_text_bytes,
      v.max_work,
      v.max_depth,
      w.max_bytes,
      w.max_nodes,
      w.max_depth,
      w.max_columns,
      w.max_order_work,
      r.max_bytes,
      r.max_nodes,
      r.max_depth,
      r.max_text_bytes,
    ] {
    if value < 0 {
      return None
    }
  }
  Some(
    64L *
    (
      limits.max_rows.to_int64() +
      v.max_nodes.to_int64() +
      w.max_nodes.to_int64() +
      w.max_columns.to_int64() +
      r.max_nodes.to_int64()
    ) +
    8L *
    (
      v.max_text_bytes.to_int64() +
      w.max_bytes.to_int64() +
      limits.max_batch_bytes.to_int64() +
      r.max_bytes.to_int64() +
      r.max_text_bytes.to_int64()
    ),
  )
}

///|
/// Preparation is pure. Actual imports may start only after the common Host
/// reserves this attempt. The same selected Local candidate remains authoritative.
pub fn[E, P] prepare_local_materializing_execution(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  imports : LocalImportLimits,
  issue : (LocalMaterializingIssue) -> E,
  join_output_ceiling? : (Int, Int64)? = None,
  output_limits? : LocalExportLimits? = None,
) -> Result[
  @connector.PreparedExecution[LocalMaterializingAttempt, E, P],
  LocalMaterializingIssue,
] {
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) else {
    return Err(Candidate(NotSelected))
  }
  guard @execution.generated_sequence_capacity(sequence, execution, measurement)
    is Some(base) &&
    local_import_retention_capacity(imports) is Some(per_input) else {
    return Err(Capacity)
  }
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  let inputs = @connector.fixed_compute_request_inputs(request)
  let mut retention = base.retained_bytes
  if output_limits is Some(limits) {
    guard local_export_retention_capacity(limits) is Some(extra) &&
      extra <= 9223372036854775807L - retention else {
      return Err(Capacity)
    }
    retention += extra
  }
  let mut transfer = 0L
  for input in inputs {
    if !@execution.producer_read_has_cell_access(input) {
      if per_input > 9223372036854775807L - retention ||
        imports.wire.max_bytes.to_int64() > 9223372036854775807L - transfer {
        return Err(Capacity)
      }
      retention += per_input
      transfer += imports.wire.max_bytes.to_int64()
    }
  }
  guard @lower.preparation_output_target(
      @lower.bound_preparation(@connector.fixed_compute_request_owner(request)),
    )
    is Some(target) else {
    return Err(Candidate(UnsupportedInputShape))
  }
  @connector.bind_prepared_execution(
    choice,
    prepared,
    {
      transfer_bytes: transfer,
      retained_bytes: retention,
      scratch_bytes: base.execution_bytes,
      execution_bytes: base.execution_bytes,
    },
    match join_output_ceiling {
      Some(limit) => [limit]
      None => []
    },
    fn(_) {
      let attempt : LocalMaterializingAttempt = {
        inputs,
        imports: Array::make(inputs.length(), None),
        copies: Array::make(inputs.length(), None),
        limits: imports,
        execute: copies => {
          execute_local_fixed_compute(
            choice,
            prepared,
            execution,
            measurement~,
            join_output_ceiling~,
            representations=copies,
          ).bind(completed => {
            match @execution.completed_output(completed, target) {
              Some(output) => Ok(output)
              None => Err(@connector.FixedComputeIssue::UnsupportedInputShape)
            }
          })
        },
        started: false,
        closed: false,
        settled: false,
        output: None,
        output_limits,
        exported: false,
        export_stream: None,
        export_receipt: None,
        release_check: None,
      }
      let close = fn() { close_local_materializing_attempt(attempt) }
      Ok(
        (
          attempt,
          {
            cancel: close,
            dispose: close,
            settled: fn() { attempt.settled = true },
            retention_released: () => {
              match attempt.release_check {
                None => true
                Some(check) => check()
              }
            },
            released: fn() {  },
            ready: fn() {
              if !attempt.closed &&
                attempt.output is Some(_) &&
                (attempt.output_limits is None || attempt.exported) {
                Ok(())
              } else {
                Err(issue(State))
              }
            },
            finish: fn() {
              match attempt.output {
                Some(output) if !attempt.closed &&
                  (attempt.output_limits is None || attempt.exported) =>
                  Ok(output)
                _ => Err(issue(State))
              }
            },
            publish: fn(_) { Ok(()) },
          },
        ),
      )
    },
  ).map_err(error => LocalMaterializingIssue::Candidate(error))
}

///|
pub fn local_materializing_input(
  attempt : LocalMaterializingAttempt,
  port : Int,
) -> @execution.ProducerRead? {
  if attempt.closed || attempt.started {
    None
  } else {
    attempt.inputs.get(port)
  }
}

///|
pub fn begin_local_materializing_input(
  attempt : LocalMaterializingAttempt,
  port : Int,
) -> Result[Unit, LocalMaterializingIssue] {
  guard local_materializing_input(attempt, port) is Some(input) &&
    !@execution.producer_read_has_cell_access(input) &&
    attempt.imports[port] is None &&
    attempt.copies[port] is None else {
    return Err(State)
  }
  let limits = attempt.limits
  match
    @execution.prepare_producer_output_import(
      input,
      limits.max_rows,
      limits.values,
      limits.wire,
      limits.max_batch_bytes,
    ) {
    Ok(value) => {
      attempt.imports[port] = Some(value)
      Ok(())
    }
    Err(error) => {
      close_local_materializing_attempt(attempt)
      Err(Import(error))
    }
  }
}

///|
pub fn append_local_materializing_input(
  attempt : LocalMaterializingAttempt,
  port : Int,
  row : String,
) -> Result[Unit, LocalMaterializingIssue] {
  guard !attempt.closed &&
    !attempt.started &&
    attempt.imports.get(port) is Some(Some(value)) else {
    return Err(State)
  }
  match
    @execution.append_completed_output_import_wire(
      value,
      row,
      attempt.limits.row,
    ) {
    Ok(_) => Ok(())
    Err(error) => {
      close_local_materializing_attempt(attempt)
      Err(Import(error))
    }
  }
}

///|
/// Installed reader calls after complete physical integrity verification. The
/// common converter independently verifies the ordered logical identity.
pub fn finish_local_materializing_input(
  attempt : LocalMaterializingAttempt,
  port : Int,
) -> Result[Unit, LocalMaterializingIssue] {
  guard !attempt.closed &&
    !attempt.started &&
    attempt.imports.get(port) is Some(Some(value)) else {
    return Err(State)
  }
  match @execution.finish_completed_output_import(value) {
    Ok(output) => {
      attempt.imports[port] = None
      attempt.copies[port] = Some(output)
      Ok(())
    }
    Err(error) => {
      close_local_materializing_attempt(attempt)
      Err(Import(error))
    }
  }
}

///|
pub fn execute_local_materializing_attempt(
  attempt : LocalMaterializingAttempt,
) -> Result[Unit, LocalMaterializingIssue] {
  if attempt.closed || attempt.started || attempt.settled {
    return Err(State)
  }
  for index, input in attempt.inputs {
    if !@execution.producer_read_has_cell_access(input) &&
      attempt.copies[index] is None {
      return Err(State)
    }
  }
  attempt.started = true
  match (attempt.execute)(attempt.copies) {
    Ok(output) => {
      attempt.output = Some(output)
      Ok(())
    }
    Err(error) => {
      close_local_materializing_attempt(attempt)
      Err(Candidate(error))
    }
  }
}

///|
pub fn close_local_materializing_attempt(
  attempt : LocalMaterializingAttempt,
) -> Unit {
  attempt.closed = true
  if attempt.export_stream is Some(stream) {
    @execution.cancel_completed_output_export(stream)
  }
  if attempt.export_receipt is Some(receipt) {
    @execution.cancel_completed_export_receipt(receipt)
  }
  attempt.export_stream = None
  attempt.export_receipt = None
  for index, value in attempt.imports {
    if value is Some(value) {
      @execution.cancel_completed_output_import(value) |> ignore
    }
    attempt.imports[index] = None
    attempt.copies[index] = None
  }
  attempt.output = None
}
