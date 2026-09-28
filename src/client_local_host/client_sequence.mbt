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
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = task_count.unwrap_or(@strategy.graph_task_count(graph))
  if count < 1 || count > @strategy.graph_task_count(graph) {
    return None
  }
  let generated = []
  for task in 0..<count {
    guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
      return None
    }
    let acquiring = @publication_host.prepare_client_query_acquisition(
        prepared, task, 0,
      )
      is Ok(_)
    let sequence = match
      @lower.prepare_sequence(
        owner,
        @publication_host.client_standard_values_sequence_limits(),
      ) {
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
    let sequence = match
      @publication_host.prepare_client_task_sequence(
        prepared,
        task,
        contracts,
        contexts,
        @publication_host.client_standard_values_sequence_limits(),
        100000,
        10000,
        prepared_sequence=Some(sequence),
      ) {
      Ok(value) => value
      Err(_) => return None
    }
    generated.push(sequence)
  }
  Some(generated)
}
