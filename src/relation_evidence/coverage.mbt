///|
fn coverage_name(field : @row.FieldName) -> String {
  match field {
    Unqualified(name) => "u:" + name
    Qualified(Left, name) => "l:" + name
    Qualified(Right, name) => "r:" + name
  }
}

///|
/// Selects a whole candidate key covered by these field occurrences. Coverage
/// does not establish field comparability or discharge the key's obligations.
/// One covered alias per original component suffices; repeats cannot replace
/// a missing component. Field provenance is compared, not just display text.
pub fn select_covered_key(
  source : @decode.Cursor,
  value : KeySet,
  fields : Array[@row.FieldName],
  limits : TransferLimits,
) -> Result[KeySelection, Issue] {
  try {
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, fields.length())
    let covered : Map[String, Bool] = Map([])
    for field in fields {
      charge(b, source, field)
      covered[coverage_name(field)] = true
    }
    let selected = match
      select_matching_key(
        source,
        value,
        field => covered.contains(coverage_name(field.name)),
        { max_work: b.work, max_name_bytes: b.text, },
      ) {
      Ok(v) => v
      Err(e) => raise Stop(e)
    }
    Ok({
      key: selected.key,
      work: limits.max_work - b.work + selected.work,
      name_bytes: limits.max_name_bytes - b.text + selected.name_bytes,
    })
  } catch {
    Stop(e) => Err(e)
  }
}
