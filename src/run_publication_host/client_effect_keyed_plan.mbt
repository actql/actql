///|
/// The real checked Source-only lookup compiler. No Model occurrence, Model
/// execution contract or independent runnable Graph is manufactured here.
pub struct ClientEffectKeyedPlanGraph {
  priv owner : PreparedClientEffectComputation
  priv component : ClientEffectKeyedPlanComponent
  priv graph_nodes : Array[@canonical.CanonicalValue]
}

///|
priv enum ClientEffectKeyedPlanComponent {
  NativeKeyedPlan(ClientKeyedPlanComponent)
  GenericKeyedPlan(ClientGenericKeyedPlanComponent)
}

///|
priv enum ClientEffectKeyedPlanInput {
  NativeKeyedConstruction(ClientKeyedPlanBarrierInput)
  GenericKeyedConstruction(ClientGenericKeyedPlanBarrierInput)
}

///|
pub fn select_client_effect_single_keyed_acquisition(
  prepared : PreparedClientEffectComputation,
) -> Result[ClientKeyedAcquisition?, ClientKeyedAcquisitionIssue] {
  match
    client_composed_keyed_source_coordinates(
      client_effect_program_view(prepared),
    ) {
    Err(issue) => Err(issue)
    Ok(None) => Ok(None)
    Ok(Some((stage, input, join))) =>
      prepare_client_effect_keyed_acquisition(
        prepared,
        stage,
        input,
        1000000,
        join_step=Some(join),
      ).map(value => Some(value))
  }
}

///|
/// Same lowering and physical profile as the Model lookup. Its final pipeline
/// is the selected checked keyed JOIN; later Task/Effect work stays in the
/// actual installed DAG and is not executed by this compiler DATA.
pub fn measure_client_effect_keyed_plan_construction(
  effect : PreparedClientEffectComputation,
  acquisition : ClientKeyedAcquisition,
  profile : @publication.PublicationContract,
  sequence_limits : @lower.SequenceLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectKeyedPlanConstruction, ClientInferPlanGraphIssue] {
  guard client_keyed_acquisition_matches_effect_program(acquisition, effect) &&
    prepared_client_effect_infer_occurrences(effect) is Some([]) &&
    client_keyed_acquisition_coordinates(acquisition) is Some((_, task, join)) else {
    return Err(UnsupportedProgram)
  }
  let fragments = match
    prepare_client_keyed_plan_fragment_inputs_original(
      client_effect_program_view(effect),
      acquisition.owner,
      task,
      join,
      acquisition,
      sequence_limits,
      max_nodes,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let input = match
    prepare_client_keyed_plan_barrier_input(
      fragments, profile, 1000000, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let (left, joined) = match
    measure_client_keyed_plan_fragments(
      fragments, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let (barrier, node) = match
    measure_client_keyed_plan_barrier(input, max_bytes, max_nodes, max_depth) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  Ok({
    owner: effect,
    original: NativeKeyedConstruction(input),
    fragments: [left, joined],
    barrier,
    node,
  })
}

///|
/// Actual emitter geometry and original inputs, not an encoded Graph or IO
/// permission. The issuer borrows these SAME lowered and policy originals.
pub struct ClientEffectKeyedPlanConstruction {
  fragments : Array[ClientTaskFragmentConstruction]
  barrier : (Int, Int, Int)
  node : (Int, Int, Int)
  priv owner : PreparedClientEffectComputation
  priv original : ClientEffectKeyedPlanInput
}

///|
/// Select only the real checked file-content Source protocol. The acquisition
/// and its policies grant no dispatch, Model permission or completed input.
pub fn measure_client_effect_generic_keyed_plan_construction(
  effect : PreparedClientEffectComputation,
  acquisition : ClientKeyedAcquisition,
  sequence_limits : @lower.SequenceLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectKeyedPlanConstruction, ClientInferPlanGraphIssue] {
  guard client_keyed_acquisition_matches_effect_program(acquisition, effect) &&
    prepared_client_effect_infer_occurrences(effect) is Some([]) &&
    client_keyed_acquisition_coordinates(acquisition) is Some((_, task, join)) else {
    return Err(UnsupportedProgram)
  }
  let fragments = match
    prepare_client_keyed_plan_fragment_inputs_original(
      client_effect_program_view(effect),
      acquisition.owner,
      task,
      join,
      acquisition,
      sequence_limits,
      max_nodes,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let input = match
    prepare_client_generic_keyed_plan_barrier_input(
      fragments, 1000000, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let (left, joined) = match
    measure_client_keyed_plan_fragments(
      fragments, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let (barrier, node) = match
    measure_client_generic_keyed_plan_barrier(
      input, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  Ok({
    owner: effect,
    original: GenericKeyedConstruction(input),
    fragments: [left, joined],
    barrier,
    node,
  })
}

///|
pub fn issue_client_effect_keyed_plan_graph(
  construction : ClientEffectKeyedPlanConstruction,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectKeyedPlanGraph, ClientInferPlanGraphIssue] {
  let effect = construction.owner
  let component = match construction.original {
    NativeKeyedConstruction(input) =>
      match
        issue_client_keyed_plan_component(
          input, max_bytes, max_nodes, max_depth,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => NativeKeyedPlan(value)
      }
    GenericKeyedConstruction(input) =>
      match
        issue_client_generic_keyed_plan_component(
          input, max_bytes, max_nodes, max_depth,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => GenericKeyedPlan(value)
      }
  }
  let nodes = []
  let fragments = match component {
    NativeKeyedPlan(value) => [value.left, value.barrier, value.joined]
    GenericKeyedPlan(value) => [value.left, value.barrier, value.joined]
  }
  for fragment in fragments {
    guard parse_plan_identity_value(
        fragment.wire,
        max_bytes,
        max_nodes,
        max_depth,
      )
      is Some(node) else {
      return Err(Encoding)
    }
    nodes.push(node)
  }
  Ok({ owner: effect, component, graph_nodes: nodes, })
}

///|
pub fn client_effect_keyed_plan_graph_coordinates(
  value : ClientEffectKeyedPlanGraph,
) -> (Int, Int, Int) {
  let original = client_effect_keyed_plan_fragments(value)
  let (stage, _, join) = client_keyed_acquisition_coordinates(
    original.acquisition,
  ).unwrap()
  (stage, original.task, join)
}

///|
pub fn client_effect_keyed_plan_graph_matches(
  value : ClientEffectKeyedPlanGraph,
  effect : PreparedClientEffectComputation,
  acquisition : ClientKeyedAcquisition,
) -> Bool {
  physical_equal(value.owner, effect) &&
  physical_equal(
    client_effect_keyed_plan_fragments(value).acquisition,
    acquisition,
  ) &&
  client_keyed_acquisition_matches_effect_program(acquisition, effect)
}

///|
/// Project the actual allowed Source-only Effect compiler. This is the same
/// nominal compiled Run used by its Definition, not an Infer substitute.
pub fn client_effect_allowed_keyed_run(
  allowed : ClientEffectAllowedRun,
  plan : ClientEffectKeyedPlanGraph,
  definition : @publication.PublicationContract,
) -> Result[ClientCompiledRun, ClientCompiledRunIssue] {
  guard physical_equal(allowed.compilation.owner, plan.owner) &&
    client_effect_keyed_plan_graph_matches(
      plan,
      allowed.compilation.owner,
      client_effect_keyed_plan_fragments(plan).acquisition,
    ) else {
    return Err(ForeignOwner)
  }
  let compiled = client_effect_allowed_component_run(allowed, None)
  match check_client_compiled_run_definition(compiled, definition) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(compiled)
  }
}

///|
// A closed original binding, borrowing the existing Ledger inventory. Neither
// variant creates a Scope, allowance, reservation or Model permission.
priv enum ClientComposedKeyedOrigin {
  ModelOrigin(ClientModelReadScope, ClientInferPlanGraph)
  SourceEffectOrigin(ClientEffectKeyedOriginal)
}

///|
fn client_composed_keyed_original_model_scope(
  value : ClientComposedKeyedOriginal,
) -> ClientModelReadScope? {
  match value.origin {
    ModelOrigin(scope, _) => Some(scope)
    _ => None
  }
}

///|
fn client_composed_keyed_original_model_plan(
  value : ClientComposedKeyedOriginal,
) -> ClientInferPlanGraph? {
  match value.origin {
    ModelOrigin(_, plan) => Some(plan)
    _ => None
  }
}

///|
fn client_composed_keyed_original_component(
  value : ClientComposedKeyedOriginal,
) -> ClientKeyedPlanComponent? {
  match value.origin {
    ModelOrigin(_, plan) => plan.keyed
    SourceEffectOrigin(original) =>
      match original.plan.component {
        NativeKeyedPlan(component) => Some(component)
        GenericKeyedPlan(_) => None
      }
  }
}

///|
fn client_effect_keyed_plan_fragments(
  value : ClientEffectKeyedPlanGraph,
) -> ClientKeyedPlanFragmentInputs {
  match value.component {
    NativeKeyedPlan(component) => component.original.fragments
    GenericKeyedPlan(component) => component.original.fragments
  }
}

///|
pub fn client_effect_keyed_plan_graph_is_generic(
  value : ClientEffectKeyedPlanGraph,
) -> Bool {
  value.component is GenericKeyedPlan(_)
}

///|
fn client_composed_keyed_original_program(
  value : ClientComposedKeyedOriginal,
) -> PreparedClientProgram {
  match value.origin {
    ModelOrigin(_, plan) => plan.owner
    SourceEffectOrigin(original) =>
      client_effect_program_view(original.prepared)
  }
}

///|
fn client_composed_keyed_original_ledger(
  value : ClientComposedKeyedOriginal,
) -> @resources.Ledger {
  match value.origin {
    ModelOrigin(scope, _) => scope.ledger
    SourceEffectOrigin(original) => original.ledger
  }
}

///|
fn client_composed_keyed_original_identity(
  value : ClientComposedKeyedOriginal,
) -> @resources.OriginalLedgerIdentity {
  match value.origin {
    ModelOrigin(scope, _) => scope.identity
    SourceEffectOrigin(original) => original.identity
  }
}

///|
fn client_composed_keyed_original_graph_nodes(
  value : ClientComposedKeyedOriginal,
) -> Array[@canonical.CanonicalValue] {
  match value.origin {
    ModelOrigin(_, plan) => plan.graph_nodes
    SourceEffectOrigin(original) => original.plan.graph_nodes
  }
}

///|
fn client_composed_keyed_original_stage(
  value : ClientComposedKeyedOriginal,
) -> Int {
  match value.origin {
    ModelOrigin(_, plan) => plan.stage
    SourceEffectOrigin(original) =>
      client_effect_keyed_plan_graph_coordinates(original.plan).0
  }
}

///|
fn client_effect_keyed_composed_original_current(
  value : ClientComposedKeyedOriginal,
) -> Bool {
  guard value.origin is SourceEffectOrigin(bound) &&
    physical_equal(value.compiled, bound.compiled) &&
    physical_equal(value.definition, bound.definition) &&
    client_effect_keyed_original_available(bound) &&
    client_effect_keyed_plan_graph_matches(
      bound.plan,
      bound.prepared,
      value.keyed,
    ) &&
    value.prefix is None &&
    value.completed is None &&
    value.producers is NoProducers &&
    value.sources is [source] &&
    value.inputs is [(_, _, _)] &&
    // The sole Source-origin constructor seals this read over the exact Source
    // output, adding only source.live as its restriction. The fresh Source
    // check already verifies that original completion; this private binding
    // has no separate Read revocation. The outer left checks the actual Read,
    // and the output projection still validates the full binding before use.
    @query.captured_source_available(source) &&
    value.direct_output is Some(_) &&
    @row_host.row_captured_inputs_source_at(value.captures, 0) is Some(same) &&
    physical_equal(source, same) &&
    @row_host.row_captured_inputs_borrowed_available(
      value.captures,
      bound.ledger,
    ) else {
    return false
  }
  @resources.original_ledger_inventory_available(bound.identity)
}

///|
/// Convenience for callers that already funded both construction phases.
/// Installed preparation uses the explicit measure/issue pair above.
pub fn prepare_client_effect_keyed_plan_graph(
  effect : PreparedClientEffectComputation,
  acquisition : ClientKeyedAcquisition,
  profile : @publication.PublicationContract,
  sequence_limits : @lower.SequenceLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectKeyedPlanGraph, ClientInferPlanGraphIssue] {
  match
    measure_client_effect_keyed_plan_construction(
      effect, acquisition, profile, sequence_limits, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => Err(issue)
    Ok(value) =>
      issue_client_effect_keyed_plan_graph(
        value, max_bytes, max_nodes, max_depth,
      )
  }
}

///|
/// Net retained carrier added to each actual Model original: replacing two
/// direct fields with one closed variant adds H1/R1/W1. It is part of the
/// shared Root/controller inventory for BOTH Native and Node constructors.
pub fn client_composed_keyed_model_origin_construction_inventory() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 1L,
    reference_slots: 1L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
/// Before projecting the actual Source-only compiled Run. The retained holder
/// H1/R9 and Effects H1/R1/W1 coexist with the existing Effect validation chain
/// (static candidate H1/R3, checked DAG H1/R2, prepared Run H1/R3) and its two
/// live Result carriers H2/R2/W2. Effects retain no DefinitionFacts cache; the
/// separate Source binding retains the exact Definition after this succeeds.
pub fn client_effect_allowed_keyed_run_construction_inventory() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 7L,
    reference_slots: 20L,
    scalar_words: 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}
