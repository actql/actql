///|
/// Prepare the same checked task sequences for physical acquisition and
/// downstream Local compute. No Run or physical provider starts here.
pub fn prepare_client_local_sequences(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  task_count? : Int? = None,
) -> Array[@execution.GeneratedSequence]? {
  prepare_client_local_sequences_owned(
    Pure(prepared),
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    task_count~,
  )
}

///|
/// The Effectful caller retains its checked Effect closure while the same
/// physical sequence preparation handles the acquired root and Local tasks.
pub fn prepare_client_effect_local_sequences(
  prepared : @publication_host.PreparedClientEffectComputation,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  task_count? : Int? = None,
) -> Array[@execution.GeneratedSequence]? {
  prepare_client_local_sequences_owned(
    Effect(prepared),
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    task_count~,
  )
}

///|
priv enum ClientLocalSequenceOwner {
  Pure(@publication_host.PreparedClientProgram)
  Effect(@publication_host.PreparedClientEffectComputation)
}

///|
/// The same admitted invocation and request bind immutable sequence copies;
/// no clock is read and no selected provider or physical capacity is issued.
pub fn prepare_client_local_sequences_at_query_time(
  prepared : @publication_host.PreparedClientProgram,
  original : @publication_host.ClientQueryTimePreparation,
  request : @publication_host.ClientRequestIdentity,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Array[@execution.GeneratedSequence]? {
  prepare_client_local_sequences_owned(
    Pure(prepared),
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    query_time=Some((original, request)),
  )
}

///|
pub fn prepare_client_effect_local_sequences_at_query_time(
  prepared : @publication_host.PreparedClientEffectComputation,
  original : @publication_host.ClientQueryTimePreparation,
  request : @publication_host.ClientRequestIdentity,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Array[@execution.GeneratedSequence]? {
  prepare_client_local_sequences_owned(
    Effect(prepared),
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    query_time=Some((original, request)),
  )
}

///|
fn client_local_owner_sequence_limits(
  value : ClientLocalSequenceOwner,
) -> @lower.SequenceLimits {
  match value {
    Pure(prepared) =>
      @publication_host.prepared_client_values_sequence_limits(prepared)
    Effect(_) => @publication_host.client_standard_values_sequence_limits()
  }
}

///|
/// Prepare the exact pure Relation prefix consumed by an installed Infer.
/// The acquisition remains outside the generated Compute sequence, while
/// both halves retain the original bound Program invocation.
pub fn prepare_client_infer_prefix(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  registry_body : String,
  values_body : String,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> @execution.GeneratedSequence? {
  guard @publication_host.client_infer_prefix_owner(prepared, task, step)
    is Some(_) ||
    @publication_host.client_acquired_infer_prefix_owner(prepared, task, step)
    is Some(_) else {
    return None
  }
  prepare_client_local_sequences_owned(
    Pure(prepared),
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    task_count=Some(1),
    infer_prefix=Some((task, step - 1)),
  ).bind(sequences => sequences.get(0))
}

///|
/// Serialization uses the same registry, contexts and bounded Local prefix
/// preparation. This empty-input entry must not admit an acquired Source.
pub fn prepare_client_serialization_prefix(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @execution.GeneratedSequence? {
  let graph = @publication_host.prepared_client_graph(prepared)
  guard @strategy.graph_task_owner(graph, task) is Some(owner) &&
    @pipeline.input_count(@lower.pipeline(@lower.bound_preparation(owner))) == 0 else {
    return None
  }
  prepare_client_serialization_prefix_owned(
    Pure(prepared),
    task,
    step,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Select only the checked Compute after the original acquisition capture.
/// The caller must supply that capture through exact operation input bindings.
pub fn prepare_client_acquired_serialization_prefix(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @execution.GeneratedSequence? {
  if @publication_host.select_client_single_keyed_acquisition(prepared)
    is Ok(Some(keyed)) {
    // A split task ordinal is not the Direct acquisition coordinate. Retain
    // the same checked JOIN-to-Serialize path and select only the prefix after
    // its actual capture; no acquisition operation is executed a second time.
    guard @publication_host.client_keyed_acquisition_reaches_serialization(
        prepared, keyed, task, step,
      ) &&
      @publication_host.client_keyed_direct_acquisition_coordinates(keyed)
      is Some((_, input, direct_task)) &&
      @publication_host.prepare_client_query_acquisition(
        prepared, direct_task, input,
      )
      is Ok(query) &&
      @sourceviews.query_acquisition_capture(query) is @pipeline.Step(capture) &&
      prepare_client_serialization_prefix_owned(
        Pure(prepared),
        task,
        step,
        registry_body,
        values_body,
        fragment_body,
        ordered_body,
      )
      is Some(prefix) else {
      return None
    }
    let count = @execution.generated_sequence_step_count(prefix)
    guard count > 0 &&
      @execution.generated_sequence_step_index_at(prefix, count - 1)
      is Some(terminal) &&
      terminal > capture else {
      return None
    }
    return @execution.select_generated_sequence_range(
      prefix,
      capture + 1,
      terminal,
    )
  }
  if task == 1 {
    // The checked Stage producer is bound at runtime by bind_captured_source;
    // this is preparation of its consumer, not replay of the Source task.
    let graph = @publication_host.prepared_client_graph(prepared)
    guard @strategy.graph_task_count(graph) == 2 &&
      @strategy.graph_captured_prefix(graph) == 1 &&
      @strategy.graph_task_input_count(graph, task) == Some(1) else {
      return None
    }
    return prepare_client_serialization_prefix_owned(
      Pure(prepared),
      task,
      step,
      registry_body,
      values_body,
      fragment_body,
      ordered_body,
    )
  }
  guard @publication_host.prepare_client_query_acquisition(prepared, task, 0)
    is Ok(query) &&
    @sourceviews.query_acquisition_capture(query) is @pipeline.Step(capture) &&
    prepare_client_serialization_prefix_owned(
      Pure(prepared),
      task,
      step,
      registry_body,
      values_body,
      fragment_body,
      ordered_body,
    )
    is Some(prefix) else {
    return None
  }
  let count = @execution.generated_sequence_step_count(prefix)
  guard count > 0 &&
    @execution.generated_sequence_step_index_at(prefix, count - 1)
    is Some(terminal) &&
    terminal > capture else {
    return None
  }
  @execution.select_generated_sequence_range(prefix, capture + 1, terminal)
}

///|
/// Prepare the original Effect task's bounded prefix for its Content family.
/// DAG producer reads remain bound to this same receiver; this entry performs
/// no acquisition, generation, task reservation or Effect approval.
pub fn prepare_client_effect_serialization_prefix(
  prepared : @publication_host.PreparedClientEffectComputation,
  task : Int,
  step : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @execution.GeneratedSequence? {
  if @publication_host.prepared_client_effect_serialization_occurrences(
      prepared,
    ) !=
    [(task, step)] {
    return None
  }
  prepare_client_serialization_prefix_owned(
    Effect(prepared),
    task,
    step,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
fn prepare_client_serialization_prefix_owned(
  prepared : ClientLocalSequenceOwner,
  task : Int,
  step : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @execution.GeneratedSequence? {
  let (graph, barrier) = match prepared {
    Pure(value) =>
      (
        @publication_host.prepared_client_graph(value),
        @publication_host.prepare_client_serialization(
          value,
          task,
          step,
          max_work=10000,
        ),
      )
    Effect(value) =>
      (
        @strategy.checked_effect_computation_graph(
          @publication_host.prepared_client_effect_computation_graph(value),
        ),
        @publication_host.prepare_client_effect_serialization(
          value,
          task,
          step,
          max_work=10000,
        ),
      )
  }
  guard barrier is Ok(barrier) else { return None }
  let selected = @strategy.graph_task_selected_step(graph, task)
  if (selected is Some(index) && index != step) ||
    @pipeline.serialization_order_input(@lower.serialization_order(barrier)) !=
    @pipeline.Step(step - 1) {
    return None
  }
  prepare_client_local_sequences_owned(
    prepared,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    task_count=Some(task + 1),
    selected_task=Some(task),
    infer_prefix=Some(
      (
        task,
        if @pipeline.serialization_sort(@lower.serialization_checked(barrier))
          is Some(_) {
          step
        } else {
          step - 1
        },
      ),
    ),
    serialization_input=Some((task, barrier)),
  ).bind(sequences => sequences.get(0))
}

///|
/// Prepare only the Compute suffix for the same installed Infer occurrence.
/// The acquisition marker is retained for coordinates, never selected for
/// execution. Its completed output must be supplied through exact bindings.
pub fn prepare_client_infer_suffix(
  prepared : @publication_host.PreparedClientProgram,
  step : Int,
  registry_body : String,
  values_body : String,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> @execution.GeneratedSequence? {
  guard @publication_host.client_infer_prefix_owner(prepared, 0, step)
    is Some(_) ||
    @publication_host.client_acquired_infer_prefix_owner(prepared, 0, step)
    is Some(_) else {
    return None
  }
  prepare_client_local_sequences_owned(
    Pure(prepared),
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    task_count=Some(1),
    infer_suffix=Some((0, step)),
  ).bind(sequences => sequences.get(0))
}

///|
pub fn prepare_client_composed_infer_prefix(
  prepared : @publication_host.PreparedClientProgram,
  occurrence : @publication_host.ClientInferOccurrence,
  registry_body : String,
  values_body : String,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> @execution.GeneratedSequence? {
  if !@publication_host.client_infer_occurrence_matches(occurrence, prepared) {
    return None
  }
  prepare_owned_infer_segment(
    Pure(prepared),
    occurrence,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    false,
  )
}

///|
pub fn prepare_client_effect_infer_prefix(
  prepared : @publication_host.PreparedClientEffectComputation,
  occurrence : @publication_host.ClientInferOccurrence,
  registry_body : String,
  values_body : String,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> @execution.GeneratedSequence? {
  if !@publication_host.client_infer_occurrence_matches_effect(
      occurrence, prepared,
    ) {
    return None
  }
  prepare_owned_infer_segment(
    Effect(prepared),
    occurrence,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    false,
  )
}

///|
pub fn prepare_client_composed_infer_suffix(
  prepared : @publication_host.PreparedClientProgram,
  occurrence : @publication_host.ClientInferOccurrence,
  registry_body : String,
  values_body : String,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> @execution.GeneratedSequence? {
  if !@publication_host.client_infer_occurrence_matches(occurrence, prepared) {
    return None
  }
  prepare_owned_infer_segment(
    Pure(prepared),
    occurrence,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    true,
  )
}

///|
pub fn prepare_client_effect_infer_suffix(
  prepared : @publication_host.PreparedClientEffectComputation,
  occurrence : @publication_host.ClientInferOccurrence,
  registry_body : String,
  values_body : String,
  fragment_body? : String? = None,
  ordered_body? : String? = None,
) -> @execution.GeneratedSequence? {
  if !@publication_host.client_infer_occurrence_matches_effect(
      occurrence, prepared,
    ) {
    return None
  }
  prepare_owned_infer_segment(
    Effect(prepared),
    occurrence,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    true,
  )
}

///|
fn prepare_owned_infer_segment(
  prepared : ClientLocalSequenceOwner,
  occurrence : @publication_host.ClientInferOccurrence,
  registry : String,
  values : String,
  fragment : String?,
  ordered : String?,
  suffix : Bool,
) -> @execution.GeneratedSequence? {
  let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  if step < 1 {
    return None
  }
  prepare_client_local_sequences_owned(
    prepared,
    registry,
    values,
    fragment,
    ordered,
    selected_task=Some(task),
    infer_prefix=if suffix { None } else { Some((task, step - 1)) },
    infer_suffix=if suffix { Some((task, step)) } else { None },
  ).bind(sequences => sequences.get(0))
}

///|
/// The original checked acquisition determines its input and capture prefix.
/// Other inputs and downstream consumers stay in the same Program, but are
/// neither required nor executed by this physical acquisition preparation.
fn prepare_client_query_acquisition_prefix(
  prepared : ClientLocalSequenceOwner,
  task : Int,
  source_index : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  query_time? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )? = None,
) -> @execution.GeneratedSequence? {
  let query = match (prepared, query_time) {
    (Pure(value), Some((original, request))) =>
      @publication_host.prepare_client_query_acquisition_at_query_time(
        value, task, source_index, original, request,
      )
    (Effect(value), Some((original, request))) =>
      @publication_host.prepare_client_effect_query_acquisition_at_query_time(
        value, task, source_index, original, request,
      )
    (Pure(value), None) =>
      @publication_host.prepare_client_query_acquisition(
        value, task, source_index,
      )
    (Effect(value), None) =>
      @publication_host.prepare_client_effect_query_acquisition(
        value, task, source_index,
      )
  }
  guard query is Ok(query) &&
    @sourceviews.query_acquisition_capture(query) is @pipeline.Step(capture) else {
    return None
  }
  prepare_client_local_sequences_owned(
    prepared,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    task_count=Some(task + 1),
    selected_task=Some(task),
    infer_prefix=Some((task, capture)),
    acquisition_source=Some((task, source_index)),
    query_time~,
  ).bind(sequences => sequences.get(0))
}

///|
/// Prepare metadata for an authenticated saved pre-INFER output. Earlier
/// producer coordinates are non-executable boundaries, not a replay prefix.
fn prepare_client_restored_serialization_sequence(
  prepared : @publication_host.PreparedClientProgram,
  occurrence : @publication_host.ClientInferOccurrence,
  serialization_step : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @execution.GeneratedSequence? {
  let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  guard @strategy.graph_task_owner(graph, task) is Some(owner) &&
    physical_equal(
      owner,
      @publication_host.client_infer_occurrence_preparation(occurrence),
    ) else {
    return None
  }
  prepare_client_local_sequences_owned(
    Pure(prepared),
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    task_count=Some(task + 1),
    selected_task=Some(task),
    infer_prefix=Some((task, step - 1)),
    serialization_restore=Some((task, serialization_step, step)),
  ).bind(sequences => sequences.get(0))
}

///|
fn prepare_client_local_sequences_owned(
  prepared : ClientLocalSequenceOwner,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  task_count? : Int? = None,
  infer_prefix? : (Int, Int)? = None,
  infer_suffix? : (Int, Int)? = None,
  selected_task? : Int? = None,
  acquisition_source? : (Int, Int)? = None,
  serialization_input? : (Int, @lower.PreparedSerialization)? = None,
  serialization_restore? : (Int, Int, Int)? = None,
  query_time? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )? = None,
) -> Array[@execution.GeneratedSequence]? {
  if registry_body.length() > 100000 || values_body.length() > 100000 {
    return None
  }
  let registry_value = @identity.from_json(
    @json.parse(registry_body),
    10000,
    100,
    100000,
  ) catch {
    _ => return None
  }
  let values_value = @identity.from_json(
    @json.parse(values_body),
    10000,
    100,
    100000,
  ) catch {
    _ => return None
  }
  let contracts = match
    @execution.admit_relation_registry(registry_value, values_value, {
      max_body_bytes: 100000,
      max_body_nodes: 10000,
      max_body_depth: 100,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  let physical : @execution.RegistryLimits = {
    max_body_bytes: 100000,
    max_body_nodes: 10000,
    max_body_depth: 100,
  }
  let fragment_contract = match fragment_body {
    None => None
    Some(body) => {
      if body.length() > 100000 {
        return None
      }
      let value = @identity.from_json(@json.parse(body), 10000, 100, 100000) catch {
        _ => return None
      }
      match @execution.admit_fragment_contract(contracts, value, physical) {
        Ok(contract) => Some(contract)
        Err(_) => return None
      }
    }
  }
  let ordered_contract = match ordered_body {
    None => None
    Some(body) => {
      if body.length() > 100000 {
        return None
      }
      let value = @identity.from_json(@json.parse(body), 10000, 100, 100000) catch {
        _ => return None
      }
      match @execution.admit_ordered_contract(contracts, value, physical) {
        Ok(contract) => Some(contract)
        Err(_) => return None
      }
    }
  }
  let graph = match prepared {
    Pure(value) => @publication_host.prepared_client_graph(value)
    Effect(value) =>
      @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(value),
      )
  }
  let count = task_count.unwrap_or(@strategy.graph_task_count(graph))
  if count < 1 || count > @strategy.graph_task_count(graph) {
    return None
  }
  let generated = []
  let composed_boundaries = match prepared {
    Effect(value) =>
      match @publication_host.prepared_client_effect_infer_occurrence(value) {
        Some(occurrence) => [occurrence]
        None => []
      }
    Pure(value) =>
      @publication_host.prepared_client_composed_infer_occurrences(value).unwrap_or([],
      )
  }
  let serialization_boundaries = match prepared {
    Effect(value) =>
      @publication_host.prepared_client_effect_serialization_occurrences(value)
    Pure(value) =>
      @publication_host.prepared_client_serialization_occurrences(value)
  }
  // Each checked boundary still needs its installed provider. Retaining both
  // markers neither executes generation nor grants Model authorization.
  if serialization_boundaries.length() > 1 {
    return None
  }
  if selected_task is Some(task) && (task < 0 || task >= count) {
    return None
  }
  for task in 0..<count {
    let composed_boundary = composed_boundaries
      .filter(occurrence => {
        @strategy.graph_task_owner(graph, task)
        .map(owner => {
          physical_equal(
            owner,
            @publication_host.client_infer_occurrence_preparation(occurrence),
          )
        })
        .unwrap_or(false)
      })
      .get(0)
      .map(@publication_host.client_infer_occurrence_coordinates)
    let serialization_boundary = serialization_boundaries
      .filter(boundary => {
        @strategy.graph_task_owner(graph, boundary.0) is Some(boundary_owner) &&
        @strategy.graph_task_owner(graph, task) is Some(task_owner) &&
        physical_equal(boundary_owner, task_owner)
      })
      .get(0)
      .map(boundary => boundary.1)
    if selected_task is Some(selected) && task != selected {
      continue
    }
    guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
      return None
    }
    let source_index = match acquisition_source {
      Some((source_task, source_index)) if source_task == task => source_index
      _ => 0
    }
    let acquiring = match prepared {
      Pure(value) =>
        (match query_time {
          Some((original, request)) =>
            @publication_host.prepare_client_query_acquisition_at_query_time(
              value, task, source_index, original, request,
            )
          None =>
            @publication_host.prepare_client_query_acquisition(
              value, task, source_index,
            )
        })
        is Ok(_)
      Effect(value) =>
        (match query_time {
          Some((original, request)) =>
            @publication_host.prepare_client_effect_query_acquisition_at_query_time(
              value, task, source_index, original, request,
            )
          None =>
            @publication_host.prepare_client_effect_query_acquisition(
              value, task, source_index,
            )
        })
        is Ok(_)
    }
    // Whole serialization-prefix preparation retains the original acquisition
    // expression contexts even when the selected barrier has a later task
    // ordinal. Its execution range still excludes the completed capture.
    let acquiring = acquiring ||
      (match (serialization_input, prepared) {
        (Some((selected, _)), Pure(value)) if selected == task =>
          match
            @publication_host.select_client_single_keyed_acquisition(value) {
            Ok(Some(keyed)) =>
              @publication_host.client_keyed_acquisition_reaches_serialization(
                value,
                keyed,
                task,
                @strategy.graph_task_selected_step(graph, task).unwrap_or(-1),
              )
            _ => false
          }
        _ => false
      })
    let sequence = match
      (match serialization_restore {
        Some((selected, producer, consumer)) if selected == task =>
          @lower.prepare_serialization_infer_input_sequence(
            owner,
            producer,
            consumer,
            client_local_owner_sequence_limits(prepared),
          )
        _ =>
          match serialization_input {
            Some((serialization_task, barrier)) if task == serialization_task =>
              @lower.prepare_serialization_input_sequence(
                barrier,
                client_local_owner_sequence_limits(prepared),
              )
            _ =>
              match infer_prefix {
                Some((prefix_task, terminal)) if task == prefix_task =>
                  @lower.prepare_sequence_prefix(
                    owner,
                    terminal,
                    client_local_owner_sequence_limits(prepared),
                  )
                _ =>
                  match infer_suffix {
                    Some((suffix_task, step)) if suffix_task == task =>
                      @lower.prepare_sequence_with_infer_boundary(
                        owner,
                        step,
                        client_local_owner_sequence_limits(prepared),
                        serialization=serialization_boundary,
                      )
                    _ =>
                      match composed_boundary {
                        Some((_, _, step)) =>
                          @lower.prepare_sequence_with_infer_boundary(
                            owner,
                            step,
                            client_local_owner_sequence_limits(prepared),
                            serialization=serialization_boundary,
                          )
                        _ =>
                          match serialization_boundary {
                            Some(step) =>
                              @lower.prepare_sequence_with_serialization_boundary(
                                owner,
                                step,
                                client_local_owner_sequence_limits(prepared),
                              )
                            _ =>
                              @lower.prepare_sequence(
                                owner,
                                client_local_owner_sequence_limits(prepared),
                              )
                          }
                      }
                  }
              }
          }
      }) {
      Ok(value) => value
      Err(_) => return None
    }
    let contexts : Array[@execution.FragmentRuntimeContext] = []
    for step in 0..<@lower.sequence_count(sequence) {
      guard @lower.sequence_step(sequence, step) is Some(operation) else {
        return None
      }
      match operation {
        @lower.RowStep(kernel) => {
          let required = match @lower.kernel_body(kernel) {
            @lower.SnapshotMap(_)
            | @lower.OrderedBindings(_)
            | @lower.Filter(_)
            | @lower.AssertAll(_) => true
            @lower.Groups(group) => {
              let mut found = false
              for aggregate = 0
                  aggregate < @lower.group_aggregate_count(group)
                  aggregate = aggregate + 1 {
                if @lower.group_aggregate_requires_expression_context(
                    @lower.group_aggregate_at(group, aggregate).unwrap(),
                  ) {
                  found = true
                }
              }
              found
            }
            @lower.AnalyticRows(analytic) =>
              @lower.analytic_requires_expression_context(analytic)
            _ => false
          }
          if !required {
            continue
          }
          guard fragment_contract is Some(contract) else { return None }
          let fragment = match
            @lower.prepare_fragment_pipeline(sequence, step, {
              max_roots: 100,
              max_pointer_bytes: 10000,
              max_work: 100000,
            }) {
            Ok(value) => value
            Err(_) => return None
          }
          // Work covers measuring every value these rows admit, with a small
          // constant per byte. Live values are charged in the execution
          // capacity (264 units each): an acquisition stage's residual
          // evaluates the whole capture at once (up to 500 KB, the most one
          // acquisition captures), while a compute stage keeps one
          // evaluation's bound so several tasks fit the Run's budget.
          let logical : @lower.FragmentRowLimits = {
            max_input_rows: 100L,
            max_value_bytes: 10000L,
            max_live_value_bytes: if acquiring {
              500000L
            } else {
              100000L
            },
            max_work: 10000000L,
          }
          let ordered = @lower.kernel_body(kernel) is @lower.OrderedBindings(_)
          let request = match
            @lower.prepare_fragment_request(
              fragment,
              100L,
              10000L,
              row_limits=if ordered { Some(logical) } else { None },
            ) {
            Ok(value) => value
            Err(_) => return None
          }
          let context = match
            @execution.prepare_runtime_fragment(
              request,
              contract,
              {
                max_roots: 100,
                max_nodes: 10000,
                max_work: 100000,
                max_text_bytes: 10000,
                max_links: 10000,
              },
              physical,
              logical,
              ordered=if ordered { ordered_contract } else { None },
            ) {
            Ok(value) => value
            Err(_) => return None
          }
          contexts.push(context)
        }
        _ => ()
      }
    }
    let outcome = if infer_suffix is Some((suffix_task, boundary)) &&
      task == suffix_task {
      let last = @lower.sequence_count(sequence) - 1
      guard last > boundary &&
        @lower.node_at(@lower.bound_preparation(owner), last) is Some(node) else {
        return None
      }
      @execution.prepare_generated_sequence(
        contracts,
        sequence,
        contexts,
        [@lower.node_id(node)],
        100000,
        10000,
      ).map_err(issue => {
        @publication_host.ClientTaskSequenceIssue::Generated(issue)
      })
    } else if infer_prefix is Some((prefix_task, terminal)) &&
      task == prefix_task {
      guard @lower.node_at(@lower.bound_preparation(owner), terminal)
        is Some(node) else {
        return None
      }
      @execution.prepare_generated_sequence(
        contracts,
        sequence,
        contexts,
        [@lower.node_id(node)],
        100000,
        10000,
      ).map_err(issue => {
        @publication_host.ClientTaskSequenceIssue::Generated(issue)
      })
    } else {
      match prepared {
        Pure(value) =>
          @publication_host.prepare_client_task_sequence(
            value,
            task,
            contracts,
            contexts,
            client_local_owner_sequence_limits(prepared),
            100000,
            10000,
            prepared_sequence=Some(sequence),
          )
        Effect(value) =>
          @publication_host.prepare_client_effect_task_sequence(
            value,
            task,
            contracts,
            contexts,
            client_local_owner_sequence_limits(prepared),
            100000,
            10000,
            prepared_sequence=Some(sequence),
          )
      }
    }
    let sequence = match outcome {
      Ok(value) => value
      Err(_) => return None
    }
    let sequence = if infer_suffix is Some((suffix_task, boundary)) &&
      task == suffix_task {
      guard @execution.select_generated_sequence_range(
          sequence,
          boundary + 1,
          @strategy.graph_task_prefix_end(graph, task).unwrap_or(
            @execution.generated_sequence_step_count(sequence) - 1,
          ),
        )
        is Some(selected) else {
        return None
      }
      selected
      // A segmented graph task executes and retains only its exact operation.
      // Reserving the whole authored Stage for every selected task would count
      // unrelated siblings repeatedly and could also expose the wrong terminal.
      // Explicit prefix/suffix preparations keep their own checked ranges.
    } else if infer_prefix is None &&
      acquisition_source is None &&
      serialization_input is None &&
      serialization_restore is None &&
      @strategy.graph_task_selected_step(graph, task) is Some(step) {
      guard @execution.select_generated_sequence_step(sequence, step)
        is Some(selected) else {
        return None
      }
      selected
    } else {
      sequence
    }
    let sequence = match query_time {
      None => sequence
      Some((original, request)) => {
        let bound = match prepared {
          Pure(value) =>
            @publication_host.bind_client_query_time_sequence(
              value, task, sequence, original, request, 100000, 10000,
            )
          Effect(value) =>
            @publication_host.bind_client_effect_query_time_sequence(
              value, task, sequence, original, request, 100000, 10000,
            )
        }
        match bound {
          Ok(value) => value
          Err(_) => return None
        }
      }
    }
    generated.push(sequence)
  }
  Some(generated)
}
