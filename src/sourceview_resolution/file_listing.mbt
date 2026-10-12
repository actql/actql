///|
// Check selector alternatives in the ordinary Request owner. A selected
// parameter cannot later evaluate to NULL and accidentally widen the scope.
fn check_file_listing_selector(
  profile : @environment.FileListProfile,
  fields : Array[RequestField],
  b : Budget,
  source : @decode.Cursor?,
) -> Unit raise RequestStop {
  let mut selected : String? = None
  for field in fields {
    if field.slot.field_name != "paths" && field.slot.field_name != "glob" {
      continue
    }
    request_charge(b, 1, Some(field.slot.source))
    let active = match field.slot.value {
      @slots.Literal(value) => !@decode.is_null(value)
      @slots.Parameter(declaration) => {
        if declaration.parameter_type.contract.nullable {
          request_fail(InvalidFileListSelector, Some(field.slot.source))
        }
        true
      }
      @slots.Binding(_) =>
        request_fail(InvalidFileListSelector, Some(field.slot.source))
    }
    if active {
      if selected is Some(_) {
        request_fail(InvalidFileListSelector, source)
      }
      selected = Some(field.slot.field_name)
    }
  }
  if !@environment.file_listing_accepts(profile, selected.unwrap_or("all")) {
    request_fail(InvalidFileListSelector, source)
  }
}
