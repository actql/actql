///|
/// An opaque connection between the exact unchecked intent and its ordinary
/// preparation owner. Neither this handle nor its CID admits a Run or work.
struct NativeClientSubmittedPreparation {
  intent_cid : String
  preparation : NativeClientPreparation
}

///|
pub(all) enum NativeClientSubmittedPreparationIssue {
  InvalidSubmittedInput
  SubmittedInputLimit
  Declarations(@parameters.Issue)
  Preparation(NativeClientPreparationIssue)
  ReadOnlyEffect
  Request(@local.ClientRequestTerminalIssue)
  RequestPreparation(@local.ClientRequestPreparationIssue)
  RequestBranchUnavailable
}

///|
pub fn native_client_submitted_preparation(
  value : NativeClientSubmittedPreparation,
) -> NativeClientPreparation {
  value.preparation
}

///|
pub fn native_client_submitted_preparation_intent_cid(
  value : NativeClientSubmittedPreparation,
) -> String {
  value.intent_cid
}

///|
/// Reuse the exact original intent envelope. Structured input is already the
/// Program; query input retains its text, format, declarations and parameters.
/// The Host supplies its authorized context and configured write bindings.
/// No caller-provided lowered JSON or independently prepared handle is used.
pub fn prepare_native_client_submitted_program(
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  context : @query.Context?,
  evidence : Array[@context.StageCapacityInput],
  limits : @host.ClientEffectComputationLimits,
  source_path? : String = "<source>",
  table_writes? : Array[@query.TableWriteBinding] = [],
) -> Result[
  NativeClientSubmittedPreparation,
  NativeClientSubmittedPreparationIssue,
] {
  native_timing_count(17)
  let source = match
    @source.parse_json_bytes_preserving(
      @utf8.encode(@host.client_submitted_intent_wire(intent)),
      { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
    ) {
    Ok(value) => value
    Err(error) =>
      match error.issue {
        InputLimit | NodeLimit | DepthLimit => return Err(SubmittedInputLimit)
        _ => return Err(InvalidSubmittedInput)
      }
  }
  let value = @canonical.from_source(source, 8192, 64, 65536, data_keys=true) catch {
    @canonical.InputLimit => return Err(SubmittedInputLimit)
    _ => return Err(InvalidSubmittedInput)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 8192,
      max_depth: 64,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(issue) =>
      if issue.kind == @decode.BudgetExceeded {
        return Err(SubmittedInputLimit)
      } else {
        return Err(InvalidSubmittedInput)
      }
  }
  guard @decode.closed_object(cursor, [
      "kind", "input", "parameters", "stopBefore", "readOnly",
    ])
    is Ok(root) &&
    epoch_text(root, "kind") is Some(kind) &&
    @decode.lookup(root, "input") is Some(input) &&
    @decode.lookup(root, "parameters") is Some(parameters) else {
    return Err(InvalidSubmittedInput)
  }
  let supplied = if @decode.is_null(parameters) {
    None
  } else {
    Some(parameters)
  }
  let (document, format, query_context) = if kind == "program" {
    guard @canonical.object_field(value, "input") is Some(program) else {
      return Err(InvalidSubmittedInput)
    }
    let document = @canonical.stringify_value(program, 65536, 8192, 64) catch {
      @encode.OutputLimit => return Err(SubmittedInputLimit)
      _ => return Err(InvalidSubmittedInput)
    }
    (document, @frontend.Json, context)
  } else if kind == "aql" {
    guard @decode.closed_object(input, [
        "text", "format", "parameterDeclarations",
      ])
      is Ok(input) &&
      epoch_text(input, "text") is Some(document) &&
      epoch_text(input, "format") is Some(spelling) else {
      return Err(InvalidSubmittedInput)
    }
    let format = match @frontend.select_format(spelling) {
      Ok(value) => value
      Err(_) => return Err(InvalidSubmittedInput)
    }
    let query_context = match @decode.lookup(input, "parameterDeclarations") {
      None => context
      Some(declarations) => {
        if format != @frontend.Text && format != @frontend.Sql {
          return Err(InvalidSubmittedInput)
        }
        guard context is Some(context) else {
          return Err(InvalidSubmittedInput)
        }
        let declarations = match
          @parameters.read_declarations(Some(declarations), {
            max_parameters: 1024,
            max_nodes: 8192,
            max_depth: 64,
            max_text_bytes: 65536,
          }) {
          Ok(value) => value
          Err(issue) => return Err(Declarations(issue))
        }
        Some({ ..context, parameter_declarations: Some(declarations), })
      }
    }
    (document, format, query_context)
  } else {
    return Err(InvalidSubmittedInput)
  }
  let preparation = match
    prepare_native_client_program(
      document,
      format,
      environment,
      supplied,
      query_context,
      evidence,
      limits,
      source_path~,
      table_writes~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  // The original intent and this exact prepared Effect inventory share the
  // Common compatibility decision. Preparation failures retain their priority.
  if preparation is EffectComputation(prepared) &&
    !@host.client_submitted_intent_effect_compatible(intent, prepared) {
    return Err(ReadOnlyEffect)
  }
  Ok({ intent_cid: @host.client_submitted_intent_cid(intent), preparation, })
}
