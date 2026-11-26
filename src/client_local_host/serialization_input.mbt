///|
/// Execute the original checked pure prefix using the existing Local managed
/// provider. No replacement Program, Source observation or serialization runtime
/// is created. The original Run ledger owns its reservation until the same
/// provider confirms cleanup, including after completed input is borrowed.
struct ClientSerializationPrefix {
  mut child : @local.ManagedProviderExecution?
  // Fixed controller DATA, not another owner/allowance or cleanup witness.
  // Preserve the child's actual validated total after its heavy alias retires.
  mut final_work : Result[Int64, @local.ManagedProviderWorkIssue]?
  mut cleanup_busy : Bool
  ledger : @resources.Ledger
  reservation : @resources.Reservation
  mut child_cleaned : Bool
  mut released : Bool
  // Exact upstream provider children, retained before their constructors.
  // They keep their outputs until this consumer has really cleaned up.
  dependencies : Array[ClientSerializationPrefix]
  mut pending_start : Bool
  mut parent_busy : Bool
  mut composed : ClientOriginalComposedKeyedPrefix?
}

///|
pub(all) enum ClientSerializationPrefixIssue {
  Unavailable
  Original(@publication_host.ClientModelReadPreparationIssue)
  Physical(@resources.LedgerIssue)
  Provider(@connector.FixedComputeIssue)
  Capture(@query.CapturedSourceIssue)
  ProducerRead(@execution.ProducerReadIssue)
}

///|
fn serialization_prefix_provider(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  acquired? : Bool = false,
  whole? : Bool = false,
  query_time? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )? = None,
) -> (
  @execution.GeneratedSequence,
  @local.ManagedProvider,
  @execution.ExecutionCapacity,
)? {
  if execution.max_work <= 0 ||
    execution.rows.max_rows < 0 ||
    measurement.max_bytes < 0 {
    return None
  }
  let sequence = if whole {
    prepare_client_serialization_prefix_owned(
      Pure(prepared),
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      query_time~,
    )
  } else if acquired {
    prepare_client_acquired_serialization_prefix(
      prepared,
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      query_time~,
    )
  } else {
    prepare_client_serialization_prefix(
      prepared,
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      query_time~,
    )
  }
  guard sequence is Some(sequence) &&
    @local.local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) &&
    @local.managed_provider_capacity(provider, sequence) is Some(capacity) else {
    return None
  }
  Some((sequence, provider, capacity))
}

///|
/// Derive from the same selected provider, not a Host guess or row sample.
pub fn client_serialization_prefix_capacity(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> @execution.ExecutionCapacity? {
  serialization_prefix_provider(
    prepared, task, step, installed_contracts, values_body, fragment_body, ordered_body,
    execution, measurement,
  ).map(value => value.2)
}

///|
pub fn start_client_serialization_prefix(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  workspace? : @execution.ExecutionCapacity? = None,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  guard serialization_prefix_provider(
      prepared, task, step, installed_contracts, values_body, fragment_body, ordered_body,
      execution, measurement,
    )
    is Some((sequence, provider, capacity)) else {
    return Err(Unavailable)
  }
  start_serialization_prefix_provider(
    sequence,
    provider,
    capacity,
    [],
    execution,
    measurement,
    ledger,
    workspace,
  )
}

///|
pub fn client_acquired_serialization_prefix_capacity(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> @execution.ExecutionCapacity? {
  serialization_prefix_provider(
    prepared,
    task,
    step,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    execution,
    measurement,
    acquired=true,
  ).map(value => value.2)
}

///|
/// Borrow the original live capture, never replay its acquisition operators.
/// The caller retains capture custody until this prefix confirms cleanup.
pub fn start_client_acquired_serialization_prefix(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  source : @query.CapturedInputSource,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  workspace? : @execution.ExecutionCapacity? = None,
  keyed? : @publication_host.ClientKeyedLookupInput? = None,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  start_client_acquired_serialization_prefix_owned(
    prepared,
    task,
    step,
    source,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    execution,
    measurement,
    ledger,
    workspace,
    keyed,
    None,
  )
}

///|
// Original capture custody is checked again after input-binding liveness
// callbacks and immediately before the existing reservation. Ordinary callers
// retain their previous entry; this is not a generic callback or new Owner.
fn start_client_acquired_serialization_prefix_owned(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  source : @query.CapturedInputSource,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  workspace : @execution.ExecutionCapacity?,
  keyed : @publication_host.ClientKeyedLookupInput?,
  original_capture : @row_source_host.RowSourceCapture?,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  let direct = match keyed {
    Some(lookup) => {
      let acquisition = @publication_host.client_keyed_lookup_acquisition(
        lookup,
      )
      guard @publication_host.client_keyed_acquisition_reaches_serialization(
          prepared, acquisition, task, step,
        ) &&
        @publication_host.client_keyed_direct_acquisition_coordinates(
          acquisition,
        )
        is Some((_, input, direct_task)) else {
        return Err(Unavailable)
      }
      (direct_task, input)
    }
    None => (0, 0)
  }
  guard serialization_prefix_provider(
      prepared,
      task,
      step,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      execution,
      measurement,
      acquired=true,
    )
    is Some((sequence, provider, capacity)) &&
    @publication_host.prepare_client_query_acquisition(
      prepared,
      direct.0,
      direct.1,
    )
    is Ok(query) else {
    return Err(Unavailable)
  }
  let inputs = match
    prepare_acquired_serialization_prefix_inputs(
      prepared, task, source, sequence, query, execution, measurement, ledger, keyed,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if original_capture is Some(capture) &&
    @row_source_host.row_capture_original_prefix_requirement(capture, ledger)
    is None {
    return Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState)),
    )
  }
  // Capacity addition and reserve_attempt below run synchronously and invoke
  // no capture/provider callback behind this final original-custody fence.
  start_serialization_prefix_provider(
    sequence, provider, capacity, inputs, execution, measurement, ledger, workspace,
  )
}

///|
// The existing input binding logic, with no prefix/provider reconstruction or
// reservation. Managed callers reserve and retain their original prefix BEFORE
// these liveness callbacks and input/row-buffer constructors can enter.
fn prepare_acquired_serialization_prefix_inputs(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  source : @query.CapturedInputSource,
  sequence : @execution.GeneratedSequence,
  original_query : @sourceviews.QueryAcquisition,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  keyed : @publication_host.ClientKeyedLookupInput?,
) -> Result[Array[@local.ManagedProviderInput], ClientSerializationPrefixIssue] {
  guard @sourceviews.query_acquisition_capture(original_query)
    is @pipeline.Step(capture) else {
    return Err(Unavailable)
  }
  let owner = @execution.generated_sequence_owner(sequence)
  let inputs : Array[@local.ManagedProviderInput] = []
  let keyed_step = match keyed {
    None => None
    Some(lookup) => {
      let (left, right) = match
        @publication_host.prepare_client_keyed_serialization_inputs(
          prepared, lookup, source, ledger, sequence,
        ) {
        Ok(value) => value
        Err(_) => return Err(Unavailable)
      }
      guard @publication_host.client_keyed_acquisition_coordinates(
          @publication_host.client_keyed_lookup_acquisition(lookup),
        )
        is Some((_, _, join)) else {
        return Err(Unavailable)
      }
      inputs.push(@local.managed_provider_relation_input(left))
      inputs.push(@local.managed_provider_supplied_relation_input(right))
      Some(join)
    }
  }
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    guard @execution.generated_sequence_step_index_at(sequence, index)
      is Some(consumer) &&
      @lower.node_at(@lower.bound_preparation(owner), consumer) is Some(node) else {
      return Err(Unavailable)
    }
    for port in 0..<@lower.node_input_count(node) {
      if keyed_step == Some(consumer) {
        continue
      }
      guard @lower.node_input_target(node, port) is Some(target) else {
        return Err(Unavailable)
      }
      if (task == 0 || keyed is Some(_)) &&
        target is @pipeline.Step(target) &&
        target > capture {
        continue
      }
      if task == 1 && target is @pipeline.Step(_) {
        continue
      }
      let bound = match
        (if task == 1 && target is @pipeline.Input(index) {
          @query.bind_captured_source(source, owner, index)
        } else {
          @query.bind_captured_source_operation(source, owner, consumer, port)
        }) {
        Ok(bound) => bound
        Err(issue) => return Err(Capture(issue))
      }
      let read = match
        @execution.prepare_producer_read(
          owner,
          bound,
          execution.rows.operation_entries,
          measurement.max_bytes,
        ) {
        Ok(read) => read
        Err(issue) => return Err(ProducerRead(issue))
      }
      inputs.push(@local.managed_provider_relation_input(read))
    }
  }
  Ok(inputs)
}

///|
// Capture order is the original shared Ledger's acquisition order. The
// checked receiving slots, not these array positions, select each input.
fn borrow_serialization_whole_captures(
  captures : Array[@row_source_host.RowSourceCapture],
  ledger : @resources.Ledger,
  max_work : Int,
) -> @row_source_host.RowCapturedInputs? {
  if max_work < 0 || captures.is_empty() || captures.length() > max_work / 2 {
    return None
  }
  let originals = []
  for capture in captures {
    guard @row_source_host.row_capture_input(capture) is Some(original) &&
      @row_source_host.row_captured_input_source_original(original) is Some(_) else {
      return None
    }
    originals.push(original)
  }
  @row_source_host.borrow_row_captured_input_originals(
    originals, ledger, max_work,
  )
}

///|
// Use the original supplied reads of Whole Source captures. Neither a
// Query/Keyed capture nor an earlier external Compute Step can stand in for
// a checked pipeline input. Internal edges continue through the same provider.
fn prepare_whole_serialization_prefix_inputs(
  prepared : @publication_host.PreparedClientProgram,
  sequence : @execution.GeneratedSequence,
  captures : @row_source_host.RowCapturedInputs,
  ledger : @resources.Ledger,
  occurrence? : Int? = None,
) -> Result[Array[@local.ManagedProviderInput], ClientSerializationPrefixIssue] {
  let owner = @execution.generated_sequence_owner(sequence)
  let lower = @lower.bound_preparation(owner)
  let program = @checked.source_identity(
    @strategy.graph_program(@publication_host.prepared_client_graph(prepared)),
  )
  let slots : Array[Int] = []
  let inputs : Array[@local.ManagedProviderInput] = []
  let count = @row_source_host.row_captured_inputs_count(captures)
  if occurrence is Some(index) && (index < 0 || index >= count) {
    return Err(Unavailable)
  }
  for index in 0..<count {
    if occurrence is Some(selected) && index != selected {
      continue
    }
    guard @row_source_host.row_captured_inputs_source_original_at(
        captures, index,
      )
      is Some(original) &&
      @sourceviews.source_acquisition_input(original) is @pipeline.Input(slot) &&
      !slots.contains(slot) &&
      @row_source_host.row_captured_inputs_source_at(captures, index)
      is Some(source) &&
      @query.captured_source_matches(source, program, owner) &&
      @query.captured_source_original_input_read(source) is Some(read) &&
      @execution.supplied_relation_read_matches_input(read, owner, slot) else {
      return Err(Unavailable)
    }
    slots.push(slot)
    inputs.push(@local.managed_provider_supplied_relation_input(read))
  }
  let mut used = 0
  let observed = Array::make(slots.length(), false)
  let steps : Array[Int] = []
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    guard @execution.generated_sequence_step_index_at(sequence, index)
      is Some(step) &&
      @lower.node_at(lower, step) is Some(node) else {
      return Err(Unavailable)
    }
    for port in 0..<@lower.node_input_count(node) {
      match @lower.node_input_target(node, port) {
        Some(@pipeline.Input(slot)) => {
          guard slots.search(slot) is Some(position) else {
            return Err(Unavailable)
          }
          if !observed[position] {
            observed[position] = true
            used += 1
          }
        }
        Some(@pipeline.Step(producer)) if steps.contains(producer) => ()
        _ => return Err(Unavailable)
      }
    }
    steps.push(step)
  }
  guard used == slots.length() &&
    used > 0 &&
    @row_source_host.row_captured_inputs_borrowed_available(captures, ledger) else {
    return Err(Unavailable)
  }
  Ok(inputs)
}

///|
priv struct ClientSerializationUpstream {
  sequence : @execution.GeneratedSequence
  target : @pipeline.Target
  input : Int
  nonexpanding : Bool
}

///|
priv struct ClientPricedSerializationUpstream {
  original : ClientSerializationUpstream
  provider : @local.ManagedProvider
  execution : @execution.SequenceExecutionLimits
  reclaims_scratch : Bool
}

///|
// The initial cross-stage route accepts one or two independent original
// captured Producers. Stage identity, target and receiving dependency all
// come from the checked graph, not from Source response shape.
fn terminal_serialization_upstream_edge(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  upstream : Int,
) -> (Int, @pipeline.Target)? {
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph) - 1
  guard count >= 1 &&
    count <= 2 &&
    upstream >= 0 &&
    upstream < count &&
    task == count &&
    @strategy.graph_captured_prefix(graph) == count &&
    @strategy.graph_task_input_count(graph, task) == Some(count) &&
    @strategy.graph_data_count(graph) == count &&
    @strategy.graph_task_owner(graph, upstream) is Some(owner) &&
    @lower.preparation_output_target(@lower.bound_preparation(owner))
    is Some(target) else {
    return None
  }
  let mut match_input = None
  let inputs : Array[Int] = []
  let producers : Array[Int] = []
  for index in 0..<count {
    guard @strategy.graph_data_at(graph, index) is Some(edge) &&
      @strategy.data_edge_consumer(edge) == task &&
      @strategy.data_edge_operation_input(edge) is None else {
      return None
    }
    let input = @strategy.data_edge_input(edge)
    let producer = @strategy.data_edge_producer(edge)
    guard input >= 0 &&
      input < count &&
      !inputs.contains(input) &&
      producer >= 0 &&
      producer < count &&
      !producers.contains(producer) else {
      return None
    }
    inputs.push(input)
    producers.push(producer)
    if producer == upstream {
      guard target == @strategy.data_edge_target(edge) else { return None }
      match_input = Some(input)
    }
  }
  match_input.map(input => (input, target))
}

///|
fn prepare_terminal_serialization_upstream(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  upstream : Int,
  contracts : ClientInstalledSequenceContracts,
) -> ClientSerializationUpstream? {
  guard terminal_serialization_upstream_edge(prepared, task, upstream)
    is Some((input, @pipeline.Step(step))) else {
    return None
  }
  let installed = contracts.original
  guard prepare_client_local_sequences_owned(
      Pure(prepared),
      contracts,
      installed.values_body,
      installed.fragment_body,
      installed.ordered_body,
      task_count=Some(upstream + 1),
      selected_task=Some(upstream),
      infer_prefix=Some((upstream, step)),
    )
    is Ok(sequences) &&
    sequences is [sequence] else {
    return None
  }
  let owner = @execution.generated_sequence_owner(sequence)
  let bound = @lower.bound_preparation(owner)
  let nonexpanding = @lower.preparation_input_count(bound) == 1 &&
    @execution.generated_sequence_all_steps(sequence, operation => {
      match operation {
        @lower.RowStep(kernel) =>
          @lower.kernel_is_projection(kernel) ||
          (match @lower.kernel_body(kernel) {
            @lower.Select(_)
            | @lower.Filter(_)
            | @lower.SnapshotMap(_)
            | @lower.OrderedBindings(_)
            | @lower.AssertAll(_)
            | @lower.AssertUnique(_)
            | @lower.StableSort(_)
            | @lower.TopK(_, _)
            | @lower.Limit(_, _, _) => true
            _ => false
          })
        _ => false
      }
    })
  Some({ sequence, target: @pipeline.Step(step), input, nonexpanding, })
}

///|
// A pure projection selects whole, already measured cells. Each input cell
// can be repeated at most once per output field. Include row containers and
// the existing three live-value views. Computed values retain the general cap.
fn terminal_serialization_projection_node_bound(
  sequence : @execution.GeneratedSequence,
  read : @execution.SuppliedRelationRead,
) -> Int? {
  let steps = @execution.generated_sequence_step_count(sequence)
  let input_fields = @schema.field_count(
    @execution.supplied_relation_read_schema(read),
  )
  let output_fields = match
    (steps, @execution.generated_sequence_step_at(sequence, 0)) {
    (0, None) => input_fields
    (1, Some(@lower.RowStep(kernel))) =>
      match @lower.kernel_projection(kernel) {
        Some(projection) => @lower.projection_field_count(projection)
        None => return None
      }
    _ => return None
  }
  guard @execution.supplied_relation_read_value_usage(read) is Some(usage) &&
    usage.nodes >= 0 &&
    @execution.checked_preparation_add_product(
      usage.nodes.to_int64(),
      @execution.supplied_relation_read_row_count(read).to_int64(),
      1L,
    )
    is Some(values) &&
    @execution.checked_preparation_add_product(
      1L,
      values,
      Int::max(1, Int::max(input_fields, output_fields)).to_int64() + 1L,
    )
    is Some(roots) &&
    @execution.checked_preparation_add_product(1L, roots, 3L) is Some(nodes) &&
    nodes <= 2147483647L else {
    return None
  }
  Some(nodes.to_int())
}

///|
// Retain both full physical extents, not a guessed scratch retirement. A
// proven non-expanding original Stage is bounded by its settled Source row
// count. No terminal generation cap or unmeasured row claim enters the proof.
fn price_terminal_serialization_upstreams(
  upstream : Array[ClientSerializationUpstream],
  inputs : Array[@local.ManagedProviderInput],
  base : @execution.ExecutionCapacity,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> (Array[ClientPricedSerializationUpstream], @execution.ExecutionCapacity)? {
  if upstream.length() != inputs.length() {
    return None
  }
  let mut total = base
  let mut reclaimable = 0L
  let priced = []
  for index, original in upstream {
    guard inputs[index] is @local.SuppliedRelationInput(read) else {
      return None
    }
    let count = @execution.supplied_relation_read_row_count(read)
    let projection_nodes = terminal_serialization_projection_node_bound(
      original.sequence,
      read,
    )
    let execution = if original.nonexpanding {
      let max_rows = Int::min(execution.rows.max_rows, Int::max(1, count))
      let rows = { ..execution.rows, max_rows, }
      // The existing complete-schema proof covers Text/Signed64 and
      // bounded references/containers, not just immediate numeric fields.
      // Its values are node bounds, never a claim about decoded text or
      // canonical wire. Unknown widths keep the installed node policy.
      let nodes = client_local_schema_proof_inventory(
        [original.sequence],
        scalar_only=false,
        leaf_only=true,
      ).bind(proof => client_local_inventory_nodes(proof, max_rows))
      let nodes = match (nodes, projection_nodes) {
        (Some(schema), Some(actual)) => Some(Int::min(schema, actual))
        (Some(schema), None) => Some(schema)
        (None, Some(actual)) => Some(actual)
        (None, None) => None
      }
      let rows = match nodes {
        None => rows
        Some(nodes) =>
          {
            ..rows,
            input_values: {
              ..rows.input_values,
              max_nodes: Int::min(rows.input_values.max_nodes, nodes),
            },
            output_values: {
              ..rows.output_values,
              max_nodes: Int::min(rows.output_values.max_nodes, nodes),
            },
          }
      }
      { ..execution, rows, }
    } else {
      execution
    }
    // A checked single alias/drop/rename stage can use the existing exact
    // selected-step provider recipe. The receiving Input and producer
    // completion keep their checked owners; the provider prices actual roots
    // rather than a general sequence's unused per-step metadata ceilings.
    let original = if projection_nodes is Some(_) &&
      @execution.generated_sequence_step_count(original.sequence) == 1 &&
      original.target is @pipeline.Step(step) &&
      @execution.select_generated_sequence_step(original.sequence, step)
      is Some(sequence) {
      { ..original, sequence, }
    } else {
      original
    }
    guard @local.local_bounded_relation_provider(
        execution,
        measurement,
        original.sequence,
      )
      is Some(provider) &&
      @local.managed_provider_capacity_for_execution(
        provider,
        original.sequence,
        execution,
        measurement,
      )
      is Some(extent) &&
      @execution.add_execution_capacity(total, extent) is Some(capacity) else {
      return None
    }
    // A single built-in projection (or identity reader) transfers its
    // accepted output independently of scratch. The terminal constructor
    // must observe its cleanup before spending the non-overlapping portion.
    // Every other provider keeps its conservative co-held execution extent.
    let reclaims_scratch = projection_nodes is Some(_) &&
      extent.execution_bytes >= extent.retained_bytes
    if reclaims_scratch {
      reclaimable += extent.execution_bytes - extent.retained_bytes
    }
    total = capacity
    priced.push({ original, provider, execution, reclaims_scratch, })
  }
  if reclaimable == 0L {
    return Some((priced, total))
  }
  // Before terminal start: all upstream workspaces and the standing common
  // metadata. After scratch acknowledgement: terminal plus all output
  // holdings, and any non-reclaimed upstream execution. Same reservation.
  guard @execution.checked_preparation_add_product(
      total.execution_bytes - base.execution_bytes,
      base.retained_bytes,
      1L,
    )
    is Some(upstream_peak) &&
    @execution.execution_capacity(
      total.retained_bytes,
      Int64::max(upstream_peak, total.execution_bytes - reclaimable),
    )
    is Some(peak) else {
    return None
  }
  Some((priced, peak))
}

///|
priv struct ClientSerializationUpstreamExecution {
  upstream : Array[@local.ManagedProviderExecution?]
  outputs : Array[@execution.CompletedOutput?]
  mut current : Int
  mut downstream : @local.ManagedProviderExecution?
  mut starting : Bool
  mut advancing : Bool
  mut cancelled : Bool
}

///|
fn advance_terminal_serialization_child(
  child : @local.ManagedProviderExecution,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  let result = @local.advance_managed_provider(child, quantum)
  match @local.managed_provider_cumulative_work(child) {
    Err(_) => Err(@connector.ControlWorkLimit)
    Ok(_) => result
  }
}

///|
fn advance_cancelled_serialization_upstream(
  children : ClientSerializationUpstreamExecution,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  let mut selected = children.downstream.filter(child => {
    !@local.managed_provider_stopped(child)
  })
  if selected is None {
    for child in children.upstream {
      if child is Some(run) && !@local.managed_provider_stopped(run) {
        selected = Some(run)
        break
      }
    }
  }
  guard selected is Some(run) else {
    return Ok(@local.managed_provider_stopped_poll(0L, 0L))
  }
  match advance_terminal_serialization_child(run, quantum) {
    Ok(@local.Complete(_, progress~, work~))
    | Ok(@local.CarrierComplete(_, progress~, work~))
    | Ok(@local.Stopped(progress~, work~)) =>
      Ok(@local.managed_provider_waiting(progress, work))
    other => other
  }
}

///|
fn advance_serialization_upstream(
  children : ClientSerializationUpstreamExecution,
  upstream : Array[ClientPricedSerializationUpstream],
  sequence : @execution.GeneratedSequence,
  provider : @local.ManagedProvider,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  // A child may report final completion with zero work. That is an internal
  // handoff, not a zero-work public continuation: enter the next ready
  // child with the same quantum. At most one nonzero poll is forwarded.
  for _ in 0..<=upstream.length() {
    if children.cancelled {
      return advance_cancelled_serialization_upstream(children, quantum)
    }
    if children.downstream is Some(run) {
      return advance_terminal_serialization_child(run, quantum)
    }
    guard children.upstream.get(children.current) is Some(Some(run)) else {
      return Err(@connector.InputUnavailable)
    }
    let poll = match advance_terminal_serialization_child(run, quantum) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    match poll {
      @local.Complete(output, progress~, work~) => {
        if children.cancelled {
          return Ok(@local.managed_provider_stopped_poll(progress, work))
        }
        if upstream[children.current].reclaims_scratch {
          match @local.cleanup_managed_provider(run) {
            Ok(true) if @execution.completed_output_available(output) =>
              children.upstream[children.current] = None
            Ok(_) => {
              children.cancelled = true
              return Ok(
                @local.managed_provider_failed(
                  @connector.InputUnavailable,
                  progress,
                  work,
                ),
              )
            }
            Err(issue) => {
              children.cancelled = true
              return Ok(@local.managed_provider_failed(issue, progress, work))
            }
          }
        }
        children.outputs[children.current] = Some(output)
        children.current += 1
        if children.current == upstream.length() {
          children.starting = true
          let result = start_terminal_serialization_from_upstream(
            upstream,
            children.outputs,
            sequence,
            provider,
            execution,
            measurement,
          )
          children.starting = false
          match result {
            Err(issue) => {
              children.cancelled = true
              return Ok(@local.managed_provider_failed(issue, progress, work))
            }
            Ok(next) => {
              children.downstream = Some(next)
              if children.cancelled {
                ignore(@local.cancel_managed_provider(next))
              }
            }
          }
        }
        if work > 0L {
          return Ok(@local.managed_provider_continue(progress, work))
        }
      }
      @local.CarrierComplete(_, progress~, work~) => {
        children.cancelled = true
        return Ok(
          @local.managed_provider_failed(
            @connector.UnsupportedInputShape,
            progress,
            work,
          ),
        )
      }
      _ => return Ok(poll)
    }
  }
  Err(@connector.InputUnavailable)
}

///|
// The original prefix reservation covers each physical phase before the
// first constructor. Acknowledged upstream scratch may retire early, but its
// accepted output remains retained until downstream cleanup.
fn start_retained_serialization_upstream(
  prefix : ClientSerializationPrefix,
  upstream : Array[ClientPricedSerializationUpstream],
  sequence : @execution.GeneratedSequence,
  provider : @local.ManagedProvider,
  inputs : Array[@local.ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[Unit, ClientSerializationPrefixIssue] {
  let count = upstream.length()
  guard count >= 1 && count <= 2 && inputs.length() == count else {
    return Err(Unavailable)
  }
  let children = ClientSerializationUpstreamExecution::{
    upstream: Array::make(count, None),
    outputs: Array::make(count, None),
    current: 0,
    downstream: None,
    starting: true,
    advancing: false,
    cancelled: false,
  }
  let child = @local.managed_provider_execution(
    quantum => {
      if children.advancing || children.starting {
        return Err(@connector.InputUnavailable)
      }
      children.advancing = true
      preparation_module_call(
        () => {
          advance_serialization_upstream(
            children, upstream, sequence, provider, execution, measurement, quantum,
          )
        },
        () => children.advancing = false,
      )
    },
    () => {
      children.cancelled = true
      let mut stopped = children.downstream
        .map(@local.cancel_managed_provider)
        .unwrap_or(true)
      for child in children.upstream {
        if child is Some(run) && !@local.cancel_managed_provider(run) {
          stopped = false
        }
      }
      !children.starting && !children.advancing && stopped
    },
    () => {
      !children.starting &&
      !children.advancing &&
      children.downstream.map(@local.managed_provider_stopped).unwrap_or(true) &&
      children.upstream.all(child => {
        child.map(@local.managed_provider_stopped).unwrap_or(true)
      })
    },
    () => {
      if children.starting || children.advancing {
        return Ok(false)
      }
      if children.downstream is Some(run) {
        match @local.cleanup_managed_provider(run) {
          Ok(true) => children.downstream = None
          other => return other
        }
      }
      for cursor in 0..<count {
        let index = count - 1 - cursor
        if children.upstream[index] is Some(run) {
          match @local.cleanup_managed_provider(run) {
            Ok(true) => children.upstream[index] = None
            other => return other
          }
        }
        children.outputs[index] = None
      }
      Ok(true)
    },
  )
  prefix.child = Some(child)
  for index, source in upstream {
    match
      @local.start_managed_provider_with_inputs_and_execution(
        source.provider,
        source.original.sequence,
        [inputs[index]],
        source.execution.rows.max_rows,
        measurement.max_bytes,
        source.execution,
      ) {
      Ok(run) => {
        children.upstream[index] = Some(run)
        if children.cancelled {
          ignore(@local.cancel_managed_provider(run))
          children.starting = false
          return Err(Unavailable)
        }
      }
      Err(issue) => {
        children.starting = false
        ignore(cancel_client_serialization_prefix(prefix))
        ignore(cleanup_client_serialization_prefix(prefix))
        return Err(Provider(issue))
      }
    }
  }
  children.starting = false
  Ok(())
}

///|
fn start_terminal_serialization_from_upstream(
  upstream : Array[ClientPricedSerializationUpstream],
  outputs : Array[@execution.CompletedOutput?],
  sequence : @execution.GeneratedSequence,
  provider : @local.ManagedProvider,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[@local.ManagedProviderExecution, @connector.FixedComputeIssue] {
  let receiver = @execution.generated_sequence_owner(sequence)
  let inputs = []
  for index, priced in upstream {
    let source = priced.original
    let producer = @execution.generated_sequence_owner(source.sequence)
    guard outputs[index] is Some(output) &&
      @execution.completed_output_matches_port(output, producer, source.target) &&
      @execution.bind_completed_input(receiver, source.input, producer, output)
      is Ok(bound) &&
      @execution.prepare_producer_read(
        receiver,
        bound,
        execution.rows.operation_entries,
        measurement.max_bytes,
      )
      is Ok(read) else {
      return Err(@connector.InputUnavailable)
    }
    inputs.push(@local.managed_provider_relation_input(read))
  }
  @local.start_managed_provider_with_inputs_and_execution(
    provider,
    sequence,
    inputs,
    execution.rows.max_rows,
    measurement.max_bytes,
    execution,
  )
}

///|
fn start_serialization_prefix_provider(
  sequence : @execution.GeneratedSequence,
  provider : @local.ManagedProvider,
  capacity : @execution.ExecutionCapacity,
  inputs : Array[@local.ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  ledger : @resources.Ledger,
  workspace : @execution.ExecutionCapacity?,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  let capacity = match workspace {
    None => capacity
    Some(workspace) =>
      match @execution.add_execution_capacity(capacity, workspace) {
        Some(combined) => combined
        None => return Err(Unavailable)
      }
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
  // Retain the original reservation BEFORE the fallible provider constructor.
  // None with child_cleaned=false remains pending if foreign code unwinds
  // without a returned child or a known no-child refusal. It is never an ACK.
  let prefix = serialization_prefix_reservation(ledger, reservation)
  start_retained_serialization_prefix_provider(
    prefix, sequence, provider, inputs, execution, measurement,
  )
}

///|
fn serialization_prefix_reservation(
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
) -> ClientSerializationPrefix {
  {
    child: None,
    final_work: None,
    cleanup_busy: false,
    ledger,
    reservation,
    child_cleaned: false,
    released: false,
    dependencies: [],
    pending_start: false,
    parent_busy: false,
    composed: None,
  }
}

///|
// The caller retained this exact reservation before any later original fence
// or fallible constructor. It does not observe current or reserve again.
fn start_retained_serialization_prefix_provider(
  prefix : ClientSerializationPrefix,
  sequence : @execution.GeneratedSequence,
  provider : @local.ManagedProvider,
  inputs : Array[@local.ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientSerializationPrefix, ClientSerializationPrefixIssue] {
  prefix.pending_start = false
  match
    @local.start_managed_provider_with_inputs_and_execution(
      provider,
      sequence,
      inputs,
      execution.rows.max_rows,
      measurement.max_bytes,
      execution,
    ) {
    Ok(child) => {
      prefix.child = Some(child)
      Ok(prefix)
    }
    Err(issue) => {
      // A rejected provider start supplies no allocated execution handle.
      prefix.child_cleaned = true
      match cleanup_client_serialization_prefix(prefix) {
        Ok(true) => Err(Provider(issue))
        Ok(false) => Err(Unavailable)
        Err(issue) => Err(issue)
      }
    }
  }
}

///|
pub fn advance_client_serialization_prefix(
  value : ClientSerializationPrefix,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if value.child_cleaned {
    return Ok(@local.managed_provider_stopped_poll(0L, 0L))
  }
  if value.cleanup_busy {
    return Err(@connector.Execution(@execution.InputSet))
  }
  match value.child {
    Some(child) => @local.advance_managed_provider(child, quantum)
    None => Err(@connector.Execution(@execution.InputSet))
  }
}

///|
/// The same child's cumulative observation remains readable after failure or
/// close. A failed advance can have consumed work even without a returned poll.
pub fn client_serialization_prefix_work(
  value : ClientSerializationPrefix,
) -> Result[Int64, @local.ManagedProviderWorkIssue] {
  let own = if value.final_work is Some(original) {
    original
  } else {
    match value.child {
      Some(child) => @local.managed_provider_cumulative_work(child)
      // No execution handle has returned. This is observed work only, not
      // proof of physical stop or of how much constructor CPU was consumed.
      None => Ok(0L)
    }
  }
  let mut total = match own {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for child in value.dependencies {
    let work = match client_serialization_prefix_work(child) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if work < 0L || total > 9223372036854775807L - work {
      return Err(@local.CounterOverflow)
    }
    total += work
  }
  Ok(total)
}

///|
pub fn cancel_client_serialization_prefix(
  value : ClientSerializationPrefix,
) -> Bool {
  if value.cleanup_busy || value.parent_busy {
    return false
  }
  let mut cancelled = false
  if value.pending_start {
    value.pending_start = false
    value.child_cleaned = true
    value.final_work = Some(Ok(0L))
    cancelled = true
  } else if !value.child_cleaned && value.child is Some(child) {
    cancelled = @local.cancel_managed_provider(child)
  }
  for child in value.dependencies {
    if cancel_client_serialization_prefix(child) {
      cancelled = true
    }
  }
  cancelled
}

///|
pub fn cleanup_client_serialization_prefix(
  value : ClientSerializationPrefix,
) -> Result[Bool, ClientSerializationPrefixIssue] {
  if value.released {
    return Ok(true)
  }
  if value.cleanup_busy || value.parent_busy {
    return Ok(false)
  }
  value.cleanup_busy = true
  preparation_module_call(
    () => {
      if value.pending_start {
        // No provider constructor was entered. This is a known absent child,
        // not an inference from missing output after a fallible callback.
        value.pending_start = false
        value.child_cleaned = true
        value.final_work = Some(Ok(0L))
      }
      if !value.child_cleaned {
        guard value.child is Some(child) else { return Ok(false) }
        match @local.cleanup_managed_provider(child) {
          Ok(true) => {
            value.child_cleaned = true
            // This getter is the same callback-free reported_work field read,
            // not a second current/stop/probe. Keep its exact Result (including
            // invalid/overflow) before dropping provider closures and inputs.
            value.final_work = Some(
              @local.managed_provider_cumulative_work(child),
            )
            value.child = None
          }
          Ok(false) => return Ok(false)
          Err(issue) => return Err(Provider(issue))
        }
      }
      // Main ACK precedes this cut. Its controller must not anchor Root
      // outputs or reads while an upstream reservation is being returned.
      // Dependencies retain the actual cleanup/work owners independently.
      if value.composed is Some(original) {
        retire_composed_keyed_prefix_input_aliases(original)
        value.composed = None
      }
      for index = value.dependencies.length() - 1; index >= 0; index = index - 1 {
        match cleanup_client_serialization_prefix(value.dependencies[index]) {
          Ok(true) => ()
          Ok(false) => return Ok(false)
          Err(issue) => return Err(issue)
        }
      }
      // Latch the same validated total before cutting upstream control aliases.
      // A later reservation-return failure may retry without replaying cleanup.
      if !value.dependencies.is_empty() {
        value.final_work = Some(client_serialization_prefix_work(value))
        value.dependencies.clear()
      }
      // Alias retirement follows the original child ACK, before this original
      // settlement can consume/fail. A failed return remains retryable here;
      // it never restores a child or repeats its spent cleanup duty.
      match @resources.settle_reservation(value.ledger, value.reservation) {
        Ok(_) => {
          value.released = true
          Ok(true)
        }
        Err(issue) => Err(Physical(issue))
      }
    },
    () => value.cleanup_busy = false,
  )
}
