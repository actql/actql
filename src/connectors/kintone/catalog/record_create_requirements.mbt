///|
/// Required input fields of this complete original Form. Defaults are not
/// intended writes and never satisfy a required request member. This finite
/// projection does not issue provider permission or a current Form decision.
pub fn record_create_required_fields(
  catalog : FormFieldCatalog,
  max_fields : Int,
  max_work : Int,
) -> Result[Array[String], RecordWriteIssue] {
  if max_fields <= 0 || max_work <= 0 {
    return Err(InvalidLimits)
  }
  if catalog.fields.length() > max_fields {
    return Err(BudgetExceeded)
  }
  let copied : Map[String, Bool] = Map([])
  let mut work = max_work
  for owner in catalog.fields {
    if work <= 0 {
      return Err(BudgetExceeded)
    }
    work -= 1
    guard owner.write_lookup_targets is Some(targets) else {
      return Err(FieldUnavailable(owner.code))
    }
    for target in targets {
      if work <= 0 {
        return Err(BudgetExceeded)
      }
      work -= 1
      copied[target] = true
    }
  }
  let required = []
  for field in catalog.fields {
    if work <= 0 {
      return Err(BudgetExceeded)
    }
    work -= 1
    // Table children need the original table-row create protocol. Missing
    // parent/child requirements cannot become a scalar create default.
    if field.path.length() != 1 || field.native_type == "SUBTABLE" {
      return Err(FieldUnavailable(field.code))
    }
    let generated = match field.native_type {
      "CALC"
      | "STATUS"
      | "CATEGORY"
      | "STATUS_ASSIGNEE"
      | "RECORD_NUMBER"
      | "CREATOR"
      | "MODIFIER"
      | "CREATED_TIME"
      | "UPDATED_TIME"
      | "REFERENCE_TABLE"
      | "GROUP" => true
      "SINGLE_LINE_TEXT" =>
        match field.write_expression {
          Some(expression) => !expression.is_empty()
          None => false
        }
      _ => false
    }
    if generated || copied.contains(field.code) {
      continue
    }
    match field.required {
      Some(false) => ()
      Some(true) => {
        guard write_value_contract(field) is Some(_) &&
          (
            field.native_type != "SINGLE_LINE_TEXT" ||
            field.write_expression == Some("")
          ) else {
          return Err(FieldUnavailable(field.code))
        }
        required.push(field.code)
      }
      None => return Err(FieldUnavailable(field.code))
    }
  }
  Ok(required)
}
