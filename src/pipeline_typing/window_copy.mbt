///|
// Encode provenance independently of the textual reference spelling.
fn window_role_name(field : @schema.FieldName) -> String {
  match field {
    Unqualified(name) => "u:" + name
    Qualified(Left, name) => "l:" + name
    Qualified(Right, name) => "r:" + name
  }
}

///|
fn derive_window_roles(
  b : Budget,
  source : @decode.Cursor,
  op : @relation.CheckedOperation,
  roles : WindowEvidence,
) -> WindowEvidence? raise Stop {
  let original : Map[String, Int] = Map([])
  for (fields, role) in [(roles.starts, 1), (roles.ends, 2)] {
    spend(b, source, fields.length())
    for field in fields {
      let key = window_role_name(field)
      charge(b, source, key)
      original[key] = original.get(key).unwrap_or(0) | role
    }
  }
  let count = @relation.binding_count(op)
  spend(b, source, count)
  let slots : Array[Int] = []
  let outputs : Map[String, Int] = Map([])
  for i in 0..<count {
    let binding = @relation.binding_copy_at(op, i).unwrap()
    let role = match binding.input {
      Some(InputField(field)) => {
        let key = window_role_name(field)
        charge(b, source, key)
        original.get(key).unwrap_or(0)
      }
      Some(PriorSlot(index)) => slots[index]
      None => 0
    }
    slots.push(role)
    if binding.output is Some(name) {
      charge(b, source, name)
      outputs[window_role_name(Unqualified(name))] = role
    }
  }
  let starts = []
  let ends = []
  // Keep existing representatives first. A self-copy is the same value version;
  // an earlier slot cannot override the final binding of an output name.
  for
    (fields, result, role) in [(roles.starts, starts, 1), (roles.ends, ends, 2)] {
    let seen : Map[String, Bool] = Map([])
    spend(b, source, fields.length() + count)
    for field in fields {
      let key = window_role_name(field)
      charge(b, source, key)
      if (outputs.get(key).unwrap_or(role) & role) != 0 {
        result.push(field)
        seen[key] = true
      }
    }
    for i in 0..<count {
      guard @relation.binding_copy_at(op, i).unwrap().output is Some(name) else {
        continue
      }
      charge(b, source, name)
      let field = @schema.Unqualified(name)
      let key = window_role_name(field)
      if !seen.contains(key) && (outputs.get(key).unwrap_or(0) & role) != 0 {
        result.push(field)
        seen[key] = true
      }
    }
  }
  retained_window(starts, ends)
}
