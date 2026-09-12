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

///|
/// Read the existing closed graph structural body. This checks declared types
/// and laws, not graph data, issuer authority, or canonical envelope bytes.
pub fn read_cursor(
  root : @decode.Cursor,
  limits : Limits,
) -> Result[CheckedContract, ReadIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  try {
    let b = {
      nodes: limits.max_nodes,
      text: limits.max_bytes,
      depth: limits.max_depth,
    }
    charge_nodes(b, 1)
    if @decode.object_length(root) != Some(7) {
      stop(InvalidBody)
    }
    let object = match
      @decode.closed_object(root, [
        "version", "node_id_contract", "node_properties", "edge_properties", "edge_labels",
        "identity_law_cid", "value_law_cid",
      ]) {
      Ok(v) => v
      Err(_) => stop(InvalidBody)
    }
    if text_value(required(object, "version"), b) != "actql-graph-contract/0.1" {
      stop(InvalidBody)
    }
    for key in ["identity_law_cid", "value_law_cid"] {
      if text_value(required(object, key), b) != law_cid() {
        stop(LawMismatch)
      }
    }
    let id = read_type(required(object, "node_id_contract"), b)
    let nodes = read_properties(required(object, "node_properties"), b, limits)
    let edges = read_properties(required(object, "edge_properties"), b, limits)
    let label_cursor = required(object, "edge_labels")
    let labels = if @decode.is_null(label_cursor) {
      charge_nodes(b, 1)
      None
    } else {
      let count = match @decode.array_length(label_cursor) {
        Some(n) => n
        None => stop(InvalidBody)
      }
      charge_nodes(b, 1)
      charge_nodes(b, count)
      let values = []
      let mut previous = None
      for i in 0..<count {
        let label = text_value(@decode.element_at(label_cursor, i).unwrap(), b)
        if previous is Some(p) && @unicode.compare_utf16(p, label) >= 0 {
          stop(NonCanonicalLabels)
        }
        previous = Some(label)
        values.push(label)
      }
      Some(values)
    }
    let carrier = match
      @carrier.graph(
        id,
        nodes,
        edges,
        labels~,
        max_labels=limits.max_nodes,
        max_label_bytes=limits.max_bytes,
      ) {
      Ok(v) => v
      Err(_) => stop(InvalidStructure)
    }
    match admit(carrier, limits) {
      Ok(v) => Ok(v)
      Err(_) => stop(BudgetExceeded)
    }
  } catch {
    ReadStop(e) => Err(e)
  }
}
