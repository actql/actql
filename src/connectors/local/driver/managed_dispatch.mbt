///|
// A synchronous callback can reenter cancellation. Its stack roots still
// belong to this execution until the callback returns.
fn[A] with_managed_scratch_use(
  uses : Ref[Int],
  release : () -> Unit,
  action : () -> A,
) -> A {
  uses.val += 1
  let result = action()
  uses.val -= 1
  release()
  result
}

///|
/// Pure prepared Local managed task. Physical representation access starts
/// only after common selection, reservation and task registration.
struct LocalManagedDispatchConfiguration[T] {
  run : @strategy.CapturedDAG
  task : Int
  choice : @connector.ManagedFixedComputeChoice[T]
  prepared : @connector.PreparedManagedCompute[T, @execution.GeneratedSequence]
  sequence : @execution.GeneratedSequence
  provider : @local.ManagedProvider?
  relation_inputs : Array[LocalManagedRelationInput[T]]
  provider_inputs : Array[LocalManagedPreparedInput]
  completion_inputs : Array[@execution.ManagedInputBinding]
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  imports : @local.LocalImportLimits
  capacity : @connector.ExecutionCapacity
  join_output_ceilings : Array[(Int, Int64)]
  interval_search_ceilings : Array[(Int, Int64)]
  asof_search_ceilings : Array[(Int, Int64)]
  sequence_match_ceilings : Array[(Int, Int64, Int64)]
  aggregate_output_ceilings : Array[@connector.AggregateOutputCeiling]
  analytic_envelopes : Array[@connector.AnalyticEnvelope]
}

///|
pub enum LocalManagedAvailableOutput[T] {
  CapturedRelationInput
  SuppliedRelationInput
  RelationOutput(@execution.ManagedCompletedOutput[T])
  CarrierOutput(
    @execution.CarrierManagedCompletedOutput,
    @carrier_runtime.Material
  )
}

///|
pub fn[T] local_managed_supplied_relation_input() -> LocalManagedAvailableOutput[
  T,
] {
  SuppliedRelationInput
}

///|
pub fn[T] local_managed_captured_relation_input() -> LocalManagedAvailableOutput[
  T,
] {
  CapturedRelationInput
}

///|
pub fn[T] local_managed_relation_output(
  output : @execution.ManagedCompletedOutput[T],
) -> LocalManagedAvailableOutput[T] {
  RelationOutput(output)
}

///|
pub fn[T] local_managed_carrier_output(
  output : @execution.CarrierManagedCompletedOutput,
  material : @carrier_runtime.Material,
) -> LocalManagedAvailableOutput[T] {
  CarrierOutput(output, material)
}

///|
priv enum LocalManagedPreparedInput {
  PreparedRelation(Int)
  PreparedSupplied(@execution.SuppliedRelationRead)
  PreparedCarrier(@carrier_runtime.ProducerView)
}

///|
priv enum LocalManagedRelationInput[T] {
  OrdinaryRelationInput(@execution.ProducerRead)
  SuppliedRelationInput(@execution.SuppliedRelationRead)
  ManagedRelationInput(@execution.ManagedProducerRead[T])
}

///|
fn bind_physical_operation_input(
  run : @strategy.CapturedDAG,
  index : Int,
  binding : @execution.ManagedInputBinding,
) -> @execution.ManagedInputBinding? {
  match @strategy.captured_next_managed_operation_input(run, index) {
    Some((step, operation_input)) =>
      @strategy.graph_task_owner(
        @strategy.captured_dag_graph(run),
        @strategy.next_captured_task(run).unwrap(),
      ).bind(owner => {
        @execution.managed_input_binding_for_operation(
          binding, owner, step, operation_input,
        )
      })
    None => Some(binding)
  }
}

///|
pub struct LocalManagedInputTransfer[T] {
  input : @execution.ManagedProducerRead[T]
  append : (String) -> Result[Unit, LocalDispatchIssue]
  finish : () -> Result[Unit, LocalDispatchIssue]
}

///|
pub(all) struct LocalManagedAdvance {
  complete : Bool
  progress : Int64
  work : Int64
}

///|
/// Primitive Host-facing operations on the same family-owned snapshot handle.
/// File custody remains with the installed Store; no Graph payload is exposed.
pub struct LocalManagedSnapshot {
  key : String
  maximum_bytes : Int
  maximum_frame_bytes : Int
  advance_save : (Int) -> Result[LocalManagedAdvance, LocalDispatchIssue]
  take_output : () -> Result[String, LocalDispatchIssue]
  content : () -> Result[@carrier_runtime.SnapshotContent, LocalDispatchIssue]
  release_source : (String) -> Result[Unit, LocalDispatchIssue]
  begin_reload : (String, () -> Bool) -> Result[Unit, LocalDispatchIssue]
  advance_reload : (Int) -> Result[LocalManagedAdvance, LocalDispatchIssue]
  finish : () -> Result[Unit, LocalDispatchIssue]
}

///|
/// Representation conversion under the existing Relation completion and task
/// owner. The installed Store owns bytes; the common exporter/importer owns
/// presence, order, exact receipts and admission. No Compute is resumed here.
pub struct LocalManagedRelationSnapshot {
  key : String
  frames : LocalInputFrames
  next : () -> Result[String?, LocalDispatchIssue]
  content : () -> Result[@carrier_runtime.SnapshotContent, LocalDispatchIssue]
  release_source : (String, () -> Bool) -> Result[Unit, LocalDispatchIssue]
  source_available : () -> Bool
  begin_reload : () -> Result[Unit, LocalDispatchIssue]
  append_reload : (String) -> Result[Unit, LocalDispatchIssue]
  finish_reload : () -> Result[Unit, LocalDispatchIssue]
  finish : () -> Result[Unit, LocalDispatchIssue]
}

///|
priv enum SnapshotPhase {
  Saving
  Saved
  Released
  Reloading
  Restored
  Finished
  Failed
} derive(Eq)

///|
pub struct LocalManagedDispatchOperations[T] {
  inputs : Array[LocalManagedInputTransfer[T]]
  retained_inputs : Array[LocalInputTransfer]
  execute : () -> Result[Unit, LocalDispatchIssue]
  advance : (Int) -> Result[LocalManagedAdvance, LocalDispatchIssue]
  request_cancel : () -> Bool
  execution_stopped : () -> Bool
  cumulative_provider_work : () -> Result[
    Int64,
    @local.ManagedProviderWorkIssue,
  ]
  prepare_finalization : (T, Int64, () -> Bool) -> Result[
    Unit,
    LocalDispatchIssue,
  ]
  advance_finalization : (Int) -> Result[
    LocalManagedAdvance,
    LocalDispatchIssue,
  ]
  settle : () -> Result[Unit, LocalDispatchIssue]
  complete : (T, Int64, () -> Bool) -> Result[
    @execution.ManagedCompletedOutput[T],
    LocalDispatchIssue,
  ]
  complete_carrier : () -> Result[
    @execution.CarrierManagedCompletedOutput,
    LocalDispatchIssue,
  ]
  output_rows : () -> Int
  output_row : (Int) -> Result[String, LocalDispatchIssue]
  material : () -> @execution.ManagedRetainedOutput[T]?
  carrier_material : () -> @carrier_runtime.Material?
  prepare_carrier_snapshot : (() -> Bool) -> Result[
    LocalManagedSnapshot?,
    LocalDispatchIssue,
  ]
  prepare_relation_snapshot : (() -> Bool) -> Result[
    LocalManagedRelationSnapshot?,
    LocalDispatchIssue,
  ]
  storage_bytes : Int64
  close : () -> Unit
  cleanup_refresh : () -> Bool
}

///|
/// Exact physical transfer unit used by the managed row wire. MoonBit String
/// length is UTF-16 code units and cannot be charged as transported bytes.
fn managed_row_transfer_bytes(
  row : String,
  max_bytes : Int,
) -> Result[Int64, LocalDispatchIssue] {
  @scalar.admit_utf8_length64(row, max_bytes.to_int64()).map_err(_ => {
    Configuration(InputUnavailable)
  })
}

///|
pub fn[T] prepare_local_managed_dispatch(
  installed : LocalDispatchModule,
  outputs : Array[@execution.ManagedCompletedOutput[T]],
  obligations : @execution.ManagedObligations,
  _output_file_bytes : Int64,
) -> Result[LocalManagedDispatchConfiguration[T]?, LocalDispatchIssue] {
  let available = []
  let mut completed = 0
  for producer in @strategy.captured_next_managed_producers(installed.run) {
    if producer == -1 {
      available.push(local_managed_supplied_relation_input())
    } else if completed < outputs.length() {
      available.push(local_managed_relation_output(outputs[completed]))
      completed += 1
    } else {
      return Err(Configuration(InputUnavailable))
    }
  }
  if completed != outputs.length() {
    return Err(Configuration(InputUnavailable))
  }
  prepare_local_managed_dispatch_with_outputs(
    installed, available, obligations, _output_file_bytes,
  )
}

///|
/// Prepare Local execution from the exact ordered Relation/Carrier output set.
pub fn[T] prepare_local_managed_dispatch_with_outputs(
  installed : LocalDispatchModule,
  outputs : Array[LocalManagedAvailableOutput[T]],
  obligations : @execution.ManagedObligations,
  _output_file_bytes : Int64,
) -> Result[LocalManagedDispatchConfiguration[T]?, LocalDispatchIssue] {
  guard @strategy.next_captured_task(installed.run) is Some(task) &&
    installed.import_policy is Some((imports, _)) else {
    return Ok(None)
  }
  if installed.estimate_configuration is Some(configuration) &&
    configuration.eligible.get(task - 1) is Some(false) {
    return Ok(None)
  }
  let relation_inputs = []
  let provider_inputs = []
  let completion_inputs = []
  let producers = @strategy.captured_next_managed_producers(installed.run)
  if producers.length() != outputs.length() {
    return Err(Configuration(InputUnavailable))
  }
  for index, output in outputs {
    match output {
      CapturedRelationInput => {
        let value = match
          @strategy.captured_task_input(
            installed.run,
            task,
            @local.local_module_execution_limits(installed.implementation).rows.metadata_entries,
            imports.wire.max_bytes,
            input_index=index,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Execution(issue))
        }
        if @execution.producer_read_row_count(value) >
          @local.local_module_managed_capacity(installed.implementation).max_rows {
          return Err(Configuration(CommonInputRows))
        }
        let relation_index = relation_inputs.length()
        relation_inputs.push(OrdinaryRelationInput(value))
        provider_inputs.push(PreparedRelation(relation_index))
        guard bind_physical_operation_input(
            installed.run,
            index,
            @execution.ordinary_relation_input_binding(value),
          )
          is Some(binding) else {
          return Err(Configuration(InputUnavailable))
        }
        completion_inputs.push(binding)
      }
      SuppliedRelationInput => {
        let value = match
          @strategy.captured_supplied_task_input(
            installed.run,
            task,
            input_index=index,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Execution(issue))
        }
        if @execution.supplied_relation_read_row_count(value) >
          @local.local_module_managed_capacity(installed.implementation).max_rows {
          return Err(Configuration(CommonInputRows))
        }
        relation_inputs.push(SuppliedRelationInput(value))
        provider_inputs.push(PreparedSupplied(value))
        guard bind_physical_operation_input(
            installed.run,
            index,
            @execution.supplied_relation_input_binding(value),
          )
          is Some(binding) else {
          return Err(Configuration(InputUnavailable))
        }
        completion_inputs.push(binding)
      }
      RelationOutput(output) =>
        match
          @strategy.captured_managed_task_input(
            installed.run,
            task,
            output,
            @local.local_module_execution_limits(installed.implementation).rows.metadata_entries,
            imports.wire.max_bytes,
            input_index=index,
          ) {
          Ok(value) => {
            let relation_index = relation_inputs.length()
            relation_inputs.push(ManagedRelationInput(value))
            provider_inputs.push(PreparedRelation(relation_index))
            guard bind_physical_operation_input(
                installed.run,
                index,
                @execution.managed_relation_input_binding(value),
              )
              is Some(binding) else {
              return Err(Configuration(InputUnavailable))
            }
            completion_inputs.push(binding)
          }
          Err(issue) => return Err(Execution(issue))
        }
      CarrierOutput(output, material) => {
        guard @strategy.graph_task_owner(
            @strategy.captured_dag_graph(installed.run),
            task,
          )
          is Some(receiver) &&
          @strategy.graph_task_owner(
            @strategy.captured_dag_graph(installed.run),
            producers[index],
          )
          is Some(producer) else {
          return Err(Execution(ForeignCandidate))
        }
        let operation = @strategy.captured_next_managed_operation_input(
          installed.run,
          index,
        )
        let view_result = match operation {
          Some((consumer_step, operation_input)) =>
            @carrier_runtime.material_prepare_operation_view(
              material, receiver, consumer_step, operation_input, producer,
            )
          None =>
            @carrier_runtime.material_prepare_view(
              material, receiver, index, producer,
            )
        }
        let view = match view_result {
          Ok(value) => value
          Err(_) => return Err(Configuration(InputUnavailable))
        }
        let read = match
          @strategy.captured_carrier_managed_task_input(
            installed.run,
            task,
            output,
            @carrier_runtime.producer_view_read_reference(view),
            input_index=index,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Execution(issue))
        }
        provider_inputs.push(PreparedCarrier(view))
        completion_inputs.push(@execution.managed_carrier_input_binding(read))
      }
    }
  }

  guard @strategy.graph_task_owner(
      @strategy.captured_dag_graph(installed.run),
      task,
    )
    is Some(owner) else {
    return Err(Execution(ForeignCandidate))
  }
  guard local_task_interval_search_ceilings(installed.run, task)
    is Some(interval_search_ceilings) else {
    return Err(Configuration(InvalidLimits))
  }
  guard local_task_asof_search_ceilings(installed.run, task)
    is Some(asof_search_ceilings) else {
    return Err(Configuration(InvalidLimits))
  }
  guard local_task_sequence_match_ceilings(installed.run, task)
    is Some(sequence_match_ceilings) else {
    return Err(Configuration(InvalidLimits))
  }
  let graph = @strategy.captured_dag_graph(installed.run)
  let selected_operation = @strategy.graph_task_selected_step(graph, task)
    is Some(_) ||
    @strategy.graph_task_prefix_end(graph, task) is Some(_)
  let request_result = if selected_operation ||
    provider_inputs.any(input => input is PreparedCarrier(_)) ||
    relation_inputs.any(input => {
      input is OrdinaryRelationInput(_) || input is SuppliedRelationInput(_)
    }) {
    @connector.prepare_managed_fixed_compute_request_for_bindings(
      owner,
      completion_inputs,
      @local.local_module_managed_capacity(installed.implementation),
      obligations,
    )
  } else {
    @connector.prepare_managed_fixed_compute_request_for_owner(
      owner,
      relation_inputs.filter_map(input => {
        match input {
          ManagedRelationInput(value) => Some(value)
          OrdinaryRelationInput(_) | SuppliedRelationInput(_) => None
        }
      }),
      @local.local_module_managed_capacity(installed.implementation),
      obligations,
    )
  }
  let request = match request_result {
    Ok(value) => value
    Err(
      LogicalIdentityUnsupported
      | CommonFragmentUnsupported
      | UnsupportedInputShape
    ) => return Ok(None)
    Err(issue) => return Err(Configuration(issue))
  }
  let estimates = match
    local_managed_estimate_lines(
      installed,
      task,
      relation_inputs.map(input => {
        match input {
          OrdinaryRelationInput(value) =>
            @execution.producer_read_row_count(value)
          SuppliedRelationInput(value) =>
            @execution.supplied_relation_read_row_count(value)
          ManagedRelationInput(value) =>
            @execution.managed_producer_read_row_count(value)
        }
      }),
    ) {
    Ok(value) => value
    Err(_) => return Err(Configuration(InvalidLimits))
  }
  let (prepared, choice) = match
    @local.prepare_local_module_managed_compute_with_estimates(
      installed.implementation,
      local_task_slot(installed, task),
      request,
      estimates,
      interval_search_ceilings~,
      asof_search_ceilings~,
      sequence_match_ceilings~,
    ) {
    Ok(value) => value
    Err(
      Candidate(
        LogicalIdentityUnsupported
        | CommonFragmentUnsupported
        | UnsupportedInputShape
        | ComputeUnsupported
      )
    ) => return Ok(None)
    Err(issue) => return Err(Preparation(issue))
  }
  guard @connector.managed_fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) else {
    return Err(Configuration(InvalidLimits))
  }
  let provider = @local.local_module_managed_provider(
    installed.implementation,
    sequence,
  )
  // Managed Local work runs only through a bounded provider. A sequence no
  // provider accepts is not a managed candidate; there is no synchronous
  // whole-sequence fallback.
  if provider is None {
    return Ok(None)
  }
  let base = match provider {
    Some(value) => @local.managed_provider_capacity(value, sequence)
    None =>
      @execution.generated_sequence_capacity(
        sequence,
        @local.local_module_execution_limits(installed.implementation),
        @local.local_module_measurement_limits(installed.implementation),
      )
  }
  guard base is Some(base) &&
    @local.local_import_retention_capacity(imports) is Some(per_input) else {
    return Err(Configuration(InvalidLimits))
  }
  let count = relation_inputs.length().to_int64()
  if per_input > 0L && count > 9223372036854775807L / per_input {
    return Err(Configuration(InvalidLimits))
  }
  let imported = count * per_input
  if base.retained_bytes > 9223372036854775807L - base.execution_bytes ||
    imported > 9223372036854775807L - base.execution_bytes - base.retained_bytes ||
    (
      count > 0L &&
      imports.wire.max_bytes.to_int64() > 9223372036854775807L / count
    ) {
    return Err(Configuration(InvalidLimits))
  }
  guard local_task_join_output_ceilings(installed.run, task)
    is Some(join_output_ceilings) else {
    return Err(Configuration(InvalidLimits))
  }
  let aggregate_output_ceilings = []
  guard @strategy.captured_task_aggregate_output_count(installed.run, task)
    is Some(aggregate_count) else {
    return Err(Configuration(InvalidLimits))
  }
  for index in 0..<aggregate_count {
    guard @strategy.captured_task_aggregate_output_at(
        installed.run,
        task,
        index,
      )
      is Some(ceiling) else {
      return Err(Configuration(InvalidLimits))
    }
    aggregate_output_ceilings.push(ceiling)
  }
  let analytic_envelopes = []
  guard @strategy.captured_task_analytic_envelope_count(installed.run, task)
    is Some(analytic_count) else {
    return Err(Configuration(InvalidLimits))
  }
  for index in 0..<analytic_count {
    guard @strategy.captured_task_analytic_envelope_at(
        installed.run,
        task,
        index,
      )
      is Some(envelope) else {
      return Err(Configuration(InvalidLimits))
    }
    analytic_envelopes.push(envelope)
  }
  Ok(
    Some({
      run: installed.run,
      task,
      choice,
      prepared,
      sequence,
      provider,
      relation_inputs,
      provider_inputs,
      completion_inputs,
      execution: @local.local_module_execution_limits(installed.implementation),
      measurement: @local.local_module_measurement_limits(
        installed.implementation,
      ),
      imports,
      capacity: {
        transfer_bytes: count * imports.wire.max_bytes.to_int64(),
        retained_bytes: base.retained_bytes,
        // The checked output view, independent copy and imported input may
        // overlap until the copy commits and every bridge is closed.
        scratch_bytes: base.execution_bytes + base.retained_bytes + imported,
        execution_bytes: base.execution_bytes + base.retained_bytes + imported,
      },
      join_output_ceilings,
      interval_search_ceilings,
      asof_search_ceilings,
      sequence_match_ceilings,
      aggregate_output_ceilings,
      analytic_envelopes,
    }),
  )
}

///|
/// Exact duration selected by the installed Local cost policy. None means the
/// candidate remains unknown and must not enter automatic multi-Site ranking.
pub fn[T] local_managed_dispatch_duration(
  setup : LocalManagedDispatchConfiguration[T],
) -> Int64? {
  match
    @connector.managed_fixed_compute_candidate_duration(
      @connector.prepared_managed_compute_candidate(setup.prepared),
    ) {
    @cost.Complete(value) => Some(value)
    @cost.Unknown => None
  }
}

///|
/// True only when a registered family provider owns this execution. Ordinary
/// Relation-only work may remain on the established Local dispatcher.
pub fn[T] local_managed_dispatch_uses_provider(
  setup : LocalManagedDispatchConfiguration[T],
) -> Bool {
  setup.provider is Some(_)
}

///|
/// Safe Site sub-scope bounds for the selected managed execution. The Run
/// ledger remains the aggregate authority; these bounds prevent one Site from
/// consuming capacity assigned to another Site.
pub fn[T] local_managed_dispatch_site_capacity(
  setup : LocalManagedDispatchConfiguration[T],
) -> (Int64, Int64)? {
  Some((setup.capacity.retained_bytes, setup.capacity.execution_bytes))
}

///|
pub fn[T] start_local_managed_dispatch(
  setup : LocalManagedDispatchConfiguration[T],
) -> Result[LocalManagedDispatchOperations[T], LocalDispatchIssue] {
  let live = Ref(true)
  let settled = Ref(false)
  let disposed = Ref(false)
  let scratch_uses = Ref(0)
  let bridges : Array[Ref[@execution.ManagedProducerBridge[T]?]] = []
  let retained_imports : Array[Ref[@execution.CompletedOutputImport?]] = []
  let reads : Array[@execution.ProducerRead?] = []
  let ordinary : Ref[@execution.CompletedOutput?] = Ref(None)
  let retained : Ref[@execution.ManagedRetainedOutput[T]?] = Ref(None)
  let carrier : Ref[@carrier_runtime.Material?] = Ref(None)
  let carrier_completed : Ref[@execution.CarrierManagedCompletedOutput?] = Ref(
    None,
  )
  let provider_execution : Ref[@local.ManagedProviderExecution?] = Ref(None)
  let final_provider_work : Ref[Result[Int64, @local.ManagedProviderWorkIssue]] = Ref(
    Ok(0L),
  )
  // Stop confirmation permits cleanup; it is not cleanup confirmation. Keep
  // the task's scratch reservation until the installed provider actually
  // releases its owned state. Cache the existing owner's cumulative work
  // before dropping its last driver reference, without inventing cleanup work.
  let release_provider_scratch = fn() {
    match provider_execution.val {
      None => true
      Some(active) => {
        if !@local.managed_provider_stopped(active) ||
          !@local.cleanup_managed_provider(active).unwrap_or(false) {
          return false
        }
        final_provider_work.val = @local.managed_provider_cumulative_work(
          active,
        )
        provider_execution.val = None
        true
      }
    }
  }
  let retired_carriers : Array[@carrier_runtime.Material] = []
  let snapshot_attempted = Ref(false)
  let snapshot_ready = Ref(true)
  let snapshot_storage_released : Ref[(() -> Bool)?] = Ref(None)
  let relation_snapshot_cancel : Ref[(() -> Unit)?] = Ref(None)
  let execution_finished = Ref(false)
  let execution_failure : Ref[LocalDispatchIssue?] = Ref(None)
  let request = @connector.managed_fixed_compute_candidate_request(
    @connector.prepared_managed_compute_candidate(setup.prepared),
  )
  let relation_inputs = setup.relation_inputs
  let obligations = @connector.managed_fixed_compute_request_obligations(
    request,
  )
  let identity_requirements = @execution.managed_obligations_identities(
    obligations,
  ).filter(requirement => requirement.need is @execution.EstablishedBy(_))
  let finalization_started = Ref(false)
  let finalization_ready = Ref(false)
  let finalization_cancelled = Ref(false)
  let finalization_row = Ref(0)
  let finalization_identity = Ref(0)
  let finalization_issuer = Ref(0)
  let finalization_established = Ref(0)
  let finalization_deadline = Ref(0)
  let finalization_work_remaining = Ref(setup.execution.max_work)
  let finalization_payload : Ref[T?] = Ref(None)
  let finalization_available : Ref[(() -> Bool)?] = Ref(None)
  let finalization_values : Ref[@execution.ManagedOutputValues?] = Ref(None)
  let finalization_receipt : Ref[@execution.ManagedOutputValueReceipt?] = Ref(
    None,
  )
  let finalization_retention : Ref[
    @execution.ManagedOutputRetentionPort[
      (@execution.ManagedOutputValueReceipt, T, Int64, () -> Bool),
      T,
    ]?,
  ] = Ref(None)
  let finalization_material : Ref[@execution.ManagedRetainedOutput[T]?] = Ref(
    None,
  )
  let finalization_stream : Ref[@execution.CompletedOutputExport?] = Ref(None)
  let finalization_result_preparation : Ref[
    @execution.CompletedResultRelationExportPreparation?,
  ] = Ref(None)
  let finalization_cids : Array[String?] = Array::make(
    identity_requirements.length(),
    None,
  )
  let finalization_issuers : Array[@execution.ManagedIdentityIssuer[T]] = []
  let finalization_completed : Ref[@execution.ManagedCompletedOutput[T]?] = Ref(
    None,
  )
  let finalization_completion_preparation = @execution.generated_completion_preparation(
    setup.sequence,
  )
  let finalization_progress = fn() -> Int64 {
    (finalization_row.val +
    (if finalization_material.val is Some(_) { 1 } else { 0 }) +
    finalization_identity.val +
    finalization_issuer.val +
    (if finalization_completed.val is Some(_) { 1 } else { 0 }) +
    finalization_established.val +
    finalization_deadline.val).to_int64()
  }
  let cancel_finalization = fn() {
    finalization_cancelled.val = true
    if relation_snapshot_cancel.val is Some(cancel) {
      cancel()
      relation_snapshot_cancel.val = None
    }
    if finalization_completed.val is Some(completed) && !finalization_ready.val {
      @execution.revoke_unpublished_managed_completed_output(completed)
      |> ignore
    }
    if finalization_values.val is Some(values) {
      @execution.cancel_managed_output_values(values) |> ignore
    }
    if finalization_retention.val is Some(port) {
      @execution.cancel_managed_output_retention_port(port) |> ignore
    }
    if finalization_stream.val is Some(stream) {
      @execution.cancel_completed_output_export(stream)
    }
    if finalization_result_preparation.val is Some(preparation) {
      @execution.cancel_completed_result_relation_export(preparation) |> ignore
    }
  }
  let release_output_aliases = fn() {
    ordinary.val = None
    finalization_payload.val = None
    finalization_available.val = None
    finalization_receipt.val = None
    finalization_material.val = None
    finalization_completed.val = None
  }
  // These are the driver's charged scratch roots. Returned transfer handles
  // capture optional owners, so even a finished importer can be detached.
  // Do not clear shared result storage: successful material owns its receipt.
  let release_owned_scratch = fn() {
    if !(disposed.val ||
      (settled.val && (finalization_ready.val || carrier.val is Some(_)))) ||
      scratch_uses.val != 0 ||
      provider_execution.val is Some(_) {
      return
    }
    for handle in bridges {
      handle.val = None
    }
    for handle in retained_imports {
      handle.val = None
    }
    for index in 0..<reads.length() {
      reads[index] = None
    }
    // The checked-value copy is scratch. Its immutable receipt/index was
    // transferred to material; disposing this buffer does not revoke it.
    if finalization_values.val is Some(values) {
      @execution.dispose_managed_output_values_scratch(values)
    }
    finalization_values.val = None
    finalization_retention.val = None
    finalization_stream.val = None
    finalization_result_preparation.val = None
    // Execution disposal may precede the published output's final reader.
    // Only unpublished output can be dropped here; the existing released
    // notification retires published aliases after retention is confirmed.
    if disposed.val && retained.val is None {
      release_output_aliases()
    }
    for index in 0..<finalization_cids.length() {
      finalization_cids[index] = None
    }
    finalization_issuers.clear()
    finalization_issuers.shrink_to_fit()
  }
  let bound = match
    @connector.bind_prepared_managed_execution(
      setup.choice,
      setup.prepared,
      setup.capacity,
      setup.join_output_ceilings,
      fn(_sequence) {
        for input in relation_inputs {
          match input {
            OrdinaryRelationInput(read) =>
              if @execution.producer_read_has_cell_access(read) {
                reads.push(Some(read))
              } else {
                reads.push(None)
              }
            ManagedRelationInput(input) => {
              let bridge = match
                @execution.prepare_managed_producer_bridge(
                  input,
                  setup.imports.max_rows,
                  setup.imports.values,
                  setup.imports.wire.max_nodes,
                  setup.imports.wire.max_bytes,
                ) {
                Ok(value) => value
                Err(_) =>
                  return Err(@strategy.RunIssue::Compute(InputUnavailable))
              }
              bridges.push(Ref(Some(bridge)))
              reads.push(None)
            }
            SuppliedRelationInput(_) => reads.push(None)
          }
        }
        let operations : @connector.ManagedExecutionOperations[
          @strategy.RunIssue,
        ] = {
          cancel: fn() {
            live.val = false
            cancel_finalization()
            if provider_execution.val is Some(active) {
              @local.cancel_managed_provider(active) |> ignore
            }
            for handle in bridges {
              if handle.val is Some(bridge) {
                @execution.close_managed_producer_bridge(bridge)
              }
            }
            for handle in retained_imports {
              if handle.val is Some(importer) {
                @execution.cancel_completed_output_import(importer) |> ignore
              }
            }
          },
          dispose: fn() {
            live.val = false
            cancel_finalization()
            if provider_execution.val is Some(active) {
              @local.cancel_managed_provider(active) |> ignore
            }
            for handle in bridges {
              if handle.val is Some(bridge) {
                @execution.close_managed_producer_bridge(bridge)
              }
            }
            for handle in retained_imports {
              if handle.val is Some(importer) {
                @execution.cancel_completed_output_import(importer) |> ignore
              }
            }
            disposed.val = true
            release_owned_scratch()
          },
          settled: fn() {
            settled.val = true
            // Preserve the existing one stopped-provider cleanup attempt.
            // Pending/error keeps both its owner and all scratch responsibility.
            if live.val && (ordinary.val is Some(_) || carrier.val is Some(_)) {
              release_provider_scratch() |> ignore
            }
            release_owned_scratch()
          },
          // Observation only: cleanup never runs from this witness.
          scratch_released: fn() {
            (
              disposed.val ||
              (settled.val && finalization_ready.val) ||
              (settled.val && carrier.val is Some(_))
            ) &&
            scratch_uses.val == 0 &&
            provider_execution.val is None &&
            bridges.all(handle => handle.val is None) &&
            retained_imports.all(handle => handle.val is None) &&
            reads.all(read => read is None) &&
            (
              !disposed.val ||
              retained.val is Some(_) ||
              (
                ordinary.val is None &&
                finalization_payload.val is None &&
                finalization_available.val is None &&
                finalization_receipt.val is None &&
                finalization_material.val is None &&
                finalization_completed.val is None
              )
            ) &&
            finalization_values.val is None &&
            finalization_retention.val is None &&
            finalization_stream.val is None &&
            finalization_result_preparation.val is None &&
            finalization_cids.all(cid => cid is None) &&
            finalization_issuers.is_empty()
          },
          retention_released: fn() {
            let relation_released = retained.val is None ||
              retained.val
              .map(value => {
                @execution.managed_retained_output_payload(value) is None
              })
              .unwrap()
            let carrier_released = carrier.val is None ||
              carrier.val
              .map(value => !@carrier_runtime.material_cleanup_pending(value))
              .unwrap()
            let mut old_carriers_released = true
            for material in retired_carriers {
              if @carrier_runtime.material_cleanup_pending(material) {
                old_carriers_released = false
              }
            }
            relation_released &&
            carrier_released &&
            old_carriers_released &&
            snapshot_storage_released.val.map(check => check()).unwrap_or(true)
          },
          released: release_output_aliases,
          ready: fn() {
            if live.val && settled.val && !disposed.val {
              Ok(())
            } else {
              Err(@strategy.RunIssue::NotReady)
            }
          },
        }
        Ok(((), operations))
      },
      aggregate_output_ceilings=setup.aggregate_output_ceilings,
      analytic_envelopes=setup.analytic_envelopes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Configuration(issue))
  }
  let execution = match
    @strategy.start_captured_managed_execution(setup.run, setup.task, bound) {
    Ok((_, value)) => value
    Err(issue) => return Err(Execution(issue))
  }
  guard @strategy.task_execution_managed_attempt(setup.run, execution)
    is Some(execution_attempt) else {
    return Err(Execution(ForeignCandidate))
  }
  guard @strategy.task_execution_numeric_reduction_count(setup.run, execution)
    is Some(numeric_count) else {
    return Err(Execution(ForeignCandidate))
  }
  let numeric = local_task_numeric_execution(
    setup.run,
    execution,
    numeric_count,
  )
  let transfers = []
  let mut bridge_index = 0
  for read_index, input in relation_inputs {
    guard input is ManagedRelationInput(managed) else { continue }
    let handle = bridges[bridge_index]
    bridge_index += 1
    transfers.push(LocalManagedInputTransfer::{
      input: managed,
      append: fn(row) {
        guard handle.val is Some(bridge) && live.val else {
          return Err(Configuration(InputUnavailable))
        }
        let bytes = match
          managed_row_transfer_bytes(row, setup.imports.wire.max_bytes) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        match
          @strategy.charge_task_execution_transfer(setup.run, execution, bytes) {
          Err(issue) => Err(Execution(Physical(issue)))
          Ok(_) =>
            @execution.append_managed_producer_bridge_wire(
              bridge,
              row,
              setup.imports.row,
            ).map_err(_ => Configuration(InputUnavailable))
        }
      },
      finish: fn() {
        guard handle.val is Some(bridge) && live.val else {
          return Err(Configuration(InputUnavailable))
        }
        match
          @execution.finish_managed_producer_bridge(
            bridge,
            setup.imports.wire.max_nodes,
            setup.imports.wire.max_bytes,
          ) {
          Ok(value) => {
            reads[read_index] = Some(value)
            Ok(())
          }
          Err(_) => Err(Configuration(InputUnavailable))
        }
      },
    })
  }
  let retained_transfers : Array[LocalInputTransfer] = []
  for read_index, input in relation_inputs {
    guard input is OrdinaryRelationInput(read) &&
      !@execution.producer_read_has_cell_access(read) &&
      @execution.producer_read_retained_material(read) is Some(material) else {
      continue
    }
    let position = read_index
    let importer : Ref[@execution.CompletedOutputImport?] = Ref(None)
    retained_imports.push(importer)
    retained_transfers.push({
      material,
      input: read,
      frames: {
        maxBytes: setup.imports.wire.max_bytes,
        maxRows: setup.imports.max_rows,
        maxRowBytes: setup.imports.row.max_bytes,
        maxDepth: setup.imports.row.max_depth,
        maxFrameBytes: setup.imports.max_batch_bytes,
      },
      begin: fn() {
        guard live.val && importer.val is None else {
          return Err(Configuration(InputUnavailable))
        }
        let prepared = match
          @execution.prepare_producer_output_import(
            read,
            setup.imports.max_rows,
            setup.imports.values,
            setup.imports.wire,
            setup.imports.max_batch_bytes,
          ) {
          Ok(value) => value
          Err(_) => return Err(Configuration(InputUnavailable))
        }
        importer.val = Some(prepared)
        Ok(())
      },
      charge: bytes => {
        @strategy.charge_task_execution_transfer(setup.run, execution, bytes).map_err(issue => {
            Execution(Physical(issue))
          },
        )
      },
      append: row => {
        guard importer.val is Some(active) && live.val else {
          return Err(Configuration(InputUnavailable))
        }
        @execution.append_completed_output_import_wire(
          active,
          row,
          setup.imports.row,
        ).map_err(_ => Configuration(InputUnavailable))
      },
      finish: fn() {
        guard importer.val is Some(active) && live.val else {
          return Err(Configuration(InputUnavailable))
        }
        let output = match @execution.finish_completed_output_import(active) {
          Ok(value) => value
          Err(_) => return Err(Configuration(InputUnavailable))
        }
        let rebound = match
          @execution.rebind_producer_representation(read, output) {
          Ok(value) => value
          Err(_) => return Err(Configuration(InputUnavailable))
        }
        guard @execution.producer_read_has_cell_access(rebound) else {
          return Err(Configuration(InputUnavailable))
        }
        reads[position] = Some(rebound)
        Ok(())
      },
    })
  }
  let output_target = @strategy.captured_task_target(setup.run, setup.task)
  let advance_once = fn(
    quantum : Int,
  ) -> Result[LocalManagedAdvance, LocalDispatchIssue] {
    if quantum <= 0 {
      return Err(Configuration(InvalidLimits))
    }
    if execution_finished.val {
      return Ok({ complete: true, progress: 0L, work: 0L, })
    }
    for index, input in relation_inputs {
      if !(input is SuppliedRelationInput(_)) && reads[index] is None {
        return Err(Configuration(InputUnavailable))
      }
    }
    // Disposal prevents starting work, but an already-started bounded
    // provider must still receive one final advance after cancellation so it
    // can report an actual stop. Cleanup cannot substitute for that report.
    if (!live.val || disposed.val) && provider_execution.val is None {
      return Err(Configuration(InputUnavailable))
    }
    match setup.provider {
      Some(provider) => {
        let active = match provider_execution.val {
          Some(value) => value
          None => {
            let constrained = match
              @local.constrain_local_managed_sequence(
                setup.sequence,
                join_output_ceilings=setup.join_output_ceilings,
                interval_search_ceilings=setup.interval_search_ceilings,
                asof_search_ceilings=setup.asof_search_ceilings,
                sequence_match_ceilings=setup.sequence_match_ceilings,
                aggregate_output_ceilings=setup.aggregate_output_ceilings,
                analytic_envelopes=setup.analytic_envelopes,
                numeric~,
              ) {
              Ok(value) => value
              Err(issue) => {
                execution_finished.val = true
                return Err(Configuration(issue))
              }
            }
            guard local_task_constrain_traversal(
                setup.run,
                setup.task,
                constrained,
              )
              is Some(constrained) else {
              execution_finished.val = true
              return Err(Configuration(InputUnavailable))
            }
            let started = match
              @local.start_managed_provider_with_inputs_and_execution(
                provider,
                constrained,
                setup.provider_inputs.map(input => {
                  match input {
                    PreparedRelation(index) =>
                      @local.managed_provider_relation_input(
                        reads[index].unwrap(),
                      )
                    PreparedSupplied(read) =>
                      @local.managed_provider_supplied_relation_input(read)
                    PreparedCarrier(view) =>
                      @local.managed_provider_carrier_input(view)
                  }
                }),
                @connector.managed_fixed_compute_request_capacity(request).max_rows,
                @connector.managed_fixed_compute_request_capacity(request).max_value_bytes,
                setup.execution,
                numeric~,
              ) {
              Ok(value) => value
              Err(issue) => return Err(Configuration(issue))
            }
            provider_execution.val = Some(started)
            started
          }
        }
        let poll = @local.advance_managed_provider(active, quantum)
        if @local.managed_provider_cumulative_work(active) is Err(_) {
          live.val = false
          return Err(Configuration(InvalidLimits))
        }
        match poll {
          Err(issue) => Err(Configuration(issue))
          Ok(@local.Continue(progress~, work~)) =>
            if progress < 0L || work <= 0L || work > quantum.to_int64() {
              Err(Configuration(InvalidLimits))
            } else {
              Ok({ complete: false, progress, work, })
            }
          Ok(@local.Complete(output, progress~, work~)) => {
            if progress < 0L || work < 0L || work > quantum.to_int64() {
              return Err(Configuration(InvalidLimits))
            }
            // As after synchronous computation, every selected numeric
            // reduction slot of the task must be sealed before publication.
            if numeric_count > 0 &&
              !@strategy.seal_task_numeric_reductions(setup.run, execution) {
              execution_finished.val = true
              return Err(Execution(ForeignCandidate))
            }
            ordinary.val = Some(output)
            execution_finished.val = true
            for handle in bridges {
              if handle.val is Some(bridge) {
                @execution.close_managed_producer_bridge(bridge)
              }
            }
            Ok({ complete: true, progress, work, })
          }
          Ok(@local.CarrierComplete(material, progress~, work~)) => {
            if progress < 0L ||
              work < 0L ||
              work > quantum.to_int64() ||
              !@carrier_runtime.material_available(material) {
              return Err(Configuration(InvalidLimits))
            }
            carrier.val = Some(material)
            execution_finished.val = true
            for handle in bridges {
              if handle.val is Some(bridge) {
                @execution.close_managed_producer_bridge(bridge)
              }
            }
            Ok({ complete: true, progress, work, })
          }
          Ok(@local.Failed(issue, progress~, work~)) => {
            if progress < 0L || work < 0L || work > quantum.to_int64() {
              return Err(Configuration(InvalidLimits))
            }
            execution_finished.val = true
            Err(Configuration(issue))
          }
          Ok(@local.Stopped(progress~, work~)) => {
            if progress < 0L || work < 0L || work > quantum.to_int64() {
              return Err(Configuration(InvalidLimits))
            }
            execution_finished.val = true
            Err(Execution(Stopped))
          }
        }
      }
      // Unreachable: preparation declines providerless sequences.
      None => {
        execution_finished.val = true
        Err(Configuration(ComputeUnsupported))
      }
    }
  }
  let advance = fn(
    quantum : Int,
  ) -> Result[LocalManagedAdvance, LocalDispatchIssue] {
    if execution_failure.val is Some(issue) {
      return Err(issue)
    }
    if execution_finished.val && ordinary.val is None && carrier.val is None {
      return Err(Configuration(InputUnavailable))
    }
    let result = advance_once(quantum)
    if result is Err(issue) && execution_finished.val {
      execution_failure.val = Some(issue)
    }
    result
  }
  let operations : LocalManagedDispatchOperations[T] = {
    inputs: transfers,
    retained_inputs: retained_transfers,
    execute: fn() {
      if execution_failure.val is Some(issue) {
        return Err(issue)
      }
      while !execution_finished.val {
        match advance(1024) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      if ordinary.val is None && carrier.val is None {
        return Err(Configuration(InputUnavailable))
      }
      Ok(())
    },
    advance,
    cumulative_provider_work: fn() {
      match provider_execution.val {
        Some(active) => @local.managed_provider_cumulative_work(active)
        None => final_provider_work.val
      }
    },
    request_cancel: fn() {
      let changed = live.val
      live.val = false
      cancel_finalization()
      @strategy.close_task_execution(setup.run, execution)
      changed
    },
    execution_stopped: fn() {
      let compute_stopped = match provider_execution.val {
        Some(active) => @local.managed_provider_stopped(active)
        None => execution_finished.val || !live.val
      }
      compute_stopped &&
      (
        !finalization_started.val ||
        finalization_ready.val ||
        finalization_cancelled.val
      )
    },
    prepare_finalization: fn(payload, storage_bytes, available) {
      if finalization_started.val ||
        !execution_finished.val ||
        !snapshot_ready.val ||
        finalization_cancelled.val {
        return Err(Configuration(InvalidLimits))
      }
      guard ordinary.val is Some(_) &&
        output_target is Some(target) &&
        storage_bytes == setup.capacity.retained_bytes &&
        available() else {
        return Err(Configuration(InvalidLimits))
      }
      let values = match
        @execution.prepare_managed_output_values(
          @connector.managed_fixed_compute_request_owner(request),
          target,
          @connector.managed_fixed_compute_request_capacity(request).max_rows,
          setup.execution.rows.output_values,
          @connector.managed_fixed_compute_request_capacity(request).max_value_bytes,
          setup.measurement,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ManagedValues(issue))
      }
      let retention = match
        @execution.prepare_managed_output_retention_port(values, fn(
          proof : (@execution.ManagedOutputValueReceipt, T, Int64, () -> Bool),
        ) {
          let (receipt, proof_payload, bytes, proof_available) = proof
          if finalization_receipt.val is Some(expected) &&
            physical_equal(receipt, expected) &&
            bytes == storage_bytes &&
            proof_available() &&
            available() {
            Some((receipt, proof_payload, bytes, proof_available))
          } else {
            None
          }
        }) {
        Ok(value) => value
        Err(_) => return Err(Configuration(InvalidLimits))
      }
      finalization_payload.val = Some(payload)
      finalization_available.val = Some(available)
      finalization_values.val = Some(values)
      finalization_retention.val = Some(retention)
      finalization_started.val = true
      Ok(())
    },
    advance_finalization: fn(quantum) {
      if quantum <= 0 ||
        !finalization_started.val ||
        finalization_ready.val ||
        finalization_cancelled.val {
        return Err(Configuration(InvalidLimits))
      }
      guard ordinary.val is Some(output) &&
        output_target is Some(target) &&
        finalization_values.val is Some(values) &&
        finalization_available.val is Some(available) else {
        return Err(Configuration(InvalidLimits))
      }
      let mut work = 0
      let rows = @execution.completed_row_count(output)
      while work < quantum && finalization_row.val < rows {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let row = finalization_row.val
        match
          @execution.append_completed_projection_managed_values(
            values, output, row,
          ) {
          Ok(_) => ()
          Err(@execution.Admission(@execution.InvalidCheckedRow)) =>
            match
              @execution.append_completed_projection_managed_wire(
                values,
                output,
                row,
                setup.imports.wire,
                setup.imports.row,
              ) {
              Ok(_) => ()
              Err(issue) => return Err(ManagedValues(issue))
            }
          Err(issue) => return Err(ManagedValues(issue))
        }
        finalization_row.val += 1
        finalization_work_remaining.val -= 1
        work += 1
      }
      if work == quantum {
        return Ok({
          complete: false,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      if finalization_material.val is None {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let receipt = match @execution.finish_managed_output_values(values) {
          Ok(value) => value
          // The finished output exceeds its value limits: keep the cause.
          Err(issue) => return Err(ManagedValues(issue))
        }
        finalization_receipt.val = Some(receipt)
        guard finalization_payload.val is Some(payload) else {
          return Err(Configuration(InvalidLimits))
        }
        guard finalization_retention.val is Some(retention) else {
          return Err(Configuration(InvalidLimits))
        }
        let material = match
          @execution.retain_managed_output(
            retention,
            (receipt, payload, setup.capacity.retained_bytes, available),
          ) {
          Ok(value) => value
          Err(issue) => return Err(ManagedRetention(issue))
        }
        finalization_material.val = Some(material)
        finalization_work_remaining.val -= 1
        work += 1
      }
      if work == quantum {
        return Ok({
          complete: false,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      while work < quantum &&
            finalization_identity.val < identity_requirements.length() {
        let index = finalization_identity.val
        let requirement = identity_requirements[index]
        if finalization_stream.val is None {
          match
            (requirement.domain, requirement.subject, requirement.occurrence) {
            (@execution.OrderedRows, @execution.TaskOutput, None) => {
              let stream = match
                @execution.prepare_completed_output_export(
                  output,
                  setup.imports.max_rows,
                  setup.imports.values,
                  setup.imports.wire,
                  setup.imports.max_batch_bytes,
                ) {
                Ok(value) => value
                Err(issue) => return Err(IdentityExport(issue))
              }
              finalization_stream.val = Some(stream)
            }
            (@execution.LogicalRelation, @execution.NamedResult, Some(result)) => {
              if finalization_result_preparation.val is None {
                let preparation = match
                  @execution.start_completed_result_relation_export(
                    output,
                    result,
                    {
                      max_fields: setup.imports.wire.max_columns,
                      max_mapping_work: setup.imports.wire.max_order_work,
                      max_order_work: setup.execution.max_work,
                      max_workspace_entries: setup.imports.max_rows,
                    },
                    setup.imports.max_rows,
                    setup.imports.values,
                    setup.imports.wire,
                    setup.imports.wire,
                    {
                      max_fields: setup.imports.wire.max_columns,
                      max_bytes: setup.imports.wire.max_bytes,
                      max_nodes: setup.imports.wire.max_nodes,
                      max_depth: setup.imports.wire.max_depth,
                    },
                    setup.imports.max_batch_bytes,
                  ) {
                  Ok(value) => value
                  Err(issue) => return Err(IdentityExport(issue))
                }
                finalization_result_preparation.val = Some(preparation)
              }
              let preparation = finalization_result_preparation.val.unwrap()
              let remaining = Int::min(
                quantum - work,
                finalization_work_remaining.val,
              )
              if remaining < 1 {
                return Err(Configuration(InvalidLimits))
              }
              let (ready, used) = match
                @execution.advance_completed_result_relation_export(
                  preparation, remaining,
                ) {
                Ok(value) => value
                Err(issue) => return Err(IdentityExport(issue))
              }
              finalization_work_remaining.val -= used
              work += used
              if !ready {
                return Ok({
                  complete: false,
                  progress: finalization_progress(),
                  work: work.to_int64(),
                })
              }
              let stream = match
                @execution.finish_completed_result_relation_export_preparation(
                  preparation,
                ) {
                Ok(value) => value
                Err(issue) => return Err(IdentityExport(issue))
              }
              finalization_result_preparation.val = None
              finalization_stream.val = Some(stream)
            }
            _ => return Err(Configuration(LogicalIdentityUnsupported))
          }
        }
        guard finalization_stream.val is Some(stream) else {
          return Err(Configuration(LogicalIdentityUnsupported))
        }
        if work == quantum {
          break
        }
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        match @execution.next_completed_output_export(stream) {
          Ok(Some(_)) => {
            finalization_work_remaining.val -= 1
            work += 1
          }
          Ok(None) => {
            let cid = match requirement.domain {
              @execution.OrderedRows => {
                let receipt = match
                  @execution.finish_completed_output_export(stream) {
                  Ok((value, _)) => value
                  Err(issue) => return Err(IdentityExport(issue))
                }
                let identity = @execution.output_stream_identity(
                    @execution.completed_export_content(receipt),
                  ).0
                @execution.cancel_completed_export_receipt(receipt)
                identity
              }
              @execution.LogicalRelation => {
                let receipt = match
                  @execution.finish_completed_relation_export(stream) {
                  Ok((value, _)) => value
                  Err(issue) => return Err(IdentityExport(issue))
                }
                let identity = @execution.logical_relation_cid(
                  @execution.completed_relation_export_identity(receipt),
                )
                @execution.cancel_completed_relation_export_receipt(receipt)
                identity
              }
              _ => return Err(Configuration(LogicalIdentityUnsupported))
            }
            finalization_cids[index] = Some(cid)
            finalization_stream.val = None
            finalization_identity.val += 1
            finalization_work_remaining.val -= 1
            work += 1
          }
          Err(issue) => return Err(IdentityExport(issue))
        }
      }
      if finalization_identity.val < identity_requirements.length() {
        return Ok({
          complete: false,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      guard finalization_material.val is Some(material) else {
        return Err(Configuration(InvalidLimits))
      }
      while work < quantum &&
            finalization_issuer.val < identity_requirements.length() {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let index = finalization_issuer.val
        let requirement = identity_requirements[index]
        let canonical_contract_cid = match requirement.domain {
          @execution.OrderedRows =>
            @execution.ordered_rows_canonical_contract_cid()
          @execution.LogicalRelation =>
            @execution.logical_relation_canonical_contract_cid()
          _ => return Err(Configuration(LogicalIdentityUnsupported))
        }
        let capability = match
          @execution.register_managed_identity_issuance_capability(
            requirement.domain,
            requirement.subject,
            requirement.occurrence,
            canonical_contract_cid,
          ) {
          Ok(value) => value
          Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
        }
        let permit = match
          @execution.authorize_managed_identity_execution_attempt(
            capability, execution_attempt, finalization_completion_preparation, requirement,
          ) {
          Ok(value) => value
          Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
        }
        let cid = finalization_cids[index]
        let issuer = match
          @execution.try_bind_managed_identity_issuer(permit, material, fn(
            source,
          ) {
            if physical_equal(source, material) && available() {
              cid
            } else {
              None
            }
          }) {
          Ok(value) => value
          Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
        }
        finalization_issuers.push(issuer)
        finalization_issuer.val += 1
        finalization_work_remaining.val -= 1
        work += 1
      }
      if finalization_issuer.val < identity_requirements.length() ||
        work == quantum {
        return Ok({
          complete: false,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      if finalization_completed.val is None {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let completion = match
          @execution.prepare_managed_completion_port(
            @execution.selected_managed_execution_profile(),
            finalization_completion_preparation,
            target,
            setup.imports.wire.max_nodes,
            setup.imports.wire.max_bytes,
            fn(candidate : @execution.ManagedRetainedOutput[T]) {
              if physical_equal(candidate, material) {
                Some(material)
              } else {
                None
              }
            },
            common_inputs=setup.completion_inputs,
            obligations~,
            identity_issuers=finalization_issuers,
            attempt=execution_attempt,
          ) {
          Ok(value) => value
          Err(issue) => return Err(ManagedCompletion(issue))
        }
        let completed = match
          @execution.complete_managed_output(completion, material) {
          Ok(value) => value
          Err(_) => return Err(Configuration(InvalidLimits))
        }
        finalization_completed.val = Some(completed)
        finalization_work_remaining.val -= 1
        work += 1
      }
      if work == quantum {
        return Ok({
          complete: false,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      guard finalization_completed.val is Some(completed) else {
        return Err(Configuration(InvalidLimits))
      }
      while work < quantum &&
            finalization_established.val < identity_requirements.length() {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let requirement = identity_requirements[finalization_established.val]
        match
          @execution.establish_managed_completed_identity_requirement(
            completed, requirement,
          ) {
          Ok(_) => ()
          Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
        }
        finalization_established.val += 1
        finalization_work_remaining.val -= 1
        work += 1
      }
      if finalization_established.val < identity_requirements.length() ||
        work == quantum {
        return Ok({
          complete: false,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      let deadlines = [
        @execution.BeforeCidOperation,
        @execution.BeforePublication,
        @execution.BeforeDiscard,
      ]
      while work < quantum && finalization_deadline.val < deadlines.length() {
        if finalization_work_remaining.val < 1 {
          return Err(Configuration(InvalidLimits))
        }
        let deadline = deadlines[finalization_deadline.val]
        if !@execution.managed_completed_deadline_satisfied(completed, deadline) {
          return Err(Configuration(LogicalIdentityUnsupported))
        }
        finalization_deadline.val += 1
        finalization_work_remaining.val -= 1
        work += 1
      }
      if finalization_deadline.val < deadlines.length() {
        return Ok({
          complete: false,
          progress: finalization_progress(),
          work: work.to_int64(),
        })
      }
      finalization_ready.val = true
      Ok({
        complete: true,
        progress: finalization_progress(),
        work: work.to_int64(),
      })
    },
    settle: fn() {
      let failed_or_stopped = !live.val ||
        (execution_finished.val && ordinary.val is None && carrier.val is None)
      let relation_pending = ordinary.val is Some(_) &&
        !finalization_ready.val &&
        !finalization_cancelled.val &&
        !failed_or_stopped
      if relation_pending ||
        (!failed_or_stopped && carrier.val is Some(_) && !snapshot_ready.val) {
        return Err(Configuration(InvalidLimits))
      }
      @strategy.settle_task_execution(setup.run, execution, true).map_err(issue => {
        Execution(Physical(issue))
      })
    },
    complete: fn(payload, storage_bytes, available) {
      guard finalization_ready.val &&
        finalization_payload.val is Some(expected_payload) &&
        physical_equal(payload, expected_payload) &&
        storage_bytes == setup.capacity.retained_bytes &&
        finalization_available.val is Some(expected_available) &&
        expected_available() &&
        available() &&
        finalization_material.val is Some(material) &&
        finalization_completed.val is Some(completed) else {
        return Err(Configuration(InvalidLimits))
      }
      let allocation = match
        @strategy.retain_task_execution_allocation(
          setup.run,
          execution,
          storage_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Execution(Physical(issue)))
      }
      match
        @strategy.complete_managed_task_execution_with_inputs(
          setup.run,
          execution,
          completed,
          allocation~,
          managed_inputs=setup.completion_inputs,
        ) {
        Err(issue) => {
          @strategy.release_task_execution_allocation(allocation) |> ignore
          Err(Execution(issue))
        }
        Ok(_) => {
          retained.val = Some(material)
          Ok(completed)
        }
      }
    },
    complete_carrier: fn() {
      guard execution_finished.val &&
        ordinary.val is None &&
        carrier.val is Some(material) &&
        carrier_completed.val is None &&
        snapshot_ready.val &&
        output_target is Some(target) &&
        @carrier_runtime.material_available(material) &&
        @carrier_runtime.material_storage_bytes(material) is Some(storage_bytes) &&
        storage_bytes >= 0L &&
        storage_bytes <= setup.capacity.retained_bytes &&
        !@execution.managed_obligations_require_logical_identity(obligations) else {
        return Err(Configuration(InvalidLimits))
      }
      let common_inputs = setup.completion_inputs
      let reference = @carrier_runtime.material_reference(material)
      let completion = match
        @execution.prepare_carrier_managed_completion_port_with_inputs(
          @execution.selected_managed_execution_profile(),
          @execution.generated_completion_preparation(setup.sequence),
          target,
          setup.imports.wire.max_nodes,
          setup.imports.wire.max_bytes,
          (_ : Unit) => {
            if @carrier_runtime.material_available(material) {
              Some(reference)
            } else {
              None
            }
          },
          inputs=common_inputs,
          obligations~,
          attempt=execution_attempt,
        ) {
        Ok(value) => value
        Err(issue) => return Err(ManagedCompletion(issue))
      }
      let completed = match
        @execution.complete_carrier_managed_output(completion, ()) {
        Ok(value) => value
        Err(issue) => return Err(ManagedCompletion(issue))
      }
      let allocation = match
        @strategy.retain_task_execution_allocation(
          setup.run,
          execution,
          storage_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Execution(Physical(issue)))
      }
      match
        @strategy.complete_carrier_managed_task_execution_with_inputs(
          setup.run,
          execution,
          completed,
          allocation~,
          managed_inputs=common_inputs,
        ) {
        Err(issue) => {
          @strategy.release_task_execution_allocation(allocation) |> ignore
          Err(Execution(issue))
        }
        Ok(_) => {
          carrier_completed.val = Some(completed)
          Ok(completed)
        }
      }
    },
    output_rows: fn() {
      ordinary.val.map(@execution.completed_row_count).unwrap_or(0)
    },
    output_row: fn(row) {
      guard ordinary.val is Some(output) else {
        return Err(Configuration(InputUnavailable))
      }
      @execution.completed_output_row_wire(
        output,
        row,
        setup.imports.row.max_bytes,
        setup.imports.row.max_nodes,
        setup.imports.row.max_depth,
      ).map_err(_ => Configuration(InputUnavailable))
    },
    material: fn() { retained.val },
    carrier_material: fn() { carrier.val },
    prepare_relation_snapshot: fn(storage_released) {
      // Retain checked Graph row bridges, sparse selections, derived and
      // grouped rows, and node traversals. Operation keys come from the
      // checked owner, not caller-supplied names.
      let prepared = @lower.bound_preparation(
        @execution.generated_sequence_owner(setup.sequence),
      )
      let mut graph_rows = false
      for
        position in 0..<@execution.generated_sequence_step_count(setup.sequence) {
        if @execution.generated_sequence_step_index_at(setup.sequence, position).bind(index => {
              @lower.node_at(prepared, index)
            },
          )
          is Some(node) {
          let key = @lower.operation(node)
          if key == "BRIDGE.graph.to_node_rows" ||
            key == "BRIDGE.graph.to_edge_rows" {
            graph_rows = true
          } else if key == "REL.derive" ||
            key == "REL.distinct" ||
            key == "REL.groupBy" {
            graph_rows = true
          } else if (
              key == "REL.where" ||
              key == "REL.orderByStable" ||
              key == "REL.limit"
            ) &&
            @lower.preparation_schema_at(
              prepared,
              @pipeline.Step(
                @execution.generated_sequence_step_index_at(
                  setup.sequence,
                  position,
                ).unwrap(),
              ),
            )
            is Some(schema) &&
            !@schema.all_fields_required(schema) {
            graph_rows = true
          } else if @lower.sequence_step(
              @execution.generated_prepared_sequence(setup.sequence),
              @execution.generated_sequence_step_index_at(
                setup.sequence,
                position,
              ).unwrap(),
            )
            is Some(@lower.GraphTraverseStep(traverse)) &&
            !@lower.graph_traverse_emits_paths(traverse) {
            graph_rows = true
          }
        }
      }
      if !graph_rows {
        return Ok(None)
      }
      guard live.val &&
        execution_finished.val &&
        execution_failure.val is None &&
        !snapshot_attempted.val &&
        !finalization_started.val &&
        ordinary.val is Some(output) &&
        carrier.val is None &&
        provider_execution.val is Some(active) else {
        return Err(Configuration(InvalidLimits))
      }
      let maximum_bytes = Int::min(
        setup.imports.wire.max_bytes,
        if setup.capacity.retained_bytes > 2147483647L {
          2147483647
        } else {
          setup.capacity.retained_bytes.to_int()
        },
      )
      if maximum_bytes < 2 {
        return Err(Configuration(InvalidLimits))
      }
      let wire = { ..setup.imports.wire, max_bytes: maximum_bytes, }
      let frames : LocalInputFrames = {
        maxBytes: maximum_bytes,
        maxRows: setup.imports.max_rows,
        maxRowBytes: setup.imports.row.max_bytes,
        maxDepth: setup.imports.row.max_depth,
        maxFrameBytes: Int::min(maximum_bytes, setup.imports.max_batch_bytes),
      }
      let exporting = match
        @execution.prepare_completed_output_export(
          output,
          setup.imports.max_rows,
          setup.imports.values,
          wire,
          frames.maxFrameBytes,
        ) {
        Ok(value) => value
        Err(_) => return Err(Configuration(InputUnavailable))
      }
      let stream = Ref(Some(exporting))
      let receipt : Ref[@execution.CompletedOutputExportReceipt?] = Ref(None)
      let stored : Ref[@execution.CompletedOutput?] = Ref(None)
      let importing : Ref[@execution.CompletedOutputImport?] = Ref(None)
      let restored : Ref[@execution.CompletedOutput?] = Ref(None)
      let phase = Ref(SnapshotPhase::Saving)
      let remaining = Ref(0L)
      match @local.managed_provider_cumulative_work(active) {
        Ok(work) if work >= 0L && work <= setup.execution.max_work.to_int64() =>
          remaining.val = setup.execution.max_work.to_int64() - work
        _ => return Err(Configuration(InvalidLimits))
      }
      // Each conversion advance/row is charged once by this same task owner.
      // Typed value traversal retains its existing admission/work limits too.
      let charge = fn() -> Result[Unit, LocalDispatchIssue] {
        if !live.val || execution_failure.val is Some(_) || remaining.val < 1L {
          execution_failure.val = Some(Configuration(InvalidLimits))
          return Err(Configuration(InvalidLimits))
        }
        remaining.val -= 1L
        @local.managed_provider_record_handoff_work(active, 1L).map_err(_ => {
          Configuration(InvalidLimits)
        })
      }
      snapshot_attempted.val = true
      snapshot_ready.val = false
      snapshot_storage_released.val = Some(storage_released)
      relation_snapshot_cancel.val = Some(fn() {
        if stream.val is Some(value) {
          @execution.cancel_completed_output_export(value)
        }
        if receipt.val is Some(value) {
          @execution.cancel_completed_export_receipt(value)
        }
        if importing.val is Some(value) {
          @execution.cancel_completed_output_import(value) |> ignore
        }
        stream.val = None
        receipt.val = None
        stored.val = None
        importing.val = None
        restored.val = None
        phase.val = Failed
      })
      Ok(
        Some({
          key: "relation-task-" + setup.task.to_string(),
          frames,
          next: () => {
            if phase.val == Saved {
              return Ok(None)
            }
            guard phase.val == Saving && stream.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            if charge() is Err(issue) {
              return Err(issue)
            }
            match @execution.next_completed_output_export(value) {
              Ok(Some(part)) => Ok(Some(part))
              Ok(None) => {
                let (finished, tail) = match
                  @execution.finish_completed_output_export(value) {
                  Ok(result) => result
                  Err(_) => return Err(Configuration(InputUnavailable))
                }
                receipt.val = Some(finished)
                stream.val = None
                phase.val = Saved
                Ok(Some(tail))
              }
              Err(_) => Err(Configuration(InputUnavailable))
            }
          },
          content: () => {
            guard phase.val == Saved && receipt.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            let (cid, bytes, _, _) = @execution.output_stream_identity(
              @execution.completed_export_content(value),
            )
            Ok({ cid, bytes, })
          },
          release_source: (cid, available) => {
            guard live.val && phase.val == Saved && receipt.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            let content = @execution.completed_export_content(value)
            let (expected, _, _, _) = @execution.output_stream_identity(content)
            if cid != expected || !available() {
              return Err(Configuration(InputUnavailable))
            }
            let handle = @execution.retain_admitted_output_stream(
              content,
              (),
              available,
            )
            let retained = match
              @execution.bind_completed_output_export(
                value,
                @execution.retained_output_material(handle),
              ) {
              Ok(result) => result
              Err(_) => return Err(Configuration(InputUnavailable))
            }
            // The exporter consumed its exact receipt. Retire the driver's
            // only cell output before the first reload byte can be admitted.
            receipt.val = None
            ordinary.val = None
            stored.val = Some(retained)
            phase.val = Released
            Ok(())
          },
          source_available: () => ordinary.val is Some(_),
          begin_reload: () => {
            guard live.val && phase.val == Released && stored.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            let value = match
              @execution.prepare_completed_output_import(
                value,
                setup.imports.max_rows,
                setup.imports.values,
                wire,
                frames.maxFrameBytes,
              ) {
              Ok(result) => result
              Err(_) => return Err(Configuration(InputUnavailable))
            }
            importing.val = Some(value)
            phase.val = Reloading
            Ok(())
          },
          append_reload: row => {
            guard phase.val == Reloading && importing.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            if charge() is Err(issue) {
              return Err(issue)
            }
            @execution.append_completed_output_import_wire(
              value,
              row,
              setup.imports.row,
            ).map_err(_ => Configuration(InputUnavailable))
          },
          finish_reload: () => {
            guard phase.val == Reloading && importing.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            if charge() is Err(issue) {
              return Err(issue)
            }
            let value = match @execution.finish_completed_output_import(value) {
              Ok(result) => result
              Err(_) => return Err(Configuration(InputUnavailable))
            }
            restored.val = Some(value)
            importing.val = None
            stored.val = None
            phase.val = Restored
            Ok(())
          },
          finish: () => {
            guard live.val &&
              phase.val == Restored &&
              storage_released() &&
              restored.val is Some(value) else {
              return Err(Configuration(InvalidLimits))
            }
            ordinary.val = Some(value)
            restored.val = None
            relation_snapshot_cancel.val = None
            phase.val = Finished
            snapshot_ready.val = true
            Ok(())
          },
        }),
      )
    },
    prepare_carrier_snapshot: fn(storage_released) {
      guard live.val &&
        execution_finished.val &&
        execution_failure.val is None &&
        !snapshot_attempted.val &&
        carrier.val is Some(source) &&
        carrier_completed.val is None &&
        output_target is Some(target) &&
        provider_execution.val is Some(active) else {
        return Err(Configuration(InvalidLimits))
      }
      snapshot_attempted.val = true
      let operation = match @carrier_runtime.material_prepare_snapshot(source) {
        Err(issue) => return Err(CarrierSnapshot(issue))
        Ok(None) => return Ok(None)
        Ok(Some(operation)) => operation
      }
      snapshot_ready.val = false
      snapshot_storage_released.val = Some(storage_released)
      if operation.workspace_bytes > setup.capacity.execution_bytes ||
        operation.maximum_bytes < 1 ||
        operation.maximum_frame_bytes < 1 {
        return Err(Configuration(InvalidLimits))
      }
      let owner = @execution.generated_sequence_owner(setup.sequence)
      let remaining = Ref(0L)
      match @local.managed_provider_cumulative_work(active) {
        Ok(work) if work >= 0L && work <= setup.execution.max_work.to_int64() =>
          remaining.val = setup.execution.max_work.to_int64() - work
        _ => return Err(Configuration(InvalidLimits))
      }
      let phase = Ref(SnapshotPhase::Saving)
      let save_work = Ref(0L)
      let reload_work = Ref(0L)
      let save_progress = Ref(0L)
      let reload_progress = Ref(0L)
      let advance_stage = fn(quantum, reloading) {
        if !live.val ||
          execution_failure.val is Some(_) ||
          quantum <= 0 ||
          phase.val != (if reloading { Reloading } else { Saving }) {
          return Err(Configuration(InvalidLimits))
        }
        if remaining.val <= 0L {
          phase.val = Failed
          execution_failure.val = Some(Configuration(InvalidLimits))
          return Err(Configuration(InvalidLimits))
        }
        let allowed = if remaining.val < quantum.to_int64() {
          remaining.val.to_int()
        } else {
          quantum
        }
        let observation = match
          (if reloading {
            operation.advance_reload
          } else {
            operation.advance_save
          })(allowed) {
          Ok(value) => value
          Err(issue) => {
            phase.val = Failed
            execution_failure.val = Some(CarrierSnapshot(issue))
            return Err(CarrierSnapshot(issue))
          }
        }
        let work_cursor = if reloading { reload_work } else { save_work }
        let progress_cursor = if reloading {
          reload_progress
        } else {
          save_progress
        }
        if observation.work < work_cursor.val ||
          observation.progress < progress_cursor.val {
          @local.managed_provider_record_handoff_work(active, -1L) |> ignore
          phase.val = Failed
          execution_failure.val = Some(Configuration(InvalidLimits))
          return Err(Configuration(InvalidLimits))
        }
        let delta = observation.work - work_cursor.val
        if delta < 0L ||
          delta > allowed.to_int64() ||
          (!observation.complete && observation.issue is None && delta == 0L) {
          @local.managed_provider_record_handoff_work(active, -1L) |> ignore
          phase.val = Failed
          execution_failure.val = Some(Configuration(InvalidLimits))
          return Err(Configuration(InvalidLimits))
        }
        match @local.managed_provider_record_handoff_work(active, delta) {
          Ok(_) => ()
          Err(_) => {
            phase.val = Failed
            execution_failure.val = Some(Configuration(InvalidLimits))
            return Err(Configuration(InvalidLimits))
          }
        }
        work_cursor.val = observation.work
        progress_cursor.val = observation.progress
        remaining.val -= delta
        if observation.issue is Some(issue) {
          phase.val = Failed
          execution_failure.val = Some(CarrierSnapshot(issue))
          return Err(CarrierSnapshot(issue))
        }
        if observation.complete {
          phase.val = if reloading { Restored } else { Saved }
        }
        Ok({
          complete: observation.complete,
          progress: observation.progress,
          work: delta,
        })
      }
      Ok(
        Some({
          key: "task-" + setup.task.to_string(),
          maximum_bytes: operation.maximum_bytes,
          maximum_frame_bytes: operation.maximum_frame_bytes,
          advance_save: quantum => advance_stage(quantum, false),
          take_output: () => {
            if phase.val != Saving && phase.val != Saved {
              return Err(Configuration(InvalidLimits))
            }
            (operation.take_output)().map_err(issue => CarrierSnapshot(issue))
          },
          content: () => {
            if phase.val != Saved {
              return Err(Configuration(InvalidLimits))
            }
            (operation.content)().map_err(issue => CarrierSnapshot(issue))
          },
          release_source: cid => {
            if !live.val || phase.val != Saved {
              return Err(Configuration(InvalidLimits))
            }
            match (operation.release_source)(cid) {
              Ok(_) => ()
              Err(issue) => return Err(CarrierSnapshot(issue))
            }
            phase.val = Released
            Ok(())
          },
          begin_reload: (text, available) => {
            if !live.val || phase.val != Released {
              return Err(Configuration(InvalidLimits))
            }
            match (operation.begin_reload)(text, available) {
              Ok(_) => ()
              Err(issue) => return Err(CarrierSnapshot(issue))
            }
            phase.val = Reloading
            Ok(())
          },
          advance_reload: quantum => advance_stage(quantum, true),
          finish: () => {
            if !live.val || phase.val != Restored || !storage_released() {
              return Err(Configuration(InvalidLimits))
            }
            let restored = match (operation.take_material)() {
              Ok(value) => value
              Err(issue) => return Err(CarrierSnapshot(issue))
            }
            // Keep the old operation handle through its cleanup confirmation;
            // revoking its source alone does not end snapshot custody.
            retired_carriers.push(source)
            carrier.val = Some(restored)
            if !@carrier_runtime.completion_reference_matches_port(
                @carrier_runtime.material_reference(restored),
                owner,
                target,
              ) ||
              !@carrier_runtime.material_available(restored) {
              phase.val = Failed
              return Err(Configuration(InputUnavailable))
            }
            @carrier_runtime.reclaim_material(source) |> ignore
            if @carrier_runtime.material_cleanup_pending(source) {
              return Err(Configuration(InputUnavailable))
            }
            phase.val = Finished
            snapshot_ready.val = true
            Ok(())
          },
        }),
      )
    },
    storage_bytes: setup.capacity.retained_bytes,
    close: fn() {
      live.val = false
      cancel_finalization()
      if carrier.val is Some(material) {
        @carrier_runtime.reclaim_material(material) |> ignore
      }
      for material in retired_carriers {
        @carrier_runtime.reclaim_material(material) |> ignore
      }
      @strategy.close_task_execution(setup.run, execution)
    },
    cleanup_refresh: fn() {
      if scratch_uses.val != 0 {
        return false
      }
      if !release_provider_scratch() {
        return false
      }
      release_owned_scratch()
      let carrier_reclaimed = match carrier.val {
        None => true
        Some(material) =>
          if !@carrier_runtime.material_cleanup_pending(material) {
            true
          } else {
            @carrier_runtime.reclaim_material(material) |> ignore
            !@carrier_runtime.material_cleanup_pending(material)
          }
      }
      if !carrier_reclaimed {
        return false
      }
      for material in retired_carriers {
        @carrier_runtime.reclaim_material(material) |> ignore
        if @carrier_runtime.material_cleanup_pending(material) {
          return false
        }
      }
      if !snapshot_storage_released.val.map(check => check()).unwrap_or(true) {
        return false
      }
      @strategy.refresh_task_execution_cleanup(setup.run, execution).unwrap_or(
        false,
      )
    },
  }
  Ok({
    ..operations,
    inputs: operations.inputs.map(transfer => {
      ..transfer,
      append: row => {
        with_managed_scratch_use(scratch_uses, release_owned_scratch, () => {
          (transfer.append)(row)
        })
      },
      finish: () => {
        with_managed_scratch_use(
          scratch_uses,
          release_owned_scratch,
          transfer.finish,
        )
      },
    }),
    execute: () => {
      with_managed_scratch_use(
        scratch_uses,
        release_owned_scratch,
        operations.execute,
      )
    },
    retained_inputs: operations.retained_inputs.map(transfer => {
      ..transfer,
      begin: () => {
        with_managed_scratch_use(
          scratch_uses,
          release_owned_scratch,
          transfer.begin,
        )
      },
      append: row => {
        with_managed_scratch_use(scratch_uses, release_owned_scratch, () => {
          (transfer.append)(row)
        })
      },
      finish: () => {
        with_managed_scratch_use(
          scratch_uses,
          release_owned_scratch,
          transfer.finish,
        )
      },
    }),
    advance: quantum => {
      with_managed_scratch_use(scratch_uses, release_owned_scratch, () => {
        (operations.advance)(quantum)
      })
    },
    prepare_finalization: (payload, bytes, available) => {
      with_managed_scratch_use(scratch_uses, release_owned_scratch, () => {
        (operations.prepare_finalization)(payload, bytes, available)
      })
    },
    advance_finalization: quantum => {
      with_managed_scratch_use(scratch_uses, release_owned_scratch, () => {
        (operations.advance_finalization)(quantum)
      })
    },
  })
}

///|
pub fn start_local_managed_dispatch_node(
  setup : LocalManagedDispatchConfiguration[Int],
) -> Result[LocalManagedDispatchOperations[Int], LocalDispatchIssue] {
  start_local_managed_dispatch(setup)
}
