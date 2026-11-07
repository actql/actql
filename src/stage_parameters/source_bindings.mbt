///|
/// Retain the completed original binding in an immutable Source snapshot.
/// No caller-supplied Result, proof, execution permission or currentness is
/// accepted. An ordinary caller still funds construction before this entry.
pub fn prepare_bindings(
  source : Source,
  supplied : @decode.Cursor?,
  limits : @value.Limits,
) -> (Source, Result[@parameter.BindingResult, @parameter.Issue]) {
  if source.binding_read is Some(original) &&
    @parameter.reuse_binding_read(
      original,
      source.declarations,
      supplied,
      limits,
    )
    is Some(completed) {
    return (source, completed)
  }
  match @parameter.prepare_binding_read(source.declarations, supplied, limits) {
    Err(issue) => (source, Err(issue))
    Ok(original) => {
      let completed = @parameter.finish_binding_read(original)
      (complete_source_binding(source, original), completed)
    }
  }
}

///|
fn complete_source_binding(
  source : Source,
  original : @parameter.BindingReadInput,
) -> Source {
  { ..source, binding_read: Some(original), }
}

///|
/// Bind the actual Source declarations. The exact completed immutable input
/// may be forwarded under fitting measured node/text ceilings and unchanged
/// or relaxed depth. Other inputs use the same ordinary semantic engine.
/// Usage remains charged by the consumer; failed reads require exact limits.
pub fn bind(
  source : Source,
  supplied : @decode.Cursor?,
  limits : @value.Limits,
) -> Result[@parameter.BindingResult, @parameter.Issue] {
  if source.binding_read is Some(original) &&
    @parameter.reuse_binding_read(
      original,
      source.declarations,
      supplied,
      limits,
    )
    is Some(completed) {
    return completed
  }
  @parameter.bind(source.declarations, supplied, limits)
}
