///|
pub(all) enum ReadIssue {
  InvalidLimits
  InvalidBody
  LawMismatch
  InvalidType(@value.AdmissionError)
  InvalidStructure
  NonCanonicalLabels
  BudgetExceeded
} derive(Eq, Debug)

///|
priv suberror ReadStop {
  ReadStop(ReadIssue)
}

///|
priv struct ReadBudget {
  mut nodes : Int
  mut text : Int
  depth : Int
}

///|
fn[T] stop(issue : ReadIssue) -> T raise ReadStop {
  raise ReadStop(issue)
}

///|
fn charge_nodes(b : ReadBudget, n : Int) -> Unit raise ReadStop {
  if n > b.nodes {
    stop(BudgetExceeded)
  }
  b.nodes -= n
}

///|
fn charge_text(b : ReadBudget, s : String) -> Unit raise ReadStop {
  match @scalar.admit_utf8_length(s, b.text) {
    Ok(n) => b.text -= n
    Err(_) => stop(BudgetExceeded)
  }
}

///|
fn required(
  obj : @decode.ObjectView,
  key : String,
) -> @decode.Cursor raise ReadStop {
  match @decode.lookup(obj, key) {
    Some(v) => v
    None => stop(InvalidBody)
  }
}

///|
fn text_value(c : @decode.Cursor, b : ReadBudget) -> String raise ReadStop {
  let s = match @decode.text(c) {
    Ok(v) => v
    Err(_) => stop(InvalidBody)
  }
  charge_text(b, s)
  s
}

///|
fn read_type(
  c : @decode.Cursor,
  b : ReadBudget,
) -> @value.Contract raise ReadStop {
  match
    @value.read_checked_usage(c, {
      max_nodes: b.nodes,
      max_depth: b.depth,
      max_text_bytes: b.text,
    }) {
    Ok((v, n, t)) => {
      b.nodes -= n
      b.text -= t
      v
    }
    Err(e) => stop(InvalidType(e))
  }
}

///|
fn read_properties(
  c : @decode.Cursor,
  b : ReadBudget,
  limits : Limits,
) -> @carrier.Knowledge raise ReadStop {
  let count = match @decode.object_length(c) {
    Some(n) => n
    None => stop(InvalidBody)
  }
  charge_nodes(b, 1)
  if count > b.nodes {
    stop(BudgetExceeded)
  }
  let fields = []
  for i in 0..<count {
    let (name, child) = @decode.field_at(c, i).unwrap()
    charge_text(b, name)
    let contract = read_type(child, b)
    fields.push((@row.Unqualified(name), Some(contract)))
  }
  match
    @carrier.rows(
      fields,
      field_set=Closed,
      max_fields=limits.max_nodes,
      max_name_bytes=limits.max_bytes,
    ) {
    Ok(v) => v
    Err(_) => stop(InvalidStructure)
  }
}
