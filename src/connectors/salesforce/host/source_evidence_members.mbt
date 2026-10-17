///|
/// The Check Environment source evidence members of one generated
/// declaration, as canonical texts: for each declared view, the schema
/// snapshot its publication observed and this implementation's capability
/// (the broad-receipt process-evidence contract). The declaration's data
/// policies classify every view as `unknown`.
pub fn salesforce_source_evidence_members(
  declaration : @catalog.StaticDeclaration,
) -> (Array[String], Array[String]) raise @encode.EncodeFailure {
  // Preserve the producer's original malformed-metadata refusal before the
  // same shared evidence emitter consumes its complete row projection.
  for view in declaration.views {
    if view.carrier_schema_cid.is_empty() || view.data_policy_cid.is_empty() {
      raise @encode.EncodeFailure::InvalidStructure
    }
  }
  let projection = match salesforce_row_declaration(declaration) {
    Ok(value) => value
    Err(_) => raise @encode.EncodeFailure::InvalidStructure
  }
  @rows.row_declaration_evidence_members(projection)
}
