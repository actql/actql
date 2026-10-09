///|
/// A failure-only association retained by the existing selector resolver.
/// This is not namespace completeness, disclosure or Provider absence evidence.
priv struct UnresolvedSelector {
  owner : Owner
  declaration : @inputs.Declaration
  source : @decode.Cursor
}

///|
fn[T] fail_unresolved_selector(
  owner : Owner,
  declaration : @inputs.Declaration,
  source : @decode.Cursor,
) -> T raise Stop {
  raise Stop({
    kind: Unresolved,
    source: Some(source),
    unresolved_selector: Some({ owner, declaration, source, }),
  })
}

///|
/// Return the original admitted declaration only for the actual unresolved
/// selection under these input and Catalog owners. Its cursor belongs to the
/// admitted normalized Program; public locations still require the existing
/// original-document pointer mapping. No parse or selection is performed here.
pub fn unresolved_selector_declaration(
  issue : Issue,
  inputs : @inputs.Inputs,
  catalog : @environment.SourceRequestContracts,
) -> @inputs.Declaration? {
  guard issue.kind == Unresolved &&
    issue.unresolved_selector is Some(reference) &&
    physical_equal(reference.owner.inputs, inputs) &&
    physical_equal(reference.owner.catalog, catalog) &&
    issue.source is Some(source) &&
    physical_equal(reference.source, source) else {
    return None
  }
  Some(reference.declaration)
}
