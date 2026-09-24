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
pub struct LocalManagedDispatchOperations[T] {
  inputs : Array[LocalManagedInputTransfer[T]]
  execute : () -> Result[Unit, LocalDispatchIssue]
  advance : (Int) -> Result[LocalManagedAdvance, LocalDispatchIssue]
  request_cancel : () -> Bool
  execution_stopped : () -> Bool
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
  let selected_operation = @strategy.graph_task_selected_step(
      @strategy.captured_dag_graph(installed.run),
      task,
    )
    is Some(_)
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
      task - 1,
      request,
      estimates,
      interval_search_ceilings~,
      asof_search_ceilings~,
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
  let bridges : Array[@execution.ManagedProducerBridge[T]] = []
  let reads : Array[@execution.ProducerRead?] = []
  let ordinary : Ref[@execution.CompletedOutput?] = Ref(None)
  let retained : Ref[@execution.ManagedRetainedOutput[T]?] = Ref(None)
  let carrier : Ref[@carrier_runtime.Material?] = Ref(None)
  let carrier_completed : Ref[@execution.CarrierManagedCompletedOutput?] = Ref(
    None,
  )
  let provider_execution : Ref[@local.ManagedProviderExecution?] = Ref(None)
  let execution_finished = Ref(false)
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
                return Err(@strategy.RunIssue::Compute(InputUnavailable))
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
              bridges.push(bridge)
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
            for bridge in bridges {
              @execution.close_managed_producer_bridge(bridge)
            }
          },
          dispose: fn() {
            disposed.val = true
            live.val = false
            cancel_finalization()
            if provider_execution.val is Some(active) {
              @local.cancel_managed_provider(active) |> ignore
            }
            for bridge in bridges {
              @execution.close_managed_producer_bridge(bridge)
            }
          },
          settled: fn() { settled.val = true },
          retention_released: fn() {
            let relation_released = retained.val is None ||
              retained.val
              .map(value => {
                @execution.managed_retained_output_payload(value) is None
              })
              .unwrap()
            let carrier_released = carrier.val is None ||
              carrier.val
              .map(value => !@carrier_runtime.material_available(value))
              .unwrap()
            relation_released && carrier_released
          },
          released: fn() { () },
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
  let numeric = if numeric_count == 0 {
    None
  } else {
    Some(
      @execution.numeric_aggregate_execution_with_seal(
        fn(step, name, occurrence, contributors, expected_count, max_work) {
          @strategy.execute_task_numeric_reduction_for_slot(
            setup.run,
            execution,
            step,
            name,
            occurrence,
            contributors,
            expected_count,
            max_work,
          )
        },
        fn(step, name, occurrence_count) {
          @strategy.seal_task_numeric_reduction_slot(
            setup.run,
            execution,
            step,
            name,
            occurrence_count,
          )
        },
      ),
    )
  }
  let transfers = []
  let mut bridge_index = 0
  for read_index, input in relation_inputs {
    guard input is ManagedRelationInput(managed) else { continue }
    let bridge = bridges[bridge_index]
    bridge_index += 1
    transfers.push(LocalManagedInputTransfer::{
      input: managed,
      append: fn(row) {
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
  let output_target = @strategy.captured_task_target(setup.run, setup.task)
  let advance = fn(
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
    let exact = reads.filter_map(value => value)
    match setup.provider {
      Some(provider) => {
        let active = match provider_execution.val {
          Some(value) => value
          None => {
            let started = match
              @local.start_managed_provider_with_inputs_and_execution(
                provider,
                setup.sequence,
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
              ) {
              Ok(value) => value
              Err(issue) => return Err(Configuration(issue))
            }
            provider_execution.val = Some(started)
            started
          }
        }
        match @local.advance_managed_provider(active, quantum) {
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
            ordinary.val = Some(output)
            execution_finished.val = true
            for bridge in bridges {
              @execution.close_managed_producer_bridge(bridge)
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
            for bridge in bridges {
              @execution.close_managed_producer_bridge(bridge)
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
            Err(Configuration(InputUnavailable))
          }
        }
      }
      None => {
        if setup.provider_inputs.length() != exact.length() ||
          setup.provider_inputs.any(input => {
            input is PreparedSupplied(_) || input is PreparedCarrier(_)
          }) {
          execution_finished.val = true
          return Err(Configuration(UnsupportedInputShape))
        }
        let output = match
          @local.execute_local_managed_fixed_compute(
            setup.choice,
            setup.prepared,
            exact,
            setup.execution,
            setup.measurement,
            join_output_ceilings=setup.join_output_ceilings,
            interval_search_ceilings=setup.interval_search_ceilings,
            asof_search_ceilings=setup.asof_search_ceilings,
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
        if numeric_count > 0 &&
          !@strategy.seal_task_numeric_reductions(setup.run, execution) {
          execution_finished.val = true
          return Err(Execution(ForeignCandidate))
        }
        let independent = match
          @execution.copy_completed_output_independent(
            output,
            setup.execution.rows.max_rows,
            setup.imports.wire.max_columns,
          ) {
          Ok(value) => value
          Err(issue) => {
            execution_finished.val = true
            return Err(ManagedCopy(issue))
          }
        }
        ordinary.val = Some(independent)
        execution_finished.val = true
        for bridge in bridges {
          @execution.close_managed_producer_bridge(bridge)
        }
        Ok({
          complete: true,
          progress: @execution.completed_row_count(independent).to_int64(),
          work: 1L,
        })
      }
    }
  }
  Ok({
    inputs: transfers,
    execute: fn() {
      while !execution_finished.val {
        match advance(1024) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      Ok(())
    },
    advance,
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
          Err(_) => return Err(Configuration(InvalidLimits))
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
                Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
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
                  Err(_) =>
                    return Err(Configuration(LogicalIdentityUnsupported))
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
                Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
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
                Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
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
                  Err(_) =>
                    return Err(Configuration(LogicalIdentityUnsupported))
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
                  Err(_) =>
                    return Err(Configuration(LogicalIdentityUnsupported))
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
          Err(_) => return Err(Configuration(LogicalIdentityUnsupported))
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
      if relation_pending {
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
    storage_bytes: setup.capacity.retained_bytes,
    close: fn() {
      live.val = false
      cancel_finalization()
      if carrier.val is Some(material) {
        @carrier_runtime.reclaim_material(material) |> ignore
      }
      @strategy.close_task_execution(setup.run, execution)
    },
    cleanup_refresh: fn() {
      let provider_reclaimed = match provider_execution.val {
        None => true
        Some(active) =>
          if @local.managed_provider_stopped(active) {
            @local.cleanup_managed_provider(active).unwrap_or(false)
          } else {
            false
          }
      }
      if !provider_reclaimed {
        return false
      }
      let carrier_reclaimed = match carrier.val {
        None => true
        Some(material) =>
          !@carrier_runtime.material_available(material) ||
          @carrier_runtime.reclaim_material(material)
      }
      if !carrier_reclaimed {
        return false
      }
      @strategy.refresh_task_execution_cleanup(setup.run, execution).unwrap_or(
        false,
      )
    },
  })
}

///|
pub fn start_local_managed_dispatch_node(
  setup : LocalManagedDispatchConfiguration[Int],
) -> Result[LocalManagedDispatchOperations[Int], LocalDispatchIssue] {
  start_local_managed_dispatch(setup)
}
