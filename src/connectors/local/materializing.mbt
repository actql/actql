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
  // The computation runs only through its bounded provider, one quantum per
  // advance, over the constrained sequence.
  provider : ManagedProvider
  sequence : @execution.GeneratedSequence
  execution : @execution.SequenceExecutionLimits
  mut numeric : @execution.NumericAggregateExecution?
  max_rows : Int
  max_value_bytes : Int
  mut provider_execution : ManagedProviderExecution?
  // Snapshot only when cleanup releases the provider handle. The provider's
  // existing owner is the sole accumulator, also for close-driven stop polls.
  mut provider_work : Result[Int64, ManagedProviderWorkIssue]
  // The reads given to the provider: imported copies rebind their producer.
  mut reads : Array[@execution.ProducerRead]
  mut started : Bool
  mut closed : Bool
  mut settled : Bool
  mut output : @execution.CompletedOutput?
  mut publication_output : @execution.CompletedOutput?
  output_limits : LocalExportLimits?
  mut exported : Bool
  mut export_stream : @execution.CompletedOutputExport?
  mut export_receipt : @execution.CompletedOutputExportReceipt?
  mut release_check : (() -> Bool)?
}

///|
/// Import limits a Host has not configured explicitly, for a bounded
/// materializing attempt: the module's own row and input-guard limits,
/// clamped to the configurable retained-row bounds.
pub fn local_default_import_limits(
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> LocalImportLimits {
  let frame_bytes = Int::max(1, Int::min(measurement.max_bytes, 16777216))
  let depth = Int::max(1, Int::min(measurement.max_depth, 64))
  {
    max_rows: execution.rows.max_rows,
    values: execution.rows.input_values,
    wire: {
      max_columns: measurement.max_nodes,
      max_order_work: measurement.max_work,
      max_bytes: measurement.max_bytes,
      max_nodes: measurement.max_nodes,
      max_depth: depth,
    },
    row: {
      max_bytes: frame_bytes,
      max_nodes: measurement.max_nodes,
      max_depth: depth,
      max_text_bytes: execution.rows.input_values.max_text_bytes,
    },
    max_batch_bytes: frame_bytes,
  }
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
pub fn[E] prepare_local_materializing_execution(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  imports : LocalImportLimits,
  issue : (LocalMaterializingIssue) -> E,
  join_output_ceiling? : (Int, Int64)? = None,
  output_limits? : LocalExportLimits? = None,
  join_output_ceilings? : Array[(Int, Int64)] = [],
  expansion_output_ceilings? : Array[(Int, Int64)] = [],
  session_output_ceilings? : Array[(Int, Int64)] = [],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
  sequence_match_ceilings? : Array[(Int, Int64, Int64)] = [],
  aggregate_output_ceilings? : Array[@connector.AggregateOutputCeiling] = [],
  analytic_envelopes? : Array[@connector.AnalyticEnvelope] = [],
  family_providers? : Array[ManagedProvider] = [],
  provider_capacity? : @connector.FixedComputeCapacity? = None,
) -> Result[
  @connector.PreparedExecution[LocalMaterializingAttempt, E],
  LocalMaterializingIssue,
] {
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) else {
    return Err(Candidate(NotSelected))
  }
  // There is no synchronous whole-sequence lane: a sequence no bounded
  // provider accepts is not a materializing candidate.
  guard local_managed_provider_for(
      family_providers, execution, measurement, sequence,
    )
    is Some(provider) else {
    return Err(Candidate(ComputeUnsupported))
  }
  guard managed_provider_capacity(provider, sequence) is Some(base) &&
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
    is Some(_) else {
    return Err(Candidate(UnsupportedInputShape))
  }
  let ceilings = join_output_ceilings.copy()
  if join_output_ceiling is Some(ceiling) {
    ceilings.push(ceiling)
  }
  let constrained = match
    constrain_local_managed_sequence(
      sequence,
      join_output_ceilings=ceilings,
      expansion_output_ceilings~,
      session_output_ceilings~,
      interval_search_ceilings~,
      asof_search_ceilings~,
      sequence_match_ceilings~,
      aggregate_output_ceilings~,
      analytic_envelopes~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  // The provider runs under the same row and value capacity as managed Local
  // work; the ordinary request capacity describes only the task boundary.
  let request_capacity = provider_capacity.unwrap_or(
    @connector.fixed_compute_request_capacity(request),
  )
  @connector.bind_prepared_materializing_execution(
    choice,
    prepared,
    {
      transfer_bytes: transfer,
      retained_bytes: retention,
      scratch_bytes: base.execution_bytes,
      execution_bytes: base.execution_bytes,
    },
    ceilings,
    fn(_) {
      let attempt : LocalMaterializingAttempt = {
        inputs,
        imports: Array::make(inputs.length(), None),
        copies: Array::make(inputs.length(), None),
        limits: imports,
        provider,
        sequence: constrained,
        execution,
        numeric: None,
        max_rows: request_capacity.max_rows,
        max_value_bytes: request_capacity.max_value_bytes,
        provider_execution: None,
        provider_work: Ok(0L),
        reads: [],
        started: false,
        closed: false,
        settled: false,
        output: None,
        publication_output: None,
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
            settled: fn() {
              attempt.settled = true
              if !attempt.closed && attempt.output is Some(_) {
                release_local_materializing_scratch(attempt) |> ignore
              }
            },
            scratch_released: fn() { attempt.provider_execution is None },
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
          },
        ),
      )
    },
    aggregate_output_ceilings~,
    analytic_envelopes~,
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
  // Drains the same bounded execution for Hosts that own no event loop.
  while true {
    match advance_local_materializing_attempt(attempt, 256) {
      Ok(advance) => if advance.complete { break Ok(()) }
      Err(issue) => break Err(issue)
    }
  } nobreak {
    Err(State)
  }
}

///|
pub(all) struct LocalMaterializingAdvance {
  complete : Bool
  progress : Int64
  work : Int64
}

///|
/// The exact task ticket supplies numeric authority after candidate selection
/// and before the first bounded provider step.
pub fn bind_local_materializing_numeric_execution(
  attempt : LocalMaterializingAttempt,
  numeric : @execution.NumericAggregateExecution,
) -> Bool {
  if attempt.started ||
    attempt.closed ||
    attempt.settled ||
    attempt.numeric is Some(_) {
    return false
  }
  attempt.numeric = Some(numeric)
  true
}

///|
/// Advance the attempt's bounded provider by at most `quantum` work units.
/// The first advance requires every retained input to be fully imported.
pub fn advance_local_materializing_attempt(
  attempt : LocalMaterializingAttempt,
  quantum : Int,
) -> Result[LocalMaterializingAdvance, LocalMaterializingIssue] {
  if attempt.closed || attempt.settled || attempt.output is Some(_) {
    return Err(State)
  }
  let active = match attempt.provider_execution {
    Some(value) => value
    None => {
      if attempt.started {
        return Err(State)
      }
      let inputs = attempt.inputs.copy()
      for index, input in attempt.inputs {
        match attempt.copies[index] {
          Some(output) =>
            match @execution.rebind_producer_representation(input, output) {
              Ok(read) => inputs[index] = read
              Err(_) => return Err(Candidate(ForeignPreparation))
            }
          None =>
            if !@execution.producer_read_has_cell_access(input) {
              return Err(State)
            }
        }
      }
      attempt.started = true
      attempt.reads = inputs
      let started = match
        start_managed_provider_with_inputs_and_execution(
          attempt.provider,
          attempt.sequence,
          inputs.map(managed_provider_relation_input),
          attempt.max_rows,
          attempt.max_value_bytes,
          attempt.execution,
          numeric=attempt.numeric,
        ) {
        Ok(value) => value
        Err(error) => {
          close_local_materializing_attempt(attempt)
          return Err(Candidate(error))
        }
      }
      attempt.provider_execution = Some(started)
      started
    }
  }
  let bounded = fn(progress : Int64, work : Int64, complete : Bool) {
    progress >= 0L &&
    work >= 0L &&
    work <= quantum.to_int64() &&
    (complete || work > 0L)
  }
  let poll = advance_managed_provider(active, quantum)
  if managed_provider_cumulative_work(active) is Err(_) {
    close_local_materializing_attempt(attempt)
    return Err(Candidate(InvalidLimits))
  }
  match poll {
    Err(error) => {
      close_local_materializing_attempt(attempt)
      Err(Candidate(error))
    }
    Ok(Continue(progress~, work~)) =>
      if bounded(progress, work, false) {
        Ok({ complete: false, progress, work, })
      } else {
        close_local_materializing_attempt(attempt)
        Err(Candidate(InvalidLimits))
      }
    Ok(Complete(output, progress~, work~)) =>
      if bounded(progress, work, true) {
        // Anchor to the exact reads the provider was started with.
        let anchored = match
          @execution.completion_preparation_selected_step(
            @execution.generated_completion_preparation(attempt.sequence),
          ) {
          Some(step) =>
            @execution.anchor_completed_output_operation_inputs(
              output,
              step,
              attempt.reads,
            )
          None =>
            @execution.anchor_completed_output_inputs(output, attempt.reads)
        }
        guard anchored is Some(anchored) else {
          close_local_materializing_attempt(attempt)
          return Err(Candidate(ForeignPreparation))
        }
        attempt.output = Some(anchored)
        Ok({ complete: true, progress, work, })
      } else {
        close_local_materializing_attempt(attempt)
        Err(Candidate(InvalidLimits))
      }
    Ok(CarrierComplete(material, ..)) => {
      @carrier_runtime.reclaim_material(material) |> ignore
      close_local_materializing_attempt(attempt)
      Err(Candidate(UnsupportedInputShape))
    }
    Ok(Failed(error, ..)) => {
      close_local_materializing_attempt(attempt)
      Err(Candidate(error))
    }
    Ok(Stopped(..)) => {
      close_local_materializing_attempt(attempt)
      Err(State)
    }
  }
}

///|
/// Request a stop. A started provider reports the stop on its next advance.
pub fn cancel_local_materializing_attempt(
  attempt : LocalMaterializingAttempt,
) -> Bool {
  match attempt.provider_execution {
    Some(active) => cancel_managed_provider(active)
    None => false
  }
}

///|
/// True once no provider computation can run: never started, or stopped.
pub fn local_materializing_stopped(attempt : LocalMaterializingAttempt) -> Bool {
  match attempt.provider_execution {
    Some(active) => managed_provider_stopped(active)
    None => true
  }
}

///|
/// Available only after successful complete input and output measurement.
pub fn local_materializing_guard_usage(
  attempt : LocalMaterializingAttempt,
) -> (Int, Int, Int)? {
  // Bounded providers admit their inputs step by step; there is no separate
  // whole-input guard measurement to report.
  ignore(attempt)
  None
}

///|
/// Total work the bounded provider reported across the advances of a
/// completed attempt. This is the provider's own report, not a value
/// measurement: no input or output values are scanned to produce it.
pub fn local_materializing_provider_work(
  attempt : LocalMaterializingAttempt,
) -> Int64? {
  if attempt.closed || attempt.output is None {
    None
  } else {
    local_materializing_cumulative_work(attempt).to_option()
  }
}

///|
/// Diagnostic provider work, including failure and physical stop, available
/// before completion and after close/cleanup. This is not billing approval.
pub fn local_materializing_cumulative_work(
  attempt : LocalMaterializingAttempt,
) -> Result[Int64, ManagedProviderWorkIssue] {
  match attempt.provider_execution {
    Some(active) => managed_provider_cumulative_work(active)
    None => attempt.provider_work
  }
}

///|
/// Exact admitted in-memory output for the common completion boundary. This
/// returns the evaluator-owned generation without copying, serializing or
/// recomputing its value evidence.
pub fn local_materializing_completed_output(
  attempt : LocalMaterializingAttempt,
) -> @execution.CompletedOutput? {
  if attempt.closed ||
    !attempt.settled ||
    (attempt.output_limits is Some(_) && !attempt.exported) {
    None
  } else {
    attempt.output
  }
}

///|
/// The evaluator-owned cell view shares the exact completion occurrence with
/// the retained file. Publication may borrow it only while this attempt and
/// its verified retained output are both available.
pub fn local_materializing_publication_output(
  attempt : LocalMaterializingAttempt,
) -> @execution.CompletedOutput? {
  if attempt.closed ||
    !attempt.settled ||
    !attempt.exported ||
    attempt.output is None {
    None
  } else {
    attempt.publication_output
  }
}

///|
/// The detached output has its own retention. Release only stopped provider
/// workspace, retaining the existing owner on pending/error for close retry.
fn release_local_materializing_scratch(
  attempt : LocalMaterializingAttempt,
) -> Bool {
  match attempt.provider_execution {
    None => true
    Some(active) => {
      if !managed_provider_stopped(active) ||
        !cleanup_managed_provider(active).unwrap_or(false) {
        return false
      }
      attempt.provider_work = managed_provider_cumulative_work(active)
      attempt.provider_execution = None
      true
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
  attempt.publication_output = None
  if attempt.provider_execution is Some(active) {
    // A started provider reports its stop on one final advance before its
    // workspace is reclaimed.
    if !managed_provider_stopped(active) {
      cancel_managed_provider(active) |> ignore
      advance_managed_provider(active, 1) |> ignore
    }
    release_local_materializing_scratch(attempt) |> ignore
  }
}
