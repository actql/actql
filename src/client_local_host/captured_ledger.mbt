///|
fn client_local_general_value_nodes() -> Int {
  20000
}

///|
fn client_local_default_row_profile() -> Int {
  100
}

///|
fn client_local_execution_limits(
  max_rows? : Int = client_local_default_row_profile(),
  scalar_sequences? : Array[@execution.GeneratedSequence]? = None,
  scalar_inventory? : ClientLocalSchemaProofInventory? = None,
  scalar_demand? : ClientLocalScalarDemand? = None,
  value_node_demand? : ClientLocalValueNodeDemand? = None,
) -> (
  @execution.ValueLimits,
  @execution.SequenceExecutionLimits,
  @execution.FixedInputGuardMeasureLimits,
) {
  // Preserve general text and execution envelopes. Only original checked
  // Number/Boolean schemas can reduce the scalar input/output node envelope;
  // the pre-admission quote and configured providers use this same policy.
  let scalar_nodes = if value_node_demand is Some(demand) {
    Some(demand.nodes)
  } else if scalar_demand is Some(demand) {
    Some(demand.value_nodes)
  } else if scalar_inventory is Some(inventory) {
    client_local_inventory_nodes(inventory, max_rows)
  } else {
    match scalar_sequences {
      Some(sequences) => client_local_scalar_nodes(sequences, max_rows)
      None => None
    }
  }
  let values : @execution.ValueLimits = {
    max_nodes: scalar_nodes.unwrap_or(client_local_general_value_nodes()),
    max_text_bytes: 500000,
    max_depth: 100,
    max_work: 20000000,
  }
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: values.max_work,
    max_frames: 100,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: values.max_work,
    // Guard measurement counts serialized scalar bytes, not text payload.
    max_bytes: scalar_demand
    .map(demand => Int::max(500000, demand.wire_bytes))
    .unwrap_or(500000),
    max_nodes: Int::max(20000, scalar_nodes.unwrap_or(20000)),
    max_depth: values.max_depth,
  }
  (values, execution, measurement)
}

///|
/// Use the checked task inventory and the same Local import/output envelope
/// for ordinary and Effect computations. Provider capacity and Run capacity
/// are derived together, before any task starts.
priv struct ClientLocalSequenceCapacity {
  limits : @resources.LedgerLimits
  provider_retained : Int64
  provider_execution : Int64
  simultaneous : (Int64, Int64)?
}

///|
fn client_local_sequence_capacity(
  sequences : Array[@execution.GeneratedSequence],
  task_count : Int,
  capacity_plan? : ClientLocalCapacityPlan? = None,
  retained_inputs? : Array[Int]? = None,
  max_rows? : Int = client_local_default_row_profile(),
  retained_output? : Bool = true,
  runtime_admission? : Bool = false,
) -> (@resources.LedgerLimits, Int64, Int64)? {
  client_local_sequence_capacity_original(
    sequences,
    task_count,
    capacity_plan~,
    retained_inputs~,
    max_rows~,
    retained_output~,
    runtime_admission~,
  ).map(value => {
    (value.limits, value.provider_retained, value.provider_execution)
  })
}

///|
fn client_local_sequence_capacity_original(
  sequences : Array[@execution.GeneratedSequence],
  task_count : Int,
  capacity_plan? : ClientLocalCapacityPlan? = None,
  retained_inputs? : Array[Int]? = None,
  max_rows? : Int = client_local_default_row_profile(),
  retained_output? : Bool = true,
  include_simultaneous? : Bool = false,
  simultaneous_graph? : @strategy.CheckedDAG? = None,
  runtime_admission? : Bool = false,
) -> ClientLocalSequenceCapacity? {
  if task_count < 1 || sequences.length() > task_count {
    return None
  }
  let runtime_inventory = runtime_admission &&
    !include_simultaneous &&
    retained_inputs is Some(_)
  let plan = capacity_plan.unwrap_or_else(() => {
    client_local_capacity_plan(sequences, max_rows)
  })
  if !client_local_capacity_plan_matches(plan, sequences, max_rows) {
    return None
  }
  if include_simultaneous {
    guard plan.graph is Some(original) &&
      simultaneous_graph is Some(graph) &&
      physical_equal(original, graph) else {
      return None
    }
  }
  if plan.metadata_retained_bytes > 0L && retained_inputs is None {
    return None
  }
  let execution = plan.execution
  let measurement = plan.measurement
  let mut retained_bytes = 0L
  let mut execution_bytes = 0L
  let mut total_retained_bytes = 0L
  let individual : Array[(Int64, Int64)]? = if include_simultaneous {
    Some([])
  } else {
    None
  }
  let mut input_import_bytes = 0L
  let mut output_export_bytes = 0L
  for index, sequence in sequences {
    guard @execution.generated_sequence_capacity(
        sequence, execution, measurement,
      )
      is Some(required) else {
      return None
    }
    let retained = @execution.execution_capacity_retained_bytes(required)
    let executing = @execution.execution_capacity_execution_bytes(required)
    if individual is Some(values) {
      guard simultaneous_graph is Some(graph) else { return None }
      // The installed dispatch selects an exact task step or prefix before
      // selecting its bounded provider. Quote that same provider's complete
      // child/scratch envelope, not only the generated outer sequence.
      // A captured Source prefix is absent from this Compute inventory.
      // Its original owner keeps its separate acquisition/provider footprint.
      let task = index + plan.graph_offset
      let selected = match @strategy.graph_task_selected_step(graph, task) {
        Some(step) => @execution.select_generated_sequence_step(sequence, step)
        None =>
          match @strategy.graph_task_prefix_end(graph, task) {
            Some(last) =>
              @execution.select_generated_sequence_prefix(sequence, last)
            None => Some(sequence)
          }
      }
      guard selected is Some(selected) &&
        @local.local_bounded_relation_provider(execution, measurement, selected)
        is Some(provider) &&
        @local.managed_provider_capacity(provider, selected) is Some(actual) else {
        return None
      }
      values.push(
        (
          @execution.execution_capacity_retained_bytes(actual) +
          plan.metadata_retained_bytes,
          @execution.execution_capacity_execution_bytes(actual),
        ),
      )
    }
    if retained < 0L || retained > client_local_retained_byte_ceiling() {
      return None
    }
    if !runtime_inventory {
      if retained > client_local_retained_byte_ceiling() - total_retained_bytes {
        return None
      }
      total_retained_bytes += retained
    }
    if retained > retained_bytes {
      retained_bytes = retained
    }
    if executing > execution_bytes {
      execution_bytes = executing
    }
  }
  let mut transfer_bytes = task_count.to_int64() * 1000000L
  if retained_inputs is Some(inputs) {
    if inputs.length() != sequences.length() {
      return None
    }
    let import_limits = plan.imports
    // Input custody and metadata exist on both runtime paths. Only the
    // configured retained-output path also constructs the export backing.
    let export_capacity = if retained_output {
      @local.local_export_retention_capacity(plan.exports)
    } else {
      Some(0L)
    }
    guard @local.local_import_retention_capacity(import_limits)
      is Some(import_bytes) &&
      export_capacity is Some(export_bytes) else {
      return None
    }
    // A whole-Run maximum is an optional estimate, not a reservation or an
    // execution prerequisite. The Source-free consumer admits each actual
    // provider/import/output on this SAME finite Ledger before construction.
    // Callers requiring a simultaneous envelope retain the strict inventory.
    let inventory = if runtime_inventory {
      let mut ports = 0L
      for count in inputs {
        if count < 0 {
          return None
        }
        ports += count.to_int64()
      }
      Some((client_local_retained_byte_ceiling(), ports))
    } else {
      client_local_store_inventory(
        inputs,
        retained_bytes + plan.metadata_retained_bytes,
        import_bytes,
        export_bytes,
        client_local_retained_byte_ceiling(),
      )
    }
    guard inventory is Some((retained, ports)) else { return None }
    input_import_bytes = import_bytes
    output_export_bytes = export_bytes
    total_retained_bytes = retained
    let imported_wire = ports * import_limits.wire.max_bytes.to_int64()
    if imported_wire > transfer_bytes {
      transfer_bytes = imported_wire
    }
  }
  let limits : @resources.LedgerLimits = {
    planning_work: 100000,
    attempts: task_count,
    holdings: task_count,
    transfer_bytes,
    retained_bytes: if total_retained_bytes > 200000000L {
      total_retained_bytes
    } else {
      200000000L
    },
    execution_bytes: client_local_execution_byte_ceiling(),
  }
  let simultaneous = match individual {
    None => None
    Some(per_task) => {
      let mut total : (Int64, Int64)? = Some((0L, 0L))
      for index in 0..<per_task.length() {
        let (provider, scratch) = per_task[index]
        let inputs = match retained_inputs {
          Some(ports) => ports[index]
          None => 0
        }
        total = match total {
          None => None
          Some(previous) =>
            client_local_family_task_inventory(
              previous, provider, scratch, inputs, input_import_bytes, output_export_bytes,
              9223372036854775807L,
            )
        }
      }
      total
    }
  }
  Some({
    limits,
    provider_retained: retained_bytes,
    provider_execution: execution_bytes,
    simultaneous,
  })
}

///|
/// Whole-Run holding allowance for retained Local outputs. Inputs count ports,
/// not distinct producers: two ports can each require an independent import.
/// Use the installed provider ceiling for every task, just as family providers
/// do. Keep the existing finite admission ceiling; do not sample a successful
/// execution or drop a parent holding to manufacture a fitting reservation.
fn client_local_store_inventory(
  inputs : Array[Int],
  provider_bytes : Int64,
  import_bytes : Int64,
  export_bytes : Int64,
  max_bytes : Int64,
) -> (Int64, Int64)? {
  if provider_bytes < 0L ||
    import_bytes < 0L ||
    export_bytes < 0L ||
    max_bytes < 0L ||
    provider_bytes > max_bytes ||
    export_bytes > max_bytes - provider_bytes {
    return None
  }
  let per_task = provider_bytes + export_bytes
  let mut retained = 0L
  let mut ports = 0L
  for count in inputs {
    if count < 0 || per_task > max_bytes - retained {
      return None
    }
    retained += per_task
    // The division precheck avoids overflow even for rejected inventories.
    if count > 0 && import_bytes > (max_bytes - retained) / count.to_int64() {
      return None
    }
    retained += count.to_int64() * import_bytes
    ports += count.to_int64()
  }
  Some((retained, ports))
}

///|
/// Add one installed family task's complete reservation to the original Run.
/// A predecessor's reservation can still be held by its accepted borrower;
/// the next task therefore overlaps, rather than replacing the largest task.
/// Precheck each addition and multiplication before forming the totals.
fn client_local_family_task_inventory(
  previous : (Int64, Int64),
  provider_bytes : Int64,
  scratch_bytes : Int64,
  input_count : Int,
  import_bytes : Int64,
  export_bytes : Int64,
  max_bytes : Int64,
) -> (Int64, Int64)? {
  let (retained, executing) = previous
  if max_bytes < 0L ||
    retained < 0L ||
    executing < 0L ||
    retained > max_bytes ||
    executing > max_bytes ||
    provider_bytes < 0L ||
    scratch_bytes < 0L ||
    import_bytes < 0L ||
    export_bytes < 0L ||
    input_count < 0 ||
    scratch_bytes > max_bytes ||
    provider_bytes > max_bytes - retained ||
    export_bytes > max_bytes - retained - provider_bytes ||
    (
      input_count > 0 &&
      import_bytes >
      (max_bytes - retained - provider_bytes - export_bytes) /
      input_count.to_int64()
    ) {
    return None
  }
  let task_retained = provider_bytes +
    export_bytes +
    input_count.to_int64() * import_bytes
  if task_retained > max_bytes - scratch_bytes ||
    scratch_bytes + task_retained > max_bytes - executing {
    return None
  }
  Some((retained + task_retained, executing + scratch_bytes + task_retained))
}

///|
/// Keep the original checked Effect owner while sizing its Local suffix.
pub fn client_effect_local_ledger_limits(
  prepared : @publication_host.PreparedClientEffectComputation,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.LedgerLimits? {
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(prepared),
  )
  guard prepare_client_effect_local_sequences(
      prepared, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) else {
    return None
  }
  let compute = []
  for task in @strategy.graph_captured_prefix(graph)..<sequences.length() {
    compute.push(sequences[task])
  }
  client_local_sequence_capacity(compute, @strategy.graph_task_count(graph)).map(value => {
      value.0
    },
  )
}

///|
/// Size the actual registered family and its enclosing Relation chain before
/// Source I/O. The caller supplies the same installed execution ceilings used
/// to select the task; a metadata-only sequence allowance is not sufficient.
pub fn client_effect_family_ledger_limits(
  prepared : @publication_host.PreparedClientEffectComputation,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  families : Array[@local.ManagedProvider],
) -> @resources.LedgerLimits? {
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(prepared),
  )
  let count = @strategy.graph_task_count(graph)
  let first = @strategy.graph_captured_prefix(graph)
  if count < 1 || first < 0 || first >= count || families.is_empty() {
    return None
  }
  guard prepare_client_effect_local_sequences(
      prepared, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) &&
    sequences.length() == count else {
    return None
  }
  let mut retained = 0L
  let mut executing = 0L
  let mut ports = 0L
  // Reuse the existing retained-input and export allowances. Every consumer
  // port is retained independently, including repeated producer occurrences.
  let values = execution.rows.input_values
  let imports = client_local_import_limits(
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: execution.rows.max_rows,
      max_value_bytes: 10000,
      common_fragment: None,
    },
    values,
  )
  guard @local.local_import_retention_capacity(imports) is Some(import_bytes) &&
    @local.local_export_retention_capacity(
      client_local_export_limits(execution.rows.max_rows, values),
    )
    is Some(export_bytes) else {
    return None
  }
  let ceiling = client_local_joint_byte_ceiling()
  for task in first..<count {
    guard @local.local_bounded_relation_provider(
        execution,
        measurement,
        sequences[task],
        family=families,
      )
      is Some(provider) &&
      @local.managed_provider_capacity(provider, sequences[task])
      is Some(capacity) &&
      @strategy.graph_task_input_count(graph, task) is Some(inputs) else {
      return None
    }
    let bytes = @execution.execution_capacity_retained_bytes(capacity)
    let scratch = @execution.execution_capacity_execution_bytes(capacity)
    guard client_local_family_task_inventory(
        (retained, executing),
        bytes,
        scratch,
        inputs,
        import_bytes,
        export_bytes,
        ceiling,
      )
      is Some((next_retained, next_executing)) else {
      return None
    }
    // The installed managed driver advertises provider execution together
    // with retained provider output, each input import and output export.
    // Size that same overlap before acquisition, not just the provider core.
    retained = next_retained
    ports += inputs.to_int64()
    // A completed family can retain its original reservation until accepted
    // Model evidence reaches Store custody. Downstream tasks may borrow that
    // output meanwhile. Admit this overlap, not merely the largest task, and
    // do not force cleanup of an input owner to make the next task fit.
    executing = next_executing
  }
  Some({
    planning_work: 100000,
    attempts: count,
    holdings: count,
    transfer_bytes: ports * imports.wire.max_bytes.to_int64(),
    retained_bytes: retained,
    execution_bytes: executing,
  })
}

///|
/// Bind the actual selected Source capacity to this checked Effect graph and
/// retain acquisition plus all family consumers on one original Run ledger.
pub fn prepare_client_effect_family_capture_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  capacity : ClientInstalledCaptureCapacity,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  families : Array[@local.ManagedProvider],
) -> @resources.Ledger? {
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(prepared),
  )
  guard @strategy.graph_captured_prefix(graph) == 1 &&
    prepare_effect_local_query_requirement(
      prepared, 0, 0, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Ok(requirement) &&
    @planning.query_requirement_cid(requirement) ==
    @planning.query_requirement_cid(capacity.requirement) &&
    client_effect_family_ledger_limits(
      prepared, installed_contracts, values_body, fragment_body, ordered_body, execution,
      measurement, families,
    )
    is Some(limits) else {
    return None
  }
  let ceiling = client_local_joint_byte_ceiling()
  if transport_bytes < 0L ||
    transport_execution_bytes < 0L ||
    capacity.retained_bytes < 0L ||
    capacity.execution_bytes < 0L ||
    capacity.retained_bytes > ceiling - limits.retained_bytes ||
    capacity.execution_bytes > ceiling - transport_execution_bytes ||
    transport_bytes > 9223372036854775807L - limits.transfer_bytes {
    return None
  }
  @resources.create_ledger({
    ..limits,
    transfer_bytes: limits.transfer_bytes + transport_bytes,
    retained_bytes: limits.retained_bytes + capacity.retained_bytes,
    execution_bytes: Int64::max(
      limits.execution_bytes,
      capacity.execution_bytes + transport_execution_bytes,
    ),
  }).to_option()
}

///|
/// Size the existing Run ledger before physical acquisition. Native capture
/// capacities and all downstream retained outputs contribute to this one
/// bounded inventory; no allocation is represented by a synthetic zero.
pub fn prepare_multi_captured_local_ledger(
  prepared : @publication_host.PreparedClientProgram,
  acquisitions : Array[@duckdb_host.NativeHostConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  prepare_multi_captured_local_ledger_owned(
    Pure(prepared),
    acquisitions.map(@duckdb_host.native_capture_configuration),
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Use the same capacity and ledger owner while retaining the checked Effect
/// computation. Neither Source capture is copied or silently re-accounted.
pub fn prepare_multi_captured_effect_local_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  acquisitions : Array[@duckdb_host.NativeHostConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  prepare_multi_captured_local_ledger_owned(
    Effect(prepared),
    acquisitions.map(@duckdb_host.native_capture_configuration),
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
fn prepare_multi_captured_local_ledger_owned(
  owner : ClientLocalSequenceOwner,
  acquisitions : Array[@duckdb_host.CaptureConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  if acquisitions.length() != 2 {
    return None
  }
  let capacities = []
  for acquisition in acquisitions {
    guard @duckdb_host.configured_capture_capacity(acquisition)
      is Some(capacity) else {
      return None
    }
    capacities.push((capacity.retained_bytes, capacity.execution_bytes))
  }
  prepare_multi_captured_capacity_ledger_owned(
    owner, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
  )
}

///|
fn prepare_multi_captured_capacity_ledger_owned(
  owner : ClientLocalSequenceOwner,
  capacities : Array[(Int64, Int64)],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  match
    multi_captured_capacity_limits_owned(
      owner, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
      values_body, fragment_body, ordered_body,
    ) {
    None => None
    Some(limits) => @resources.create_ledger(limits).to_option()
  }
}

///|
/// The same checked inventory is used for legacy accounting and for an
/// already admitted operational Run. Deriving limits does not issue capacity.
fn multi_captured_capacity_limits_owned(
  owner : ClientLocalSequenceOwner,
  capacities : Array[(Int64, Int64)],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.LedgerLimits? {
  let graph = match owner {
    Pure(prepared) => @publication_host.prepared_client_graph(prepared)
    Effect(prepared) =>
      @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(prepared),
      )
  }
  guard prepare_client_local_sequences_owned(
      owner, installed_contracts, values_body, fragment_body, ordered_body,
    ).to_option()
    is Some(sequences) else {
    return None
  }
  multi_captured_capacity_limits_selected(
    graph, capacities, transport_bytes, transport_execution_bytes, sequences,
  )
}

///|
fn installed_source_compute_count(compute : Int, sources : Int) -> Int? {
  if compute < 0 || sources < 0 || sources > 2147483647 - compute {
    None
  } else {
    Some(compute + sources)
  }
}

///|
// Immutable selected-input half of the existing calculator. Planned callers
// already own these generated originals; no second preparation or quote is
// needed during their managed-parent construction.
fn multi_captured_capacity_limits_selected(
  graph : @strategy.CheckedDAG,
  capacities : Array[(Int64, Int64)],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  sequences : Array[@execution.GeneratedSequence],
  local_capacity? : ClientLocalSequenceCapacity? = None,
  source_inputs? : Bool = false,
) -> @resources.LedgerLimits? {
  let count = @strategy.graph_task_count(graph)
  let captured = @strategy.graph_captured_prefix(graph)
  let source_count = if source_inputs { capacities.length() } else { captured }
  if (captured < 1 && !source_inputs) ||
    captured > count ||
    source_count < 1 ||
    capacities.length() != source_count ||
    transport_bytes.length() != source_count ||
    transport_execution_bytes.length() != source_count {
    return None
  }
  guard installed_source_compute_count(
      count,
      if source_inputs {
        source_count
      } else {
        0
      },
    )
    is Some(attempts) else {
    return None
  }
  if sequences.length() != count {
    return None
  }
  for index, sequence in sequences {
    guard @strategy.graph_task_owner(graph, index) is Some(original) &&
      physical_equal(original, @execution.generated_sequence_owner(sequence)) else {
      return None
    }
  }
  let (_, execution, measurement) = client_local_execution_limits()
  let mut retained = 0L
  // The installed Local import offer reserves one existing wire envelope per
  // input occurrence. A branching graph can have more ports than tasks; do not
  // merge repeated producers' ports or discount later correspondence reads.
  let mut input_ports = 0L
  for task in captured..<count {
    guard @strategy.graph_task_input_count(graph, task) is Some(inputs) &&
      inputs >= 0 &&
      inputs.to_int64() <= 9223372036854775807L - input_ports else {
      return None
    }
    input_ports += inputs.to_int64()
  }
  let transfer_envelopes = Int64::max(count.to_int64(), input_ports)
  if transfer_envelopes > 9223372036854775807L / 1000000L {
    return None
  }
  let mut transfer = local_capacity
    .map(value => value.limits.transfer_bytes)
    .unwrap_or(transfer_envelopes * 1000000L)
  let mut execution_capacity = local_capacity
    .map(value => value.limits.execution_bytes)
    .unwrap_or(client_local_execution_byte_ceiling())
  for index in 0..<source_count {
    let (capture_retained, capture_execution) = capacities[index]
    if capture_retained < 0L ||
      capture_execution < 0L ||
      capture_retained > 9223372036854775807L - retained {
      return None
    }
    retained += capture_retained
    let bytes = transport_bytes[index]
    let scratch = transport_execution_bytes[index]
    if bytes < 0L ||
      bytes > 9223372036854775807L - transfer ||
      scratch < 0L ||
      scratch > 9223372036854775807L - capture_execution {
      return None
    }
    transfer += bytes
    let required_execution = scratch + capture_execution
    if source_inputs {
      if required_execution > 9223372036854775807L - execution_capacity {
        return None
      }
      execution_capacity += required_execution
    } else if required_execution > execution_capacity {
      execution_capacity = required_execution
    }
  }
  let native_retained = retained
  retained = 0L
  for task in captured..<count {
    if local_capacity is Some(_) {
      break
    }
    guard @execution.generated_sequence_capacity(
        sequences[task],
        execution,
        measurement,
      )
      is Some(capacity) else {
      return None
    }
    let bytes = @execution.execution_capacity_retained_bytes(capacity)
    if bytes < 0L || bytes > 9223372036854775807L - retained {
      return None
    }
    retained += bytes
  }
  // Preserve the existing Local import/output allowance in addition to,
  // rather than underneath, the independently held native inputs.
  let compute_retained = local_capacity
    .map(value => value.limits.retained_bytes)
    .unwrap_or(Int64::max(retained, 200000000L))
  if compute_retained > 9223372036854775807L - native_retained {
    return None
  }
  Some({
    planning_work: 100000,
    attempts,
    holdings: attempts,
    transfer_bytes: transfer,
    retained_bytes: native_retained + compute_retained,
    execution_bytes: execution_capacity,
  })
}

///|
/// An installed capture budget retains the selected acquisition's checked
/// requirement. The Host cannot supply unbound byte counts for a different
/// source occurrence.
struct ClientInstalledCaptureCapacity {
  requirement : @planning.QueryRequirement
  retained_bytes : Int64
  execution_bytes : Int64
  original_input : Bool
  acquisition : @row_source_host.RowAcquisition?
  provider : (@row_source_host.RowAcquisition, @execution.ExecutionCapacity)?
}

///|
/// Retain the checked pending envelope without selecting a realization or
/// granting a read. Restored Source custody uses this same installed budget.
pub fn installed_pending_duckdb_capture_capacity(
  pending : ClientDuckDBCaptureCapacity,
) -> ClientInstalledCaptureCapacity {
  {
    requirement: pending.requirement,
    retained_bytes: pending.retained_bytes,
    execution_bytes: pending.execution_bytes,
    original_input: false,
    acquisition: None,
    provider: None,
  }
}

///|
pub fn installed_capture_capacity_values(
  capacity : ClientInstalledCaptureCapacity,
) -> Array[Int64] {
  [capacity.retained_bytes, capacity.execution_bytes]
}

///|
/// Plan the single installed buffered Source and its retained Compute suffix
/// before acquisition. The same checked graph, generated sequences and store
/// inventory used by the Compute Host determine this allowance. It confers
/// neither Source permission nor a reservation on an existing ledger.
pub fn single_captured_local_ledger_limits(
  prepared : @publication_host.PreparedClientProgram,
  selected : @duckdb_host.NativeHostConfiguration,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.LedgerLimits? {
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  if @strategy.graph_captured_prefix(graph) != 1 || count < 2 {
    return None
  }
  guard prepare_local_query_requirement(
      prepared, 0, 0, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Ok(requirement) &&
    @planning.query_requirement_cid(requirement) ==
    @planning.query_requirement_cid(
      @duckdb_host.configured_capture_requirement(
        @duckdb_host.native_capture_configuration(selected),
      ),
    ) &&
    @duckdb_host.configured_native_capacity(selected) is Some(native) else {
    return None
  }
  guard single_captured_compute_limits(
      prepared, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Some(limits) else {
    return None
  }
  single_captured_capacity_limits(
    limits,
    (native.retained_bytes, native.execution_bytes),
  )
}

///|
fn single_captured_compute_limits(
  prepared : @publication_host.PreparedClientProgram,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.LedgerLimits? {
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  guard @strategy.graph_captured_prefix(graph) == 1 &&
    count >= 2 &&
    prepare_client_local_sequences(
      prepared, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) else {
    return None
  }
  let compute = []
  for task in 1..<sequences.length() {
    compute.push(sequences[task])
  }
  let inputs = Array::make(compute.length(), 0)
  for index in 0..<@strategy.graph_data_count(graph) {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    let consumer = @strategy.data_edge_consumer(edge) - 1
    if consumer >= 0 && consumer < inputs.length() {
      inputs[consumer] += 1
    }
  }
  client_local_sequence_capacity(
    compute,
    count,
    retained_inputs=Some(inputs),
    max_rows=@publication_host.prepared_client_values_max_rows(prepared),
  ).map(value => value.0)
}

///|
fn single_captured_capacity_limits(
  compute : @resources.LedgerLimits,
  native : (Int64, Int64),
) -> @resources.LedgerLimits? {
  // Keep the existing finite Local inventory ceiling. The Native receiver
  // remains live beside all completed outputs; it is not a substitute for
  // the suffix's import/output allowance.
  let ceiling = client_local_joint_byte_ceiling()
  if native.0 < 0L ||
    native.1 < 0L ||
    native.1 > ceiling ||
    compute.retained_bytes < 0L ||
    compute.retained_bytes > ceiling ||
    native.0 > ceiling - compute.retained_bytes ||
    compute.execution_bytes < 0L ||
    compute.execution_bytes > ceiling {
    return None
  }
  Some({
    ..compute,
    retained_bytes: compute.retained_bytes + native.0,
    // Keep the installed execution ceiling. The Root still admits each
    // overlapping Native/Compute reservation and the live physical workspace;
    // this inventory does not certify that every execution envelope fits.
    execution_bytes: compute.execution_bytes,
  })
}

///|
pub fn installed_duckdb_capture_capacity(
  selected : @duckdb_host.CaptureConfiguration,
) -> ClientInstalledCaptureCapacity? {
  guard @duckdb_host.configured_capture_capacity(selected) is Some(capacity) else {
    return None
  }
  Some({
    requirement: @duckdb_host.configured_capture_requirement(selected),
    retained_bytes: capacity.retained_bytes,
    execution_bytes: capacity.execution_bytes,
    original_input: false,
    acquisition: None,
    provider: None,
  })
}

///|
pub fn installed_row_capture_capacity(
  selected : @row_source_host.RowAcquisition,
) -> ClientInstalledCaptureCapacity? {
  let retained = @row_source_host.row_acquisition_retained_capacity(selected)
  let execution = @row_source_host.row_acquisition_execution_capacity(selected)
  if retained < 0L || execution < retained {
    return None
  }
  Some({
    requirement: @row_source_host.row_acquisition_requirement(selected),
    retained_bytes: retained,
    execution_bytes: execution,
    original_input: true,
    acquisition: Some(selected),
    provider: None,
  })
}

///|
/// One selected acquisition and its borrowed Content prefix use the same Run
/// ledger. Both live allocations are counted before acquisition begins; the
/// selected Source requirement must still match the original checked owner.
pub fn prepare_serialization_captured_ledger(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  capacity : ClientInstalledCaptureCapacity,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  prefix_retained_bytes : Int64,
  prefix_execution_bytes : Int64,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  guard (task == 0 || task == 1) &&
    prepare_local_query_requirement(
      prepared, 0, 0, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Ok(requirement) &&
    @planning.query_requirement_cid(requirement) ==
    @planning.query_requirement_cid(capacity.requirement) else {
    return None
  }
  let maximum = 9223372036854775807L
  if transport_bytes < 0L ||
    transport_execution_bytes < 0L ||
    prefix_retained_bytes < 0L ||
    prefix_execution_bytes < 0L ||
    capacity.retained_bytes < 0L ||
    capacity.execution_bytes < 0L ||
    capacity.retained_bytes > maximum - prefix_retained_bytes ||
    capacity.execution_bytes > maximum - prefix_execution_bytes {
    return None
  }
  let execution_bytes = capacity.execution_bytes + prefix_execution_bytes
  if transport_execution_bytes > maximum - execution_bytes {
    return None
  }
  @resources.create_ledger({
    planning_work: 100000,
    attempts: 2,
    holdings: 1,
    transfer_bytes: transport_bytes,
    retained_bytes: capacity.retained_bytes + prefix_retained_bytes,
    execution_bytes: execution_bytes + transport_execution_bytes,
  }).to_option()
}

///|
/// Admit one installed capture and its checked Compute suffix on the same
/// original Run ledger, before Source I/O. Capacity stays bound to the checked
/// requirement; neither this inventory nor the transport limits grant a read.
pub fn prepare_single_captured_local_installed_ledger(
  prepared : @publication_host.PreparedClientProgram,
  capacity : ClientInstalledCaptureCapacity,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  guard prepare_local_query_requirement(
      prepared, 0, 0, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Ok(requirement) &&
    @planning.query_requirement_cid(requirement) ==
    @planning.query_requirement_cid(capacity.requirement) &&
    single_captured_compute_limits(
      prepared, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Some(compute) &&
    single_captured_capacity_limits(
      compute,
      (capacity.retained_bytes, capacity.execution_bytes),
    )
    is Some(limits) else {
    return None
  }
  if transport_bytes < 0L ||
    transport_bytes > 9223372036854775807L - limits.transfer_bytes ||
    transport_execution_bytes < 0L ||
    transport_execution_bytes >
    limits.execution_bytes - capacity.execution_bytes {
    return None
  }
  @resources.create_ledger({
    ..limits,
    transfer_bytes: limits.transfer_bytes + transport_bytes,
  }).to_option()
}

///|
pub fn prepare_multi_captured_local_installed_ledger(
  prepared : @publication_host.PreparedClientProgram,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  prepare_multi_captured_installed_ledger_owned(
    Pure(prepared),
    capacities,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Effect inputs retain the same installed capture capacity and exact checked
/// occurrence as Pure inputs. This does not select or open either provider.
pub fn prepare_multi_captured_effect_installed_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  prepare_multi_captured_installed_ledger_owned(
    Effect(prepared),
    capacities,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
fn prepare_multi_captured_installed_ledger_owned(
  owner : ClientLocalSequenceOwner,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  match
    multi_captured_installed_limits_owned(
      owner, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
      values_body, fragment_body, ordered_body,
    ) {
    None => None
    Some(limits) => @resources.create_ledger(limits).to_option()
  }
}

///|
fn multi_captured_installed_limits_owned(
  owner : ClientLocalSequenceOwner,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.LedgerLimits? {
  let captured = @strategy.graph_captured_prefix(
    installed_managed_owner_graph(owner),
  )
  if captured < 1 || capacities.length() != captured {
    return None
  }
  for index in 0..<captured {
    let requirement = match owner {
      Pure(prepared) =>
        prepare_local_query_requirement(
          prepared, index, 0, installed_contracts, values_body, fragment_body, ordered_body,
        )
      Effect(prepared) =>
        prepare_effect_local_query_requirement(
          prepared, index, 0, installed_contracts, values_body, fragment_body, ordered_body,
        )
    }
    guard requirement is Ok(requirement) &&
      @planning.query_requirement_cid(requirement) ==
      @planning.query_requirement_cid(capacities[index].requirement) else {
      return None
    }
  }
  multi_captured_capacity_limits_owned(
    owner,
    capacities.map(value => (value.retained_bytes, value.execution_bytes)),
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Admit capacities from the exact selected Native or Broad preparations.
/// Broad's bounded residual remains under its original acquisition owner.
pub fn prepare_multi_captured_local_acquisition_ledger(
  prepared : @publication_host.PreparedClientProgram,
  acquisitions : Array[@duckdb_host.CaptureConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  prepare_multi_captured_local_ledger_owned(
    Pure(prepared),
    acquisitions,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Effect computation uses the same selected-configuration capacity owner.
pub fn prepare_multi_captured_effect_acquisition_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  acquisitions : Array[@duckdb_host.CaptureConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  prepare_multi_captured_local_ledger_owned(
    Effect(prepared),
    acquisitions,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Pending Sources contribute their checked candidate envelope before any
/// physical read. Later selection must fit that same envelope; no ledger is
/// replaced or reset when a read is approved.
pub fn prepare_multi_captured_effect_capacity_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  capacities : Array[ClientDuckDBCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  if capacities.length() != 2 {
    return None
  }
  for index in 0..<2 {
    guard prepare_effect_local_query_requirement(
        prepared, index, 0, installed_contracts, values_body, fragment_body, ordered_body,
      )
      is Ok(requirement) &&
      client_duckdb_capture_capacity_matches_requirement(
        capacities[index],
        requirement,
      ) else {
      return None
    }
  }
  prepare_multi_captured_capacity_ledger_owned(
    Effect(prepared),
    capacities.map(value => (value.retained_bytes, value.execution_bytes)),
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
pub fn prepare_multi_captured_local_capacity_ledger(
  prepared : @publication_host.PreparedClientProgram,
  capacities : Array[ClientDuckDBCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  if capacities.length() != 2 {
    return None
  }
  for index in 0..<2 {
    guard prepare_local_query_requirement(
        prepared, index, 0, installed_contracts, values_body, fragment_body, ordered_body,
      )
      is Ok(requirement) &&
      client_duckdb_capture_capacity_matches_requirement(
        capacities[index],
        requirement,
      ) else {
      return None
    }
  }
  prepare_multi_captured_capacity_ledger_owned(
    Pure(prepared),
    capacities.map(value => (value.retained_bytes, value.execution_bytes)),
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}
