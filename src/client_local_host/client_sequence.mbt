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
  let graph = @publication_host.prepared_client_graph(prepared)
  // This initial connection has no external inputs or earlier task outputs.
  // Refuse other shapes at preparation, before provider work begins.
  guard task == 0 &&
    @strategy.graph_task_count(graph) == 1 &&
    step > 0 &&
    @strategy.graph_task_owner(graph, task) is Some(owner) &&
    @lower.preparation_input_count(@lower.bound_preparation(owner)) == 0 &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(_) &&
    @lower.node_input_target(node, 0) == Some(@pipeline.Step(step - 1)) else {
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
fn prepare_client_local_sequences_owned(
  prepared : ClientLocalSequenceOwner,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  task_count? : Int? = None,
  infer_prefix? : (Int, Int)? = None,
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
  for task in 0..<count {
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
            @publication_host.client_standard_values_sequence_limits(),
          )
        _ =>
          @lower.prepare_sequence(
            owner,
            @publication_host.client_standard_values_sequence_limits(),
          )
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
    let outcome = if infer_prefix is Some((prefix_task, terminal)) &&
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
            @publication_host.client_standard_values_sequence_limits(),
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
            @publication_host.client_standard_values_sequence_limits(),
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
    generated.push(sequence)
  }
  Some(generated)
}
