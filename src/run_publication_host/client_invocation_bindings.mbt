///|
pub(all) enum ClientEmptyInvocationBindingsIssue {
  BindingsDeclared
  Evidence(@publication.RunEvidenceValueIssue)
} derive(Eq, Debug)

///|
/// Issue the exact empty Invocation Bindings identity only for a checked
/// Program with no opaque declarations. The nonempty path must validate the
/// reference issuer, type, request slot and current authorization at Plan
/// issuance before it can produce a corresponding identity.
pub fn issue_prepared_client_empty_invocation_bindings(
  value : PreparedClientProgram,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientEmptyInvocationBindingsIssue] {
  issue_empty_invocation_bindings(
    @syntax.program_binding_names(value.source),
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_empty_invocation_bindings(
  declared_names : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientEmptyInvocationBindingsIssue] {
  if !declared_names.is_empty() {
    return Err(BindingsDeclared)
  }
  match
    @publication.seal_run_evidence_value(
      "invocation_bindings", "{\"version\":\"actql-invocation-bindings/0.1\",\"bindings\":{}}",
      max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(binding) => Ok(binding)
    Err(issue) => Err(Evidence(issue))
  }
}
