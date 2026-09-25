///|
// Example application wiring through the public registry and fragment verifier.
fn generate(
  owner : @lower.BoundPrepared,
  registered : @execution.RegisteredRelationContracts,
  fragment : @execution.FragmentContract,
  filter : Bool,
  data? : DataProfile? = None,
  acquisition? : Bool = false,
) -> @execution.GeneratedSequence {
  let row_limit = data
    .map(value => if acquisition { value.source_rows } else { value.task_rows })
    .unwrap_or(100)
  let value_limit = data.map(value => value.value_bytes).unwrap_or(1000)
  let work_limit = data.map(value => value.work).unwrap_or(100000)
  let registry_limits : @execution.RegistryLimits = {
    max_body_bytes: 100000,
    max_body_nodes: 10000,
    max_body_depth: 100,
  }
  let sequence = @lower.prepare_sequence(owner, {
    max_steps: 100,
    max_rows: row_limit,
    max_cells: data.map(value => row_limit * value.columns).unwrap_or(10000),
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
  let direct_count = @lower.sequence_step(sequence, 0)
    is Some(@lower.RowStep(kernel)) &&
    @lower.kernel_count_group(kernel) is Some(_)
  let direct_join = @lower.sequence_step(sequence, 0)
    is Some(@lower.JoinStep(_))
  let contexts = if filter && !direct_count && !direct_join {
    let pipeline = @lower.prepare_fragment_pipeline(sequence, 0, {
      max_roots: 100,
      max_pointer_bytes: 10000,
      max_work: 100000,
    }).unwrap()
    let request = @lower.prepare_fragment_request(
      pipeline,
      row_limit.to_int64(),
      value_limit.to_int64(),
    ).unwrap()
    let context = @execution.prepare_runtime_fragment(
      request,
      fragment,
      {
        max_roots: 100,
        max_nodes: 1000,
        max_work: 100000,
        max_text_bytes: 100000,
        max_links: 10000,
      },
      registry_limits,
      {
        max_input_rows: row_limit.to_int64(),
        max_value_bytes: value_limit.to_int64(),
        max_live_value_bytes: data
        .map(value => value.wire_bytes.to_int64())
        .unwrap_or(10000L),
        max_work: work_limit.to_int64(),
      },
    ).unwrap()
    [context]
  } else {
    []
  }
  @execution.prepare_generated_sequence(
    registered,
    sequence,
    contexts,
    [
      @lower.node_id(
        @lower.node_at(
          @lower.bound_preparation(owner),
          @pipeline.step_count(@lower.pipeline(@lower.bound_preparation(owner))) -
          1,
        ).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
}
