///|
fn transfer_window(
  b : Budget,
  source : @decode.Cursor,
  input : Target,
  steps : Array[CheckedStep],
  operation : CheckedOperation,
) -> WindowEvidence? raise Stop {
  let previous = match input {
    Step(index) => steps[index].window
    Input(_) => None
  }
  guard previous is Some(roles) else { return None }
  if operation is Event(_) {
    return Some(roles)
  }
  if operation is Projection(projection) {
    return if @projection.operation(projection) == @projection.Events {
      Some(roles)
    } else {
      None
    }
  }
  if operation is WindowGroup(op) {
    let keys = @relation.group_keys(@relation.group(op).unwrap())
    spend(
      b,
      source,
      keys.length() + roles.starts.length() + roles.ends.length(),
    )
    let retained : Map[String, Bool] = Map([])
    for key in keys {
      retained[@schema.reference_name(key.field)] = true
    }
    return retained_window(
      roles.starts.filter(f => retained.contains(@schema.reference_name(f))),
      roles.ends.filter(f => retained.contains(@schema.reference_name(f))),
    )
  }
  guard operation is Unary(op) else { return None }
  match @relation.operation(op) {
    Filter
    | Sort
    | Take
    | AssertRows
    | DedupeRows
    | TopK
    | TopKBy
    | Lag
    | WatermarkRows => Some(roles)
    Derive => {
      spend(
        b,
        source,
        @relation.binding_count(op) +
        roles.starts.length() +
        roles.ends.length(),
      )
      let overwritten : Map[String, Bool] = Map([])
      for i in 0..<@relation.binding_count(op) {
        if @relation.binding_at(op, i).unwrap().name is Some(name) {
          overwritten[name] = true
        }
      }
      let preserved = fn(f) {
        match f {
          @schema.Unqualified(name) => !overwritten.contains(name)
          _ => true
        }
      }
      retained_window(
        roles.starts.filter(preserved),
        roles.ends.filter(preserved),
      )
    }
    Select | Rename | Drop | Distinct => {
      if @relation.row_operation(op) is Some(DistinctRows) {
        return Some(roles)
      }
      let projection = @relation.projection(op)
      spend(
        b,
        source,
        projection.length() + roles.starts.length() + roles.ends.length(),
      )
      let start_names : Map[String, Bool] = Map([])
      let end_names : Map[String, Bool] = Map([])
      for name in roles.starts {
        start_names[@schema.reference_name(name)] = true
      }
      for name in roles.ends {
        end_names[@schema.reference_name(name)] = true
      }
      let starts = []
      let ends = []
      for field in projection {
        let name = @schema.reference_name(field.input)
        if start_names.contains(name) {
          starts.push(field.output)
        }
        if end_names.contains(name) {
          ends.push(field.output)
        }
      }
      retained_window(starts, ends)
    }
    _ => None
  }
}

///|
fn retained_window(
  starts : Array[@schema.FieldName],
  ends : Array[@schema.FieldName],
) -> WindowEvidence? {
  if starts.is_empty() || ends.is_empty() {
    None
  } else {
    Some({ starts, ends, })
  }
}
