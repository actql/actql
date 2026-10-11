///|
/// Original physical input metadata for the private Provider continuation.
/// These facts grant no Host authority, approval, restore or Provider permit.
pub(all) enum ResidentEffectReviewInputBinding {
  Retained(String)
  Acquired(String, String)
}

///|
/// Recheck the live input and the Host's original request before exposing its
/// binding. Local acquisition uses its checked Source requirement; it cannot
/// manufacture a Remote receiver. The complete capture separately retains the
/// acquisition observation, values, Policy and dependency inventory.
pub fn ResidentSourceCompute::effect_review_input_binding(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  request : @host.ClientRequestIdentity,
) -> Result[
  ResidentEffectReviewInputBinding,
  ResidentEffectReviewCheckpointIssue,
] {
  guard self.resident_effect_inputs_current(inputs) &&
    self.effect_materials_for_capture() is Some(saved) else {
    return Err(Unavailable)
  }
  if !physical_equal(saved.prepared, materials.prepared) ||
    !physical_equal(saved.compilation, materials.compilation) ||
    saved.request != Some(request) ||
    materials.request != Some(request) ||
    self.request_for_effect_review(inputs) != Some(request) ||
    @publication.publication_contract_identity(saved.run_definition) !=
    @publication.publication_contract_identity(materials.run_definition) {
    return Err(ForeignCapture)
  }
  match self.effect_retained {
    Some(retained) =>
      Ok(
        Retained(
          @remote.remote_input_binding_body(
            @output.native_remote_retained_task_input_binding(retained.input),
          ),
        ),
      )
    None => {
      guard self.effect_source is Some(original) else {
        return Err(Unavailable)
      }
      let (source_ref, source_contract_cid) = @planning.query_requirement_source(
        original.requirement,
      )
      Ok(Acquired(source_ref, source_contract_cid))
    }
  }
}
