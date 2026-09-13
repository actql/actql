///|
// Conformance-only authoring input. The producer is executed and completed by
// the ordinary engine; no captured handle is reconstructed from wire data.
#export_name("typedFixedCreate")
pub fn typed_fixed_create(
  source : String,
  predicate : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
) -> OwnedFixedFixture {
  try {
    let checked = @pipeline.check(cursor(source), [], None, None, {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    }).unwrap()
    let owner = @lower.bind_parameters(
      @lower.prepare(checked, {
        max_nodes: 100,
        max_references: 100,
        max_work: 10000,
        max_identifier_bytes: 1000,
      }).unwrap(),
      None,
      max_parameters=0,
      max_name_bytes=0,
    ).unwrap()
    let completed = @execution.execute_generated_sequence(
      fixture_generated(owner, registry_json, values_json, fragment_json, false),
      [],
      issued_execution_limits(100),
    ).unwrap()
    owned_fixed_from_output(
      owner,
      @execution.completed_output(completed, Step(1)).unwrap(),
      registry_json,
      values_json,
      fragment_json,
      projection="amount",
      predicate~,
    )
  } catch {
    _ => abort("typed fixed conformance setup")
  }
}
