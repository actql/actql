///|
/// Construct from the SAME completed declarations, never a caller-supplied
/// Result or a second semantic read. The caller first funds the root Map,
/// correspondence carriers, Source and actual Stage copy. Work counts one
/// visit per root field/copied Stage plus this fixed correspondence boundary.
pub fn prepare_from_declaration_read(
  program : @stage.Program,
  original : @parameter.DeclarationReadInput,
) -> (Result[Source, Issue], Int64) {
  let body = @stage.program_body(program)
  let work = @decode.object_length(body).unwrap().to_int64() + 1L
  let root = @decode.open_object(body).unwrap()
  match
    @parameter.completed_declaration_read(
      original,
      @decode.lookup(root, "params"),
    ) {
    None => (Err(ForeignDeclarations), work)
    Some(Err(issue)) => (Err(Declarations(issue)), work)
    Some(Ok(declarations)) =>
      (
        Ok(
          complete_source(
            program,
            declarations,
            @parameter.declaration_read_limits(original),
          ),
        ),
        work + @stage.stage_count(program).to_int64(),
      )
  }
}

///|
/// Retain a completed original binding without constructing a new reader or
/// binding a value. Failed Results may be retained, never upgraded to Ready.
/// Source alone remains declaration preparation, not effective bound values.
pub fn retain_completed_binding(
  source : Source,
  original : @parameter.BindingReadInput,
) -> Result[Source, Issue] {
  guard @parameter.completed_binding_read(original, source.declarations)
    is Some(_) else {
    return Err(ForeignDeclarations)
  }
  Ok(complete_source_binding(source, original))
}
