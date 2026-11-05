///|
/// Pure preparation data for the exact checked physical task selection. The
/// original module and policies survive quoting and binding to a Run. This is
/// not a Ledger, allocation, permission or physical cleanup owner.
struct LocalDispatchPreparation {
  graph : @strategy.CheckedDAG
  registry : @connector.CapabilityRegistry
  registration : @connector.CapabilityRegistration
  implementation : @local.LocalComputeModule
  capacities : Array[@execution.ExecutionCapacity?]
  input_counts : Array[Int]
  import_policy : (@local.LocalImportLimits, Int64?)?
  import_metadata : LocalManagedMetadataLimits?
  output_policy : (@local.LocalExportLimits, Int64?)?
  task_capacity : Array[@strategy.PhysicalEnvelope?]
  retained_bytes : Int64?
  transfer_bytes : Int64?
}

///|
/// Select the actual installed physical steps/prefixes before opening a Run.
/// The caller retains its existing preparation funding and admission duties.
/// Capacity accessors quote the same module later used by the bound driver.
pub fn prepare_local_dispatch_plan(
  graph : @strategy.CheckedDAG,
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  sequences : Array[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_work : Int,
  managed_capacity? : @connector.FixedComputeCapacity,
  managed_providers? : Array[@local.ManagedProvider] = [],
  inputs? : (@local.LocalImportLimits, Int64?)? = None,
  metadata? : LocalManagedMetadataLimits? = None,
  output? : (@local.LocalExportLimits, Int64?)? = None,
) -> Result[LocalDispatchPreparation, LocalDispatchIssue] {
  let selected_metadata = match inputs {
    Some((limits, milliseconds)) =>
      match local_retained_input_metadata(limits, milliseconds, metadata) {
        Some(value) => Some(value)
        None => return Err(Configuration(InvalidLimits))
      }
    None => {
      if metadata is Some(_) || output is Some(_) {
        return Err(Configuration(InvalidLimits))
      }
      None
    }
  }
  if output is Some((limits, milliseconds)) &&
    !local_retained_output_policy_valid(limits, milliseconds) {
    return Err(Configuration(InvalidLimits))
  }
  let first = @strategy.graph_captured_prefix(graph)
  let count = @strategy.graph_task_count(graph)
  if first < 0 || first > count || sequences.length() != count - first {
    return Err(Configuration(ForeignPreparation))
  }
  let physical_sequences = []
  for index, sequence in sequences {
    if !(@strategy.graph_task_owner(graph, index + first) is Some(owner) &&
      physical_equal(owner, @execution.generated_sequence_owner(sequence))) {
      return Err(Configuration(ForeignPreparation))
    }
    let physical = match
      @strategy.graph_task_selected_step(graph, index + first) {
      Some(step) => @execution.select_generated_sequence_step(sequence, step)
      None =>
        match @strategy.graph_task_prefix_end(graph, index + first) {
          Some(last) =>
            @execution.select_generated_sequence_prefix(sequence, last)
          None => Some(sequence)
        }
    }
    guard physical is Some(physical) else {
      return Err(Configuration(ForeignPreparation))
    }
    physical_sequences.push(physical)
  }
  let implementation = match
    @local.prepare_local_compute_module(
      registry,
      registration,
      physical_sequences,
      execution,
      measurement,
      max_work,
      physical_sequences.length(),
      managed_capacity?,
      managed_providers~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Configuration(issue))
  }
  let input_counts = Array::make(sequences.length(), 0)
  for index in 0..<@strategy.graph_data_count(graph) {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    if edge.consumer >= first &&
      edge.consumer < count &&
      !(edge.producer >= first &&
      @local.local_module_sequence_outputs_carrier(
        implementation,
        edge.producer - first,
      )) {
      let slot = edge.consumer - first
      if input_counts[slot] == 2147483647 {
        return Err(Configuration(InvalidLimits))
      }
      // Count the same row-import occurrences as managed dispatch. Carrier
      // predecessors supply their original managed material, never a row wire
      // importer. Repeated Relation ports still own separate import storage.
      input_counts[slot] += 1
    }
  }
  let capacities = Array::makei(physical_sequences.length(), index => {
    @local.local_module_capacity(implementation, index)
  })
  let original : LocalDispatchPreparation = {
    graph,
    registry,
    registration,
    implementation,
    capacities,
    input_counts,
    import_policy: None,
    import_metadata: None,
    output_policy: None,
    task_capacity: [],
    retained_bytes: None,
    transfer_bytes: None,
  }
  Ok(
    local_dispatch_preparation_policies(
      original, inputs, selected_metadata, output,
    ),
  )
}

///|
// The same frozen policy quote for future inputs and actual missing copies.
// Borrowed cell-access reads keep their existing holding; no importer exists.
fn local_dispatch_copy_capacity(
  base : @execution.ExecutionCapacity,
  metadata_bytes : Int64,
  imported : Int64,
  exported : Int64,
  wire_bytes : Int64,
  copies : Int,
  alongside : Bool,
) -> @strategy.PhysicalEnvelope? {
  if copies < 0 ||
    metadata_bytes < 0L ||
    imported < 0L ||
    exported < 0L ||
    wire_bytes < 0L {
    return None
  }
  guard @execution.execution_capacity_inventory(
      [
        { unit: QuotedBytes, count: base.retained_bytes, copies: 1, },
        { unit: QuotedBytes, count: metadata_bytes, copies: 1, },
        { unit: QuotedBytes, count: imported, copies, },
        { unit: QuotedBytes, count: exported, copies: 1, },
      ],
      [{ unit: QuotedBytes, count: base.execution_bytes, copies: 1, }],
      if alongside {
        RetainedAlongsideExecution
      } else {
        SeparateDimensions
      },
    )
    is Some(capacity) &&
    @execution.execution_capacity_inventory_bytes([
      { unit: QuotedBytes, count: wire_bytes, copies, },
    ])
    is Some(transfer_bytes) else {
    return None
  }
  Some({
    transfer_bytes,
    retained_bytes: capacity.retained_bytes,
    execution_bytes: capacity.execution_bytes,
  })
}

///|
fn local_dispatch_preparation_policies(
  original : LocalDispatchPreparation,
  inputs : (@local.LocalImportLimits, Int64?)?,
  metadata : LocalManagedMetadataLimits?,
  output : (@local.LocalExportLimits, Int64?)?,
) -> LocalDispatchPreparation {
  let import_bytes = match inputs {
    None => Some(0L)
    Some((limits, _)) => @local.local_import_retention_capacity(limits)
  }
  let export_bytes = match output {
    None => Some(0L)
    Some((limits, _)) => @local.local_export_retention_capacity(limits)
  }
  let metadata_bytes = metadata.map(value => value.retained_bytes).unwrap_or(0L)
  let task_capacity : Array[@strategy.PhysicalEnvelope?] = Array::makei(
    original.capacities.length(),
    slot => {
      guard original.capacities[slot] is Some(base) &&
        import_bytes is Some(imported) &&
        export_bytes is Some(exported) else {
        return None
      }
      let ports = if inputs is Some(_) {
        original.input_counts[slot]
      } else {
        0
      }
      local_dispatch_copy_capacity(
        base,
        metadata_bytes,
        imported,
        exported,
        inputs.map(value => value.0.wire.max_bytes.to_int64()).unwrap_or(0L),
        ports,
        inputs is Some(_) || output is Some(_),
      )
    },
  )
  let retained : Array[@execution.ExecutionCapacityItem] = []
  let transferred : Array[@execution.ExecutionCapacityItem] = []
  let mut known = true
  for capacity in task_capacity {
    match capacity {
      None => known = false
      Some(value) => {
        retained.push({
          unit: @execution.QuotedBytes,
          count: value.retained_bytes,
          copies: 1,
        })
        transferred.push({
          unit: @execution.QuotedBytes,
          count: value.transfer_bytes,
          copies: 1,
        })
      }
    }
  }
  {
    ..original,
    import_policy: inputs,
    import_metadata: metadata,
    output_policy: output,
    task_capacity,
    retained_bytes: if known {
      @execution.execution_capacity_inventory_bytes(retained)
    } else {
      None
    },
    transfer_bytes: if known {
      @execution.execution_capacity_inventory_bytes(transferred)
    } else {
      None
    },
  }
}

///|
/// Exact task envelope later consumed by the actual offer, without rebuilding
/// its provider or recalculating a sequence from raw configuration.
pub fn local_dispatch_preparation_task_capacity(
  original : LocalDispatchPreparation,
  task : Int,
) -> @strategy.PhysicalEnvelope? {
  let first = @strategy.graph_captured_prefix(original.graph)
  if task < first || task >= @strategy.graph_task_count(original.graph) {
    return None
  }
  let slot = task - first
  match original.task_capacity.get(slot) {
    Some(value) => value
    None => None
  }
}

///|
/// All configured Compute holdings can coexist until their actual borrowers
/// retire. This quotes retention, not RSS, execution peak or physical backing.
pub fn local_dispatch_preparation_retained_bytes(
  original : LocalDispatchPreparation,
) -> Int64? {
  original.retained_bytes
}

///|
/// Planned cumulative import transfers; actual starts/transfers still charge
/// their original Ledger. Unused reservation is not consumed work.
pub fn local_dispatch_preparation_transfer_bytes(
  original : LocalDispatchPreparation,
) -> Int64? {
  original.transfer_bytes
}

///|
/// Return the actual configuration only after it has been sealed. Refinement
/// before the first quote retains the same module and graph, not a new owner.
pub fn local_dispatch_original_preparation(
  installed : LocalDispatchModule,
) -> LocalDispatchPreparation? {
  if installed.policy_sealed {
    Some(installed.preparation)
  } else {
    None
  }
}

///|
/// Bind this exact pre-Run preparation to the original checked Run. A restored
/// or equal graph cannot replace its private nominal association. This opens
/// the existing dispatch channel; it does not open a Run or a parent Ledger.
pub fn bind_local_dispatch_plan(
  driver : @host.DispatchDriver,
  original : LocalDispatchPreparation,
) -> Result[LocalDispatchModule, LocalDispatchIssue] {
  bind_local_dispatch_original(driver, original, true)
}

///|
// A completed keyed-input view borrows its original checked Effect graph.
// Only that same opaque Effect owner can bind the pre-Run configuration.
pub fn bind_local_effect_dispatch_plan(
  driver : @host.DispatchDriver,
  original : LocalDispatchPreparation,
  captured : @strategy.CapturedEffectRunDAG,
) -> Result[LocalDispatchModule, LocalDispatchIssue] {
  bind_local_dispatch_original(
    driver,
    original,
    true,
    captured_effect=Some(captured),
  )
}

///|
fn bind_local_dispatch_original(
  driver : @host.DispatchDriver,
  original : LocalDispatchPreparation,
  freeze_policy : Bool,
  captured_effect? : @strategy.CapturedEffectRunDAG? = None,
) -> Result[LocalDispatchModule, LocalDispatchIssue] {
  let run = @host.dispatch_driver_run(driver)
  let same = match captured_effect {
    None => physical_equal(@strategy.captured_dag_graph(run), original.graph)
    Some(value) =>
      @strategy.captured_effect_run_matches_preparation(
        value,
        run,
        original.graph,
      )
  }
  if !same {
    return Err(Configuration(ForeignPreparation))
  }
  let carrier_paths = local_dispatch_carrier_path_table(
    run,
    original.implementation,
  )
  let channel = match
    @host.open_dispatch_channel(
      driver,
      original.registry,
      original.registration,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  Ok({
    run,
    preparation: original,
    registration: original.registration,
    implementation: original.implementation,
    channel,
    carrier_paths,
    estimate_configuration: None,
    import_policy: original.import_policy,
    import_metadata: original.import_metadata,
    output_policy: original.output_policy,
    policy_sealed: freeze_policy,
  })
}

///|
fn local_retained_input_metadata(
  limits : @local.LocalImportLimits,
  milliseconds : Int64?,
  metadata : LocalManagedMetadataLimits?,
) -> LocalManagedMetadataLimits? {
  if @local.local_import_retention_capacity(limits) is None ||
    limits.row.max_bytes > 16777216 ||
    limits.max_batch_bytes > 16777216 ||
    limits.row.max_depth < 1 ||
    limits.row.max_depth > 64 ||
    (milliseconds is Some(value) && value < 0L) {
    return None
  }
  local_managed_metadata_limits(limits, metadata)
}

///|
fn local_retained_output_policy_valid(
  limits : @local.LocalExportLimits,
  milliseconds : Int64?,
) -> Bool {
  @local.local_export_retention_capacity(limits) is Some(_) &&
  !(milliseconds is Some(value) && value < 0L)
}
