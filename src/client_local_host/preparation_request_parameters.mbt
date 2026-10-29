///|
/// Normal Request selection of the existing Parameter declaration/Source
/// continuation. The same parent retains it before any fallible constructor;
/// no caller-supplied Source or unbudgeted declaration reader is required.
fn[I] prepare_request_parameter_source_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  program : @syntax.Program,
  checking : @checked.CheckLimits,
) -> Result[@stages.Source, ClientRequestPreparationIssue] {
  if owner.parameter_source is Some(source) {
    guard owner.parameter_declarations is Some(declarations) &&
      declarations.phase == RetainedSource &&
      declarations.input is Some(original) &&
      physical_equal(original, input) &&
      declarations.program is Some(original_program) &&
      physical_equal(original_program, program) &&
      declarations.source is Some(Ok(original_source)) &&
      physical_equal(original_source, source) else {
      return Err(ForeignOriginal)
    }
    return Ok(source)
  }
  let root = @syntax.program_body(program)
  let mut parameters = None
  for index in 0..<@decode.object_length(root).unwrap() {
    let (name, original) = @decode.field_at(root, index).unwrap()
    if name == "params" {
      parameters = Some(original)
      break
    }
  }
  let declarations = match owner.parameter_declarations {
    Some(original) => original
    None => {
      let original = match
        begin_parameter_declaration_preflight(
          owner.capacity,
          input,
          parameters,
          {
            max_parameters: checking.compilation.structure.parameters,
            max_nodes: checking.compilation.traversal.nodes,
            max_depth: checking.compilation.traversal.depth,
            max_text_bytes: checking.compilation.traversal.text_bytes,
          },
        ) {
        Err(issue) => return Err(ParameterPreparation(issue))
        Ok(original) => original
      }
      owner.parameter_declarations = Some(original)
      original
    }
  }
  match prepare_parameter_declaration_preflight(declarations) {
    Err(issue) => return Err(ParameterPreparation(issue))
    Ok(_) => ()
  }
  match reconcile_parameter_declaration_preflight(declarations) {
    Err(issue) => return Err(ParameterPreparation(issue))
    Ok(_) => ()
  }
  guard parameter_declaration_preflight_outcome(declarations)
    is Some((outcome, _, _)) else {
    return Err(WrongPhase)
  }
  let reader = match outcome {
    Err(issue) => return Err(ParameterDeclarations(issue))
    Ok(original) => original
  }
  match prepare_parameter_declaration_header(declarations) {
    Err(issue) => return Err(ParameterPreparation(issue))
    Ok(_) => ()
  }
  if @parameters.declaration_read_phase(reader) !=
    @parameters.DeclarationComplete {
    match prepare_parameter_declaration_inventory(declarations) {
      Err(issue) => return Err(ParameterPreparation(issue))
      Ok(_) => ()
    }
    match reconcile_parameter_declaration_inventory(declarations) {
      Err(issue) => return Err(ParameterPreparation(issue))
      Ok(_) => ()
    }
    while @parameters.declaration_read_phase(reader) !=
          @parameters.DeclarationComplete {
      match @parameters.declaration_read_phase(reader) {
        @parameters.DeclarationType =>
          match prepare_parameter_declaration_type(declarations) {
            Err(issue) => return Err(ParameterPreparation(issue))
            Ok(_) => ()
          }
        @parameters.DeclarationValue =>
          match prepare_parameter_declaration_value(declarations) {
            Err(issue) => return Err(ParameterPreparation(issue))
            Ok(_) => ()
          }
        _ => return Err(WrongPhase)
      }
    }
  }
  match @parameters.finish_declaration_read(reader) {
    Err(issue) => return Err(ParameterDeclarations(issue))
    Ok(_) => ()
  }
  match reconcile_parameter_declarations(declarations) {
    Err(issue) => return Err(ParameterPreparation(issue))
    Ok(_) => ()
  }
  match prepare_parameter_declaration_source(declarations, program) {
    Err(issue) => return Err(ParameterPreparation(issue))
    Ok(_) => ()
  }
  guard parameter_declaration_source_outcome(declarations) is Some(outcome) else {
    return Err(WrongPhase)
  }
  let source = match outcome {
    Err(issue) => return Err(ParameterSource(issue))
    Ok(original) => original
  }
  owner.parameter_source = Some(source)
  match reconcile_parameter_declaration_source(declarations) {
    Err(issue) => return Err(ParameterPreparation(issue))
    Ok(_) => ()
  }
  Ok(source)
}

///|
/// Release only this retained domain's aliases. The original Request/typed
/// successor still owns all body, borrower and capacity retirement duties.
fn[I] clear_request_parameter_source(
  owner : ClientRequestPreparation[I],
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.parameter_declarations is Some(original) {
    match clear_parameter_declaration_preflight(original) {
      Err(issue) => return Err(ParameterPreparation(issue))
      Ok(_) => ()
    }
    owner.parameter_declarations = None
  }
  owner.parameter_source = None
  Ok(())
}
