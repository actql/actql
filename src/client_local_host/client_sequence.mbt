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
/// Physical source capture ends at its own checked filter/select boundary.
/// The remaining pre-INFER steps belong to Local, not to the source adapter.
fn prepare_client_infer_acquisition_prefix(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  step : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @execution.GeneratedSequence? {
  guard @publication_host.client_acquired_infer_prefix_owner(
      prepared, task, step,
    )
    is Some(_) &&
    @publication_host.prepare_client_query_acquisition(prepared, task, 0)
    is Ok(query) &&
    @sourceviews.query_acquisition_capture(query) is @pipeline.Step(capture) &&
    capture < step else {
    return None
  }
  prepare_client_local_sequences_owned(
    Pure(prepared),
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
    task_count=Some(1),
    infer_prefix=Some((task, capture)),
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
  let composed_boundary = match prepared {
    Effect(value) =>
      @publication_host.prepared_client_effect_infer_occurrence(value).map(
        @publication_host.client_infer_occurrence_coordinates,
      )
    Pure(_) => None
  }
  if selected_task is Some(task) && (task < 0 || task >= count) {
    return None
  }
  for task in 0..<count {
    if selected_task is Some(selected) && task != selected {
      continue
    }
    guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
      return None
    }
    let acquiring = match prepared {
      Pure(value) =>
        @publication_host.prepare_client_query_acquisition(value, task, 0)
        is Ok(_)
      Effect(value) =>
        @publication_host.prepare_client_effect_query_acquisition(
          value, task, 0,
        )
        is Ok(_)
    }
    let sequence = match
      (match infer_prefix {
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
              )
            _ =>
              match composed_boundary {
                Some((infer_task, _, step)) if infer_task == task =>
                  @lower.prepare_sequence_with_infer_boundary(
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
          @execution.generated_sequence_step_count(sequence) - 1,
        )
        is Some(selected) else {
        return None
      }
      selected
    } else {
      sequence
    }
    generated.push(sequence)
  }
  Some(generated)
}
