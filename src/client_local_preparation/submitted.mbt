///|
/// The exact unchecked envelope and its original ordinary preparation Owner.
/// This reference is neither durable Submission admission nor dispatch.
pub struct LocalSubmittedPreparation {
  intent : @host.ClientSubmittedIntent
  input : LocalPreparedInput
}

///|
pub fn local_submitted_preparation_intent(
  value : LocalSubmittedPreparation,
) -> @host.ClientSubmittedIntent {
  value.intent
}

///|
pub fn local_submitted_preparation_input(
  value : LocalSubmittedPreparation,
) -> LocalPreparedInput {
  value.input
}

///|
/// Keep format, declarations and bindings inside the original submitted
/// envelope. JSON interpretation and language semantics use their existing
/// Owners; a separately prepared document cannot be paired with this intent.
pub fn prepare_local_submitted_input(
  wire : String,
  environment : @checked.CheckEnvironment,
  context : LocalInputContext?,
  limits : @host.ClientProgramPreparationLimits,
) -> Result[LocalSubmittedPreparation, LocalPreparationIssue] {
  let input_limits = limits.checking.input
  let (intent, value, cursor) = match
    @host.prepare_client_submitted_input_parts(
      wire,
      input_limits.source.max_input_bytes,
      input_limits.source.max_nodes,
      input_limits.source.max_depth,
      input_limits.tree,
    ) {
    Ok(parts) => parts
    Err(issue) => return Err(SubmittedInput(issue))
  }
  guard @decode.closed_object(cursor, [
      "kind", "input", "parameters", "stopBefore", "readOnly",
    ])
    is Ok(root) &&
    @decode.required(root, "kind") is Ok(kind_cursor) &&
    @decode.text(kind_cursor) is Ok(kind) &&
    @decode.required(root, "input") is Ok(input) &&
    @decode.lookup(root, "parameters") is Some(parameters) else {
    return Err(SubmittedInput(@host.InvalidEnvelope))
  }
  let supplied = if @decode.is_null(parameters) {
    None
  } else {
    Some(parameters)
  }
  let (original, format, query_context) = if kind == "program" {
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
    (Program(document), @frontend.Json, context)
  } else {
    guard kind == "aql" &&
      @decode.closed_object(input, ["text", "format", "parameterDeclarations"])
      is Ok(input) &&
      @decode.required(input, "text") is Ok(text_cursor) &&
      @decode.text(text_cursor) is Ok(text) &&
      @decode.required(input, "format") is Ok(format_cursor) &&
      @decode.text(format_cursor) is Ok(spelling) else {
      return Err(SubmittedInput(@host.InvalidEnvelope))
    }
    let format = match @frontend.select_format(spelling) {
      Ok(@frontend.Text) => @frontend.Text
      Ok(@frontend.Sql) => @frontend.Sql
      _ => return Err(SubmittedInput(@host.InvalidEnvelope))
    }
    let context = match @decode.lookup(input, "parameterDeclarations") {
      None => context
      Some(declarations) => {
        guard context is Some(context) else {
          return Err(SubmittedInput(@host.InvalidEnvelope))
        }
        let declarations = match
          @parameters.read_declarations(Some(declarations), {
            max_parameters: limits.max_parameters,
            max_nodes: input_limits.source.max_nodes,
            max_depth: input_limits.source.max_depth,
            max_text_bytes: input_limits.source.max_input_bytes,
          }) {
          Ok(value) => value
          Err(issue) => return Err(Declarations(issue))
        }
        Some({
          ..context,
          query: {
            ..context.query,
            parameter_declarations: Some(declarations),
          },
        })
      }
    }
    (Aql(text), format, context)
  }
  prepare_local_input_with_format(
    original, format, environment, supplied, query_context, limits,
  ).map(input => { intent, input, })
}

///|
/// Derive the request from this exact retained submitted carrier, including
/// original authored input intent. This is the existing request algorithm;
/// no scope, Run, dispatch permission or saved acceptance is issued here.
pub fn local_submitted_preparation_request(
  value : LocalSubmittedPreparation,
  authority_scope_cid : String,
  request_id : String,
) -> Result[@host.ClientRequestIdentity, @host.ClientRequestIdentityIssue] {
  @host.prepare_client_request_identity(
    local_prepared_program(value.input),
    authority_scope_cid,
    request_id,
    @host.client_submitted_intent_cid(value.intent),
  )
}
