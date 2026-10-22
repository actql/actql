///|
/// Project the explicit policy already retained by this exact source-free
/// Content component. Source-derived policy closure and Model execution
/// originals have different owners and must not enter this alternative.
fn client_effect_original_source_free_policy_input(
  compilation : ClientEffectCompilation,
) -> Result[(String, String)?, ClientEffectRunMaterialsIssue] {
  // A Model component retains its own original execution/dependency policy.
  // Do not add an unrelated Host-policy alternative to those old materials.
  if compilation.compiled.infer is Some(_) {
    return Ok(None)
  }
  guard compilation.compiled.serialization is Some(component) else {
    return Ok(None)
  }
  let owner = compilation.compiled.owner
  if !physical_equal(component.owner, owner) ||
    !physical_equal(
      owner.graph,
      @strategy.checked_effect_computation_graph(compilation.owner.graph),
    ) ||
    !physical_equal(owner.source, compilation.owner.source) ||
    owner.check_environment_cid != compilation.owner.check_environment_cid {
    return Err(Compilation(Serialization(UnsupportedGraph)))
  }
  if !@strategy.graph_source_free_inputs_complete(owner.graph) {
    return Ok(None)
  }
  let policy = component.policy
  let cid = @publication.captured_effect_dependency_body_cid(policy)
  let wire = @publication.captured_effect_dependency_body_json(policy)
  if @publication.captured_effect_dependency_body_kind(policy) != "data_policy" ||
    admit_source_free_result_policy_body(cid, wire, 65536, 8192, 64) is Err(_) {
    return Err(Input(MaterialsEvidence("source_free_result_policy")))
  }
  Ok(Some((cid, wire)))
}

///|
/// The two original fields are paired even on a Program that cannot use them.
/// Null, partial and non-string inputs are not absence.
fn read_client_effect_original_source_free_policy_input(
  cid : @decode.Cursor?,
  wire : @decode.Cursor?,
) -> Result[(String, String)?, ClientValuesRunMaterialsIssue] {
  match (cid, wire) {
    (None, None) => Ok(None)
    (Some(cid), Some(wire)) =>
      match (@decode.text(cid), @decode.text(wire)) {
        (Ok(cid), Ok(wire)) => Ok(Some((cid, wire)))
        _ => Err(MaterialsMalformed)
      }
    _ => Err(MaterialsMalformed)
  }
}

///|
/// Restore only the source-free serialization purpose on the same restored
/// checked Program. The enclosing reader must still verify its independently
/// selected Compiled Plan or Run and original request before use. This does
/// not select current Host policy or issue authority, a Source, or a Run.
fn restore_client_effect_original_source_free_policy(
  prepared : PreparedClientEffectComputation,
  input : (String, String)?,
) -> Result[
  @publication.CapturedEffectDependencyBody?,
  ClientEffectRunMaterialsIssue,
] {
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  let required = @strategy.graph_source_free_inputs_complete(graph) &&
    !prepared_client_effect_serialization_occurrences(prepared).is_empty() &&
    prepared_client_effect_infer_occurrence(prepared) is None
  let missing = ClientEffectRunMaterialsIssue::Input(
    MaterialsEvidence("source_free_result_policy"),
  )
  match (required, input) {
    (false, None) => Ok(None)
    (true, Some((cid, wire))) =>
      match admit_source_free_result_policy_body(cid, wire, 65536, 8192, 64) {
        Ok(policy) => Ok(Some(policy))
        Err(_) => Err(missing)
      }
    _ => Err(missing)
  }
}
