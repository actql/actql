///|
// Only the row-name fallback. Ordinary columns, including USING and ambiguous
// columns, retain the existing resolver's precedence and rejection rules.
fn joined_row_input_fields(
  path : Array[@query.NamePart],
  part : @query.JoinPart,
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
) -> Array[(String, String)]? raise Abort {
  if path.length() != 1 {
    return None
  }
  let field = Some(
    join_projection_field(
      path, part, left_qualifier, right_qualifier, left_fields, right_fields,
    ),
  ) catch {
    Abort(UnknownColumn) => None
    Abort(issue) => raise Abort(issue)
  }
  if field is Some(_) {
    return None
  }
  let left = same_name(path[0], left_qualifier)
  let right = same_name(path[0], right_qualifier)
  if left && right {
    raise Abort(AmbiguousRelation)
  }
  if left {
    return Some(left_fields.map(field => ("left", field)))
  }
  if right {
    return Some(right_fields.map(field => ("right", field)))
  }
  None
}

///|
fn joined_expression_input_fields(
  path : Array[@query.NamePart],
  part : @query.JoinPart,
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
) -> Array[(String, String)] raise Abort {
  match
    joined_row_input_fields(
      path, part, left_qualifier, right_qualifier, left_fields, right_fields,
    ) {
    Some(fields) => fields
    None => {
      let receiver = join_projection_receiver(
        path, part, left_qualifier, right_qualifier, left_fields, right_fields,
      )
      [(receiver.0, receiver.1)]
    }
  }
}

///|
// A row is available only when every declared member has an actual JOIN slot.
// Missing members are not silently dropped or assigned invented NULL values.
fn joined_row_ranges(
  left_qualifier : @query.NamePart,
  right_qualifier : @query.NamePart,
  left_fields : Array[String],
  right_fields : Array[String],
  slots : Array[(String, String, String)],
) -> Array[(@query.NamePart, Array[(String, String)])] {
  let ranges = []
  let by_input : Map[(String, String), String] = Map([])
  for (side, field, slot) in slots {
    by_input[(side, field)] = slot
  }
  for
    (qualifier, side, fields) in [
      (left_qualifier, "left", left_fields),
      (right_qualifier, "right", right_fields),
    ] {
    let members = []
    for field in fields {
      if by_input.get((side, field)) is Some(slot) {
        members.push((field, slot))
      }
    }
    if members.length() == fields.length() {
      ranges.push((qualifier, members))
    }
  }
  ranges
}
