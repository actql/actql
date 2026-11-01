///|
/// Project only supplied DATA from this exact original intent. Null and an
/// explicitly supplied empty object remain distinct; no Program is prepared.
pub fn local_submitted_preparation_parameters_wire(
  value : LocalSubmittedPreparation,
) -> Result[String?, @host.ClientSubmittedIntentIssue] {
  let limits = @host.client_standard_program_preparation_limits().checking.input
  let (_, original, _) = match
    @host.prepare_client_submitted_input_parts(
      @host.client_submitted_intent_wire(value.intent),
      limits.source.max_input_bytes,
      limits.source.max_nodes,
      limits.source.max_depth,
      limits.tree,
    ) {
    Ok(parts) => parts
    Err(issue) => return Err(issue)
  }
  match @canonical.object_field(original, "parameters") {
    Some(@canonical.Null) => Ok(None)
    Some(parameters) => {
      let wire = @canonical.stringify_value(
        parameters,
        limits.source.max_input_bytes,
        limits.source.max_nodes,
        limits.source.max_depth,
      ) catch {
        _ => return Err(@host.Limit)
      }
      Ok(Some(wire))
    }
    None => Err(@host.InvalidEnvelope)
  }
}
