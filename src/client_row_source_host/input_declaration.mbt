///|
/// Observe the stored original declaration association without reconstructing
/// the Source acquisition. This grants no read or completion authority.
pub fn check_row_input_acquisition_declaration(
  value : RowInputAcquisition,
  declaration : RowDeclaration,
) -> Result[Unit, RowHostIssue] {
  guard row_declaration_view(declaration, value.preparation.facts.source_ref)
    is Some(view) &&
    physical_equal(value.preparation.view, view) else {
    return Err(ForeignDeclaration)
  }
  Ok(())
}
