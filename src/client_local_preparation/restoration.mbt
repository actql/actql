///|
/// Reuse only the original intent and the exact codec-retained prepared input
/// joined by the existing saved Submission/Run Owner. Decoding the envelope
/// projects authored provenance; no query lowering or Program checking runs.
pub fn restore_local_submitted_input(
  original : @host.ClientSavedTaskMaterials,
) -> Result[LocalSubmittedPreparation, LocalPreparationIssue] {
  let intent = @host.client_saved_task_materials_intent(original)
  let retained = @host.client_saved_task_materials_input(original)
  let limits = @host.client_standard_program_preparation_limits()
  let input_limits = limits.checking.input
  let (_, value, cursor) = match
    @host.prepare_client_submitted_input_parts(
      @host.client_submitted_intent_wire(intent),
      input_limits.source.max_input_bytes,
      input_limits.source.max_nodes,
      input_limits.source.max_depth,
      input_limits.tree,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SubmittedInput(issue))
  }
  guard @decode.closed_object(cursor, [
      "kind", "input", "parameters", "stopBefore", "readOnly",
    ])
    is Ok(root) &&
    @decode.lookup(root, "kind").bind(value => @decode.text(value).to_option())
    is Some(kind) &&
    @decode.lookup(root, "input") is Some(input) else {
    return Err(SubmittedInput(@host.InvalidEnvelope))
  }
  let authored = if kind == "program" {
    guard @canonical.object_field(value, "input") is Some(program) else {
      return Err(SubmittedInput(@host.InvalidEnvelope))
    }
    let document = @canonical.stringify_value(
      program,
      input_limits.source.max_input_bytes,
      input_limits.source.max_nodes,
      input_limits.source.max_depth,
    ) catch {
      _ => return Err(SubmittedInput(@host.Limit))
    }
    Program(document)
  } else {
    guard kind == "aql" &&
      @decode.closed_object(input, ["text", "format", "parameterDeclarations"])
      is Ok(fields) &&
      @decode.lookup(fields, "text").bind(value => {
        @decode.text(value).to_option()
      })
      is Some(text) &&
      @decode.lookup(fields, "format").bind(value => {
        @decode.text(value).to_option()
      })
      is Some(spelling) else {
      return Err(SubmittedInput(@host.InvalidEnvelope))
    }
    match @frontend.select_format(spelling) {
      Ok(@frontend.Text | @frontend.Sql) => ()
      _ => return Err(SubmittedInput(@host.InvalidEnvelope))
    }
    Aql(text)
  }
  let input : LocalPreparedInput = {
    prepared: @host.client_task_run_materials_retained_program(retained),
    original: authored,
    document: @host.client_task_run_materials_retained_document(retained),
  }
  Ok({ intent, input, })
}
