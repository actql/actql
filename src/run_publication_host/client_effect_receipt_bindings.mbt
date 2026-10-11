///|
pub(all) enum ClientEffectReceiptBindingsIssue {
  ForeignMaterials
  Bindings(ClientEmptyInvocationBindingsIssue)
  TemplateMismatch
}

///|
/// Obtain the original finite empty binding inventory from the checked
/// preparation Owner, then match its identity against the original compiler
/// Template. This neither admits nonempty opaque bindings nor issues a new
/// Run, invocation, Source observation or authorization grant.
pub fn client_effect_run_receipt_bindings(
  materials : ClientEffectRunMaterials,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientEffectReceiptBindingsIssue] {
  if !physical_equal(materials.compilation.owner, materials.prepared) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) ||
    bind_client_effect_compiled_run(
      materials.prepared,
      materials.allowed,
      materials.run_definition,
    )
    is Err(_) {
    return Err(ForeignMaterials)
  }
  let bindings = match
    issue_prepared_client_empty_invocation_bindings(
      client_effect_program_view(materials.prepared),
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Bindings(issue))
  }
  guard parse_plan_identity_value(
      @publication.run_evidence_value_json(
        client_effect_compilation_template(materials.compilation),
      ),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(template) &&
    @canonical.object_field(template, "invocation_bindings_cid")
    is Some(@canonical.String(identity)) &&
    identity == @publication.run_evidence_value_identity(bindings) else {
    return Err(TemplateMismatch)
  }
  Ok(bindings)
}
