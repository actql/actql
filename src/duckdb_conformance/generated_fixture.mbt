///|
// Fixed conformance construction through the real registry and fragment verifier.
fn fixture_generated(
  owner : @lower.BoundPrepared,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  filter : Bool,
) -> @execution.GeneratedSequence raise {
  let registry_limits : @execution.RegistryLimits = {
    max_body_bytes: 100000,
    max_body_nodes: 10000,
    max_body_depth: 100,
  }
  let registered = @execution.admit_relation_registry(
    fixture_contract(registry_json),
    fixture_contract(values_json),
    registry_limits,
  ).unwrap()
  let fragment = @execution.admit_fragment_contract(
    registered,
    fixture_contract(fragment_json),
    registry_limits,
  ).unwrap()
  let sequence = @lower.prepare_sequence(owner, {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
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
  let contexts = []
  if filter {
    for step in 0..<@lower.sequence_count(sequence) {
      let required = match @lower.sequence_step(sequence, step) {
        Some(@lower.RowStep(kernel)) =>
          match @lower.kernel_body(kernel) {
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
        _ => false
      }
      if required {
        let pipeline = @lower.prepare_fragment_pipeline(sequence, step, {
          max_roots: 100,
          max_pointer_bytes: 10000,
          max_work: 100000,
        }).unwrap()
        let request = @lower.prepare_fragment_request(pipeline, 100L, 1000L).unwrap()
        contexts.push(
          @execution.prepare_runtime_fragment(
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
              max_input_rows: 100L,
              max_value_bytes: 1000L,
              max_live_value_bytes: 10000L,
              max_work: 100000L,
            },
          ).unwrap(),
        )
      }
    }
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
