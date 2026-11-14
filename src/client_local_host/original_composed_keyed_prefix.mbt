///|
// The existing managed prefix with its borrowed original port inventory.
// There is no second executor, admission or Ledger in this composition.
struct ClientOriginalComposedKeyedPrefix {
  prefix : ClientSerializationPrefix
  scope : @publication_host.ClientModelReadScope
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  plan : @publication_host.ClientInferPlanGraph
  keyed : @publication_host.ClientKeyedAcquisition
  sources : Array[@query.CapturedInputSource]
  mut captures : @row_source_host.RowCapturedInputs?
  sequence : @execution.GeneratedSequence
  mut inputs : Array[(Int, Int, @execution.ProducerRead)]
  mut output : @execution.CompletedOutput?
  mut left : @publication_host.ClientKeyedLeftRead?
  roots : Array[ClientComposedRootExecution]
  provider : @local.ManagedProvider
  capacity : @execution.ExecutionCapacity
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
  mut root_index : Int
  mut started : Bool
  control_bytes : Int64
  mut host : @strategy.CapturedEffectRunDAG?
  host_sources : Array[@sourceviews.SourceAcquisition]
}

///|
// This controller's records, copied input inventories and producer-column
// metadata only. Provider execution/output backing remains its existing quote.
// The pinned Array spare-capacity envelope covers both Native and JS metadata.
// No byte coefficient is an admission policy, transport cap or row prediction.
fn composed_keyed_root_control_bytes(
  sequences : Array[@execution.GeneratedSequence],
  producer_sources? : Int = 0,
  producer_tasks? : Int = 0,
) -> Int64? {
  let mut ports = 0L
  let mut columns = 0L
  for sequence in sequences {
    let owner = @execution.generated_sequence_owner(sequence)
    let prepared = @lower.bound_preparation(owner)
    for position in 0..<@execution.generated_sequence_step_count(sequence) {
      guard @execution.generated_sequence_step_index_at(sequence, position)
        is Some(step) &&
        @lower.node_at(prepared, step) is Some(node) else {
        return None
      }
      for port in 0..<@lower.node_input_count(node) {
        guard @lower.node_input_target(node, port) is Some(target) else {
          return None
        }
        if target is @pipeline.Input(_) {
          guard @lower.preparation_schema_at(prepared, target) is Some(schema) &&
            closed_values_append_capacity(@schema.field_count(schema))
            is Some(count) else {
            return None
          }
          ports += 1L
          columns += count
        }
      }
    }
  }
  let roots = sequences.length().to_int64()
  if roots == 0L {
    return Some(0L)
  }
  guard closed_values_append_capacity(sequences.length()) is Some(root_slots) &&
    ports < 2147483647L &&
    closed_values_append_capacity(ports.to_int()) is Some(port_slots) else {
    return None
  }
  // Main controller/prefix, dependent/root arrays, and original-retirement
  // back-reference/Some frames: 12H,30R,16W.
  // Each retained Root: driver+three Some frames, Core provenance, original
  // prefix+dependency Array, and the two completed-segment input copies.
  // Each external read: exact binding/identity, restricted completion/liveness,
  // ProducerRead, columns, tuple and copied port slots. One bounded read cursor
  // and return/Some frames coexist during construction (included in this peak).
  let original : @execution.PreparationRepresentationUnits = {
    record_headers: 12L + 16L * roots + 13L * ports,
    reference_slots: 30L +
    33L * roots +
    29L * ports +
    2L * root_slots +
    4L * port_slots,
    // Each retained producer also keeps its checked original task coordinate.
    scalar_words: 16L + 15L * roots + 23L * ports + columns,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  if producer_sources == 0 && producer_tasks == 0 {
    return @execution.preparation_representation_cost(original)
  }
  guard producer_sources > 0 &&
    producer_tasks > 0 &&
    producer_sources <= 2147483647 - producer_tasks &&
    @execution.preparation_array_representation(
      1L,
      (producer_sources + producer_tasks).to_int64(),
      false,
    )
    is Some(index) else {
    return None
  }
  // Input construction and retained-left construction do not overlap. Each
  // keeps one exact Source/task index plus its variant/Some frames. Their
  // copied producer vector uses the existing two Root-vector slot envelope:
  // caller map + retained copy, already simultaneous in the former left path.
  @execution.compose_preparation_representation([
    original,
    index,
    {
      record_headers: 2L,
      reference_slots: 3L,
      scalar_words: 2L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ]).bind(@execution.preparation_representation_cost)
}

///|
/// Same existing root/controller representation for a borrowed source prefix.
/// This includes the root/receiver read vectors, completion and retained-DAG
/// handoff tuples within the existing controller/port envelope. It quotes
/// controls only; the provider and its original parent fund rows.
pub fn client_composed_source_root_control_bytes(
  sequence : @execution.GeneratedSequence,
) -> Int64? {
  composed_keyed_root_control_bytes([sequence])
}

///|
// Controller state only: every execution remains the existing provider child
// retained by the same prefix cleanup tree, never another Run or Ledger.
priv struct ClientComposedRootExecution {
  slot : Int
  sequence : @execution.GeneratedSequence
  mut inputs : Array[(Int, Int, @execution.ProducerRead)]
  mut prefix : ClientSerializationPrefix?
  mut completed : @publication_host.ClientComposedKeyedProducer?
  mut capacity : @execution.ExecutionCapacity?
}

///|
pub fn start_client_original_composed_keyed_prefix(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowSourceCapture],
  input_prefix : @execution.GeneratedSequence,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  let inputs = rows.filter_map(@row_source_host.row_capture_input)
  if inputs.length() != rows.length() {
    return Err(Unavailable)
  }
  start_client_original_composed_keyed_prefix_owned(
    scope,
    compiled,
    definition,
    plan,
    keyed,
    inputs,
    input_prefix,
    execution,
    measurement,
    None,
  )
}

///|
// The shared ordinary Effect Run already owns its finite sequence and its
// one prefix slot. A failed constructor stays attached to that SAME owner.
pub fn start_installed_original_composed_keyed_input_prefix(
  owner : ClientInstalledManagedRun,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowCapturedInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  if owner.source_free_opening || owner.serialization_prefix is Some(_) {
    return Err(Unavailable)
  }
  owner.source_free_opening = true
  preparation_module_call(
    () => {
      guard require_installed_managed_run(owner) is Ok(_) &&
        owner.preparation is Some(PlannedEffectManaged(_, selected)) &&
        selected.model is Some(model) &&
        physical_equal(model.compiled, compiled) &&
        physical_equal(model.definition, definition) &&
        physical_equal(model.graph, plan) else {
        return Err(Unavailable)
      }
      let (task, _, _) = @publication_host.client_infer_occurrence_coordinates(
        model._occurrence,
      )
      guard selected.sequences.get(task) is Some(input_prefix) else {
        return Err(Unavailable)
      }
      start_client_original_composed_keyed_prefix_owned(
        scope,
        compiled,
        definition,
        plan,
        keyed,
        rows,
        input_prefix,
        execution,
        measurement,
        Some(owner),
        root_sequences=Some(selected.sequences),
      )
    },
    () => owner.source_free_opening = false,
  )
}

///|
fn start_client_original_composed_keyed_prefix_owned(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowCapturedInput],
  input_prefix : @execution.GeneratedSequence,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  installed : ClientInstalledManagedRun?,
  borrowed_inputs? : Bool = false,
  root_sequences? : Array[@execution.GeneratedSequence]? = None,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  let selected = @publication_host.borrow_client_original_composed_keyed_input_captures(
    scope,
    compiled,
    definition,
    plan,
    keyed,
    rows,
    installed=borrowed_inputs || installed is Some(_),
  )
  let (ledger, captures, sources) = match selected {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  let owner = @publication_host.client_keyed_acquisition_owner(keyed)
  guard @publication_host.client_keyed_acquisition_coordinates(keyed)
    is Some((_, _, join)) &&
    @lower.node_at(@lower.bound_preparation(owner), join) is Some(node) &&
    @lower.node_input_target(node, 0) is Some(@pipeline.Step(left)) &&
    left >= 0 &&
    left < join &&
    @execution.select_generated_sequence_range(input_prefix, 0, left)
    is Some(sequence) &&
    @local.local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) &&
    @local.managed_provider_capacity(provider, sequence) is Some(capacity) else {
    return Err(Unavailable)
  }
  let roots : Array[ClientComposedRootExecution] = []
  for slot, source in sources {
    if @row_source_host.row_captured_inputs_source_original_at(captures, slot)
      is Some(_) &&
      !@query.captured_source_matches(
        source,
        @checked.source_identity(
          @strategy.graph_program(
            @publication_host.prepared_client_graph(plan.owner),
          ),
        ),
        owner,
      ) {
      guard root_sequences is Some(sequences) &&
        @publication_host.select_client_direct_acquisition_occurrences(
          plan.owner,
          1000000,
        )
        is Ok(direct) &&
        @publication_host.client_direct_acquisition_occurrence_at(direct, slot)
        is Some((_, _, task)) &&
        sequences.get(task) is Some(root) else {
        return Err(Unavailable)
      }
      roots.push({
        slot,
        sequence: root,
        inputs: [],
        prefix: None,
        completed: None,
        capacity: None,
      })
    }
  }
  if !roots.is_empty() {
    guard installed is Some(original) &&
      require_installed_managed_run(original) is Ok(parent) &&
      physical_equal(parent, ledger) &&
      original.serialization_prefix is None else {
      return Err(Unavailable)
    }
    // No main provider is entered yet. Its original attempt/cleanup controller
    // is retained before upstream constructors; actual byte backing grows on
    // this same reservation before the main provider is eventually entered.
    let control_bytes = match
      composed_keyed_root_control_bytes(
        roots.map(root => root.sequence),
        producer_sources=sources.length(),
        producer_tasks=@strategy.graph_task_count(
          @publication_host.prepared_client_graph(plan.owner),
        ),
      ) {
      Some(value) => value
      None => return Err(Unavailable)
    }
    let reservation = match
      @resources.reserve_attempt(
        ledger,
        0L,
        control_bytes,
        control_bytes,
        quantities=@resources.quantity_neutral_amounts(ledger),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Physical(issue))
    }
    let prefix = serialization_prefix_reservation(ledger, reservation)
    prefix.pending_start = true
    original.serialization_prefix = Some(prefix)
    let value : ClientOriginalComposedKeyedPrefix = {
      prefix,
      scope,
      compiled,
      definition,
      plan,
      keyed,
      sources,
      captures: Some(captures),
      sequence,
      inputs: [],
      output: None,
      left: None,
      roots,
      provider,
      capacity,
      execution,
      measurement,
      root_index: 0,
      started: false,
      control_bytes,
      host: None,
      host_sources: [],
    }
    prefix.composed = Some(value)
    return Ok(value)
  }
  let inputs = match
    @publication_host.prepare_client_original_composed_keyed_inputs(
      scope,
      compiled,
      definition,
      plan,
      keyed,
      sources,
      captures,
      sequence,
      execution.rows.operation_entries,
      measurement.max_bytes,
    ) {
    Ok(value) => value
    Err(@publication_host.Capture(issue)) => return Err(Capture(issue))
    Err(@publication_host.Read(issue)) => return Err(ProducerRead(issue))
    Err(@publication_host.Physical(issue)) => return Err(Physical(issue))
    Err(_) => return Err(Unavailable)
  }
  let actual = inputs.map(value => {
    @local.managed_provider_relation_input(value.2)
  })
  // The existing constructor retains its reservation before calling the
  // provider. Both actual inputs stay borrowed until its real cleanup ACK.
  let started = match installed {
    None =>
      start_serialization_prefix_provider(
        sequence,
        provider,
        capacity,
        actual,
        execution,
        measurement,
        ledger,
        None,
      )
    Some(original) => {
      guard require_installed_managed_run(original) is Ok(parent) &&
        physical_equal(parent, ledger) &&
        original.serialization_prefix is None else {
        return Err(Unavailable)
      }
      let reservation = match
        @resources.reserve_attempt(
          ledger,
          0L,
          @execution.execution_capacity_retained_bytes(capacity),
          @execution.execution_capacity_execution_bytes(capacity),
          quantities=@resources.quantity_neutral_amounts(ledger),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Physical(issue))
      }
      let prefix = serialization_prefix_reservation(ledger, reservation)
      // The existing opening latch excludes retirement during reservation.
      // No callback follows retention before the fallible provider start.
      original.serialization_prefix = Some(prefix)
      start_retained_serialization_prefix_provider(
        prefix, sequence, provider, actual, execution, measurement,
      )
    }
  }
  started.map(prefix => {
    let value : ClientOriginalComposedKeyedPrefix = {
      prefix,
      scope,
      compiled,
      definition,
      plan,
      keyed,
      sources: sources.copy(),
      captures: Some(captures),
      sequence,
      inputs,
      output: None,
      left: None,
      roots,
      provider,
      capacity,
      execution,
      measurement,
      root_index: 0,
      started: true,
      control_bytes: 0L,
      host: None,
      host_sources: [],
    }
    prefix.composed = Some(value)
    value
  })
}

///|
// Called by the existing prefix cleanup after every actual provider ACK,
// before its fallible reservation return. No callback or second owner is added.
fn retire_composed_keyed_prefix_input_aliases(
  value : ClientOriginalComposedKeyedPrefix,
) -> Unit {
  value.output = None
  value.left = None
  value.inputs.clear()
  for root in value.roots {
    root.inputs.clear()
    root.completed = None
    root.prefix = None
  }
  value.roots.clear()
  value.sources.clear()
  value.captures = None
  value.host = None
  value.host_sources.clear()
}

///|
pub fn client_original_composed_keyed_prefix_execution(
  value : ClientOriginalComposedKeyedPrefix,
) -> ClientSerializationPrefix {
  value.prefix
}

///|
pub fn advance_client_original_composed_keyed_prefix(
  value : ClientOriginalComposedKeyedPrefix,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if value.prefix.parent_busy ||
    value.prefix.cleanup_busy ||
    value.prefix.child_cleaned {
    return Err(@connector.Execution(@execution.InputSet))
  }
  value.prefix.parent_busy = true
  preparation_module_call(
    () => advance_client_original_composed_keyed_prefix_owned(value, quantum),
    () => value.prefix.parent_busy = false,
  )
}

///|
fn advance_client_original_composed_keyed_prefix_owned(
  value : ClientOriginalComposedKeyedPrefix,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if !value.started {
    if value.root_index < value.roots.length() {
      let root = value.roots[value.root_index]
      if root.prefix is None {
        let inputs = match
          @publication_host.prepare_client_composed_keyed_producer_inputs(
            value.scope,
            value.compiled,
            value.definition,
            value.plan,
            value.keyed,
            value.sources,
            value.captures.unwrap(),
            root.slot,
            root.sequence,
            value.execution.rows.operation_entries,
            value.measurement.max_bytes,
          ) {
          Ok(inputs) => inputs
          Err(_) => return Err(@connector.Execution(@execution.InputSet))
        }
        root.inputs = inputs
        guard @local.local_bounded_relation_provider(
            value.execution,
            value.measurement,
            root.sequence,
          )
          is Some(provider) &&
          @local.managed_provider_capacity(provider, root.sequence)
          is Some(capacity) else {
          return Err(@connector.Execution(@execution.InputSet))
        }
        root.capacity = Some(capacity)
        let reservation = match
          @resources.reserve_attempt(
            value.prefix.ledger,
            0L,
            @execution.execution_capacity_retained_bytes(capacity),
            @execution.execution_capacity_execution_bytes(capacity),
            quantities=@resources.quantity_neutral_amounts(value.prefix.ledger),
          ) {
          Ok(value) => value
          Err(_) => return Err(@connector.Execution(@execution.InputSet))
        }
        let child = serialization_prefix_reservation(
          value.prefix.ledger,
          reservation,
        )
        root.prefix = Some(child)
        value.prefix.dependencies.push(child)
        match
          start_retained_serialization_prefix_provider(
            child,
            root.sequence,
            provider,
            inputs.map(value => @local.managed_provider_relation_input(value.2)),
            value.execution,
            value.measurement,
          ) {
          Ok(_) => ()
          Err(Provider(issue)) => return Err(issue)
          Err(_) => return Err(@connector.Execution(@execution.InputSet))
        }
      }
      let child = root.prefix.unwrap()
      let poll = match advance_client_serialization_prefix(child, quantum) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match poll {
        @local.Complete(output, work~, ..) => {
          let completed = match
            @publication_host.retain_client_composed_keyed_producer(
              value.scope,
              value.compiled,
              value.definition,
              value.plan,
              value.keyed,
              value.sources,
              value.captures.unwrap(),
              root.slot,
              root.sequence,
              root.inputs,
              output,
              child.reservation,
              100000,
            ) {
            Ok(value) => value
            Err(_) => return Err(@connector.Execution(@execution.InputSet))
          }
          root.completed = Some(completed)
          // Return only workspace the original provider reports as retired.
          // Its cleanup handle and real completed output remain retained.
          if child.child is Some(execution) &&
            @local.managed_provider_retained_completion(execution) {
            guard root.capacity is Some(capacity) else {
              return Err(@connector.Execution(@execution.InputSet))
            }
            match
              @resources.reduce_execution_reservation(
                child.ledger,
                child.reservation,
                @execution.execution_capacity_retained_bytes(capacity),
              ) {
              Ok(_) => ()
              Err(_) => return Err(@connector.Execution(@execution.InputSet))
            }
          }
          value.root_index += 1
          // Poll work is this bounded call's delta, not the cumulative total.
          // A zero-work terminal handoff can move to the next finite phase
          // without inventing a nonzero Continue or performing a second poll
          // against the completed child. The diagnostic getter sums originals.
          if work == 0L {
            return advance_client_original_composed_keyed_prefix_owned(
              value, quantum,
            )
          }
          return Ok(@local.managed_provider_continue(0L, work))
        }
        @local.CarrierComplete(_, ..) =>
          return Err(@connector.Execution(@execution.InputSet))
        _ => return Ok(poll)
      }
    }
    let producers = value.roots.map(root => root.completed.unwrap())
    let inputs = match
      @publication_host.prepare_client_original_composed_keyed_inputs(
        value.scope,
        value.compiled,
        value.definition,
        value.plan,
        value.keyed,
        value.sources,
        value.captures.unwrap(),
        value.sequence,
        value.execution.rows.operation_entries,
        value.measurement.max_bytes,
        producers~,
      ) {
      Ok(value) => value
      Err(_) => return Err(@connector.Execution(@execution.InputSet))
    }
    value.inputs = inputs
    match
      @resources.grow_execution_reservation_capacity(
        value.prefix.ledger,
        value.prefix.reservation,
        value.control_bytes +
        @execution.execution_capacity_retained_bytes(value.capacity),
        value.control_bytes +
        @execution.execution_capacity_execution_bytes(value.capacity),
      ) {
      Ok(_) => ()
      Err(_) => return Err(@connector.Execution(@execution.InputSet))
    }
    match
      start_retained_serialization_prefix_provider(
        value.prefix,
        value.sequence,
        value.provider,
        inputs.map(value => @local.managed_provider_relation_input(value.2)),
        value.execution,
        value.measurement,
      ) {
      Ok(_) => value.started = true
      Err(Provider(issue)) => return Err(issue)
      Err(_) => return Err(@connector.Execution(@execution.InputSet))
    }
  }
  let poll = match advance_client_serialization_prefix(value.prefix, quantum) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if poll is @local.Complete(output, ..) {
    guard @execution.retain_completed_segment_inputs(
        output,
        value.sequence,
        value.inputs,
        100000,
      )
      is Some(retained) &&
      @execution.completed_segment_inputs_output(
        retained,
        value.sequence,
        value.inputs,
      )
      is Some(actual) else {
      return Err(@connector.Execution(@execution.InputSet))
    }
    value.output = Some(actual)
  }
  Ok(poll)
}

///|
pub fn complete_client_original_composed_keyed_prefix(
  value : ClientOriginalComposedKeyedPrefix,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[
  @publication_host.ClientKeyedLeftRead,
  @publication_host.ClientKeyedRequestIssue,
] {
  if value.left is Some(_) {
    return Err(Assembly("original_prefix_already_bound"))
  }
  guard value.output is Some(output) else { return Err(ForeignLeft) }
  let work = match client_serialization_prefix_work(value.prefix) {
    Ok(value) => value
    Err(_) => return Err(Assembly("prefix_work_unavailable"))
  }
  @publication_host.prepare_client_original_composed_keyed_left(
    value.scope,
    value.compiled,
    value.definition,
    value.plan,
    value.keyed,
    value.sources,
    value.captures.unwrap(),
    value.sequence,
    value.inputs,
    output,
    value.prefix.reservation,
    work,
    max_entries,
    max_name_bytes,
    producers=value.roots.map(root => root.completed.unwrap()),
    host=value.host,
    host_sources=value.host_sources,
  ).map(left => {
    value.left = Some(left)
    left
  })
}

///|
pub fn start_installed_original_composed_keyed_prefix(
  owner : ClientInstalledManagedRun,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowSourceCapture],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  let inputs = rows.filter_map(@row_source_host.row_capture_input)
  if inputs.length() != rows.length() {
    return Err(Unavailable)
  }
  start_installed_original_composed_keyed_input_prefix(
    owner, scope, compiled, definition, plan, keyed, inputs, execution, measurement,
  )
}

///|
/// Start the existing keyed prefix from the SAME DAG's completed imported
/// Result ports, after its upstream Unit has actually executed. No Source or
/// upstream Unit provider is entered by this continuation.
pub fn start_installed_original_composed_keyed_host_prefix(
  owner : ClientInstalledManagedRun,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowCapturedInput],
  host : @strategy.CapturedEffectRunDAG,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  if owner.source_free_opening || owner.serialization_prefix is Some(_) {
    return Err(Unavailable)
  }
  owner.source_free_opening = true
  preparation_module_call(
    () => {
      guard require_installed_managed_run(owner) is Ok(ledger) &&
        owner.preparation is Some(PlannedEffectManaged(_, selected)) &&
        selected.model is Some(model) &&
        physical_equal(model.compiled, compiled) &&
        physical_equal(model.definition, definition) &&
        physical_equal(model.graph, plan) &&
        owner.source_free_captured is Some(run) &&
        physical_equal(run, @strategy.captured_effect_run_dag(host)) else {
        return Err(Unavailable)
      }
      let (task, _, _) = @publication_host.client_infer_occurrence_coordinates(
        model._occurrence,
      )
      guard @strategy.next_captured_task(run) == Some(task) &&
        selected.sequences.get(task) is Some(input_prefix) &&
        @publication_host.client_keyed_acquisition_coordinates(keyed)
        is Some((_, _, join)) &&
        @lower.node_at(
          @lower.bound_preparation(
            @execution.generated_sequence_owner(input_prefix),
          ),
          join,
        )
        is Some(node) &&
        @lower.node_input_target(node, 0) is Some(@pipeline.Step(left)) &&
        @execution.select_generated_sequence_prefix(input_prefix, left)
        is Some(sequence) &&
        @local.local_bounded_relation_provider(execution, measurement, sequence)
        is Some(provider) &&
        @local.managed_provider_capacity(provider, sequence) is Some(capacity) else {
        return Err(Unavailable)
      }
      let (original, captures, sources) = match
        @publication_host.borrow_client_original_composed_keyed_input_captures(
          scope,
          compiled,
          definition,
          plan,
          keyed,
          rows,
          installed=true,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Original(issue))
      }
      if !physical_equal(original, ledger) {
        return Err(Unavailable)
      }
      // The existing controller quote includes the retained input/read vectors.
      // Provider rows and execution overlap use its actual original capacity.
      guard composed_keyed_root_control_bytes([sequence]) is Some(control) else {
        return Err(Unavailable)
      }
      guard @execution.execution_capacity_inventory(
          [
            {
              unit: QuotedBytes,
              count: @execution.execution_capacity_retained_bytes(capacity),
              copies: 1,
            },
            { unit: QuotedBytes, count: control, copies: 1, },
          ],
          [
            {
              unit: QuotedBytes,
              count: @execution.execution_capacity_execution_bytes(capacity),
              copies: 1,
            },
            { unit: QuotedBytes, count: control, copies: 1, },
          ],
          @execution.RetainedAlongsideExecution,
        )
        is Some(backing) else {
        return Err(Unavailable)
      }
      let reservation = match
        @resources.reserve_attempt(
          ledger,
          0L,
          @execution.execution_capacity_retained_bytes(backing),
          @execution.execution_capacity_execution_bytes(backing),
          quantities=@resources.quantity_neutral_amounts(ledger),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Physical(issue))
      }
      let prefix = serialization_prefix_reservation(ledger, reservation)
      prefix.pending_start = true
      owner.serialization_prefix = Some(prefix)
      let inputs : Array[(Int, Int, @execution.ProducerRead)] = []
      for position in 0..<@execution.generated_sequence_step_count(sequence) {
        let step = @execution.generated_sequence_step_index_at(
          sequence, position,
        ).unwrap()
        let node = @lower.node_at(
          @lower.bound_preparation(
            @execution.generated_sequence_owner(sequence),
          ),
          step,
        ).unwrap()
        for port in 0..<@lower.node_input_count(node) {
          match @lower.node_input_target(node, port) {
            Some(@pipeline.Input(input)) => {
              let read = match
                @strategy.captured_task_input(
                  run,
                  task,
                  execution.rows.operation_entries,
                  measurement.max_bytes,
                  input_index=input,
                ) {
                Ok(value) => value
                Err(_) => return Err(Unavailable)
              }
              inputs.push((step, port, read))
            }
            Some(@pipeline.Step(previous)) if previous < step => ()
            _ => return Err(Unavailable)
          }
        }
      }
      let host_sources = sources
        .mapi((slot, _) => {
          @row_source_host.row_captured_inputs_source_original_at(
            captures, slot,
          )
        })
        .filter_map(value => value)
      if !@publication_host.client_composed_keyed_host_inputs_match(
          host, plan, ledger, sources, host_sources, inputs,
        ) {
        return Err(Unavailable)
      }
      let value : ClientOriginalComposedKeyedPrefix = {
        prefix,
        scope,
        compiled,
        definition,
        plan,
        keyed,
        sources,
        captures: Some(captures),
        sequence,
        inputs,
        output: None,
        left: None,
        roots: [],
        provider,
        capacity,
        execution,
        measurement,
        root_index: 0,
        started: true,
        control_bytes: control,
        host: Some(host),
        host_sources,
      }
      prefix.composed = Some(value)
      start_retained_serialization_prefix_provider(
        prefix,
        sequence,
        provider,
        inputs.map(input => @local.managed_provider_relation_input(input.2)),
        execution,
        measurement,
      ).map(_ => value)
    },
    () => owner.source_free_opening = false,
  )
}

///|
/// Select only a direct original imported Result. Step-left consumers return
/// None and continue through the existing original prefix constructor.
pub fn prepare_installed_original_composed_keyed_host_input_left(
  owner : ClientInstalledManagedRun,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowCapturedInput],
  host : @strategy.CapturedEffectRunDAG,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[
  @publication_host.ClientKeyedLeftRead?,
  @publication_host.ClientKeyedRequestIssue,
] {
  if owner.source_free_opening || owner.serialization_prefix is Some(_) {
    return Err(@publication_host.ForeignLeft)
  }
  guard require_installed_managed_run(owner) is Ok(_) &&
    owner.preparation is Some(PlannedEffectManaged(_, selected)) &&
    selected.model is Some(model) &&
    physical_equal(model.compiled, compiled) &&
    physical_equal(model.definition, definition) &&
    prepared_installed_effect_model_sequence(selected, plan) is Ok(sequence) &&
    owner.source_free_captured is Some(run) &&
    physical_equal(run, @strategy.captured_effect_run_dag(host)) else {
    return Err(@publication_host.ForeignLeft)
  }
  @publication_host.prepare_client_original_composed_keyed_host_input_left(
    scope, compiled, definition, plan, keyed, rows, host, sequence, max_entries,
    max_name_bytes,
  )
}
