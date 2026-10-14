///|
// A syntax-only walk of the already admitted query decides whether identity
// labels are needed at all. It proves no key and does no semantic checking.
fn query_has_omitted_infer(root : @query.Query) -> Bool {
  let pending = [root]
  while pending.pop() is Some(query) {
    for index in 0..<@query.operation_count(query) {
      if @query.operation_at(query, index) is Some(Infer({ keys: None, .. })) {
        return true
      }
    }
    for index in 0..<@query.query_binding_count(query) {
      pending.push(@query.query_binding_at(query, index).unwrap().query)
    }
    for index in 0..<@query.set_part_count(query) {
      pending.push(@query.set_part_at(query, index).unwrap().right)
    }
  }
  false
}

///|
fn spend_infer_key_label_pair(
  construction : Construction,
  entry : (String, String),
) -> Unit raise Abort {
  construction.infer_budget.spend(1, construction.generated)
  construction.infer_budget.spend_text(entry.0, construction.generated)
  construction.infer_budget.spend_text(entry.1, construction.generated)
}

///|
// Match positional_named_expression_columns, without multiplying every column
// by the alias/private-field arrays. First authored alias wins as before.
fn infer_key_column_names(
  construction : Construction,
  columns : Array[(String, String)],
  private_fields : Array[String],
  authored_aliases : Array[(String, String)],
) -> Array[(String, String)] raise Abort {
  if !construction.infer_labels {
    return []
  }
  let private_names : Map[String, Bool] = Map([])
  for name in private_fields {
    construction.infer_budget.spend(1, construction.generated)
    construction.infer_budget.spend_text(name, construction.generated)
    private_names[name] = true
  }
  let aliases : Map[String, String] = Map([])
  for entry in authored_aliases {
    spend_infer_key_label_pair(construction, entry)
    construction.infer_budget.spend_text(entry.0, construction.generated)
    if !aliases.contains(entry.0) {
      aliases[entry.0] = entry.1
    }
  }
  let result : Array[(String, String)] = []
  for entry in columns {
    spend_infer_key_label_pair(construction, entry)
    construction.infer_budget.spend_text(entry.0, construction.generated)
    match aliases.get(entry.0) {
      Some(name) => result.push((name, entry.1))
      None => if !private_names.contains(entry.0) { result.push(entry) }
    }
  }
  result
}

///|
// Add fresh authored columns, without reviving an older visible/range label
// for a slot whose newer name was already retained by an earlier scope.
fn seed_infer_key_labels(
  construction : Construction,
  previous : Array[(String, String)],
  columns : Array[(String, String)],
) -> Array[(String, String)] raise Abort {
  if !construction.infer_labels {
    return []
  }
  let known : Map[String, Bool] = Map([])
  let labels : Array[(String, String)] = []
  for entry in previous {
    spend_infer_key_label_pair(construction, entry)
    known[entry.0] = true
    labels.push(entry)
  }
  for entry in columns {
    spend_infer_key_label_pair(construction, entry)
    construction.infer_budget.spend_text(entry.1, construction.generated)
    if !known.contains(entry.1) {
      known[entry.1] = true
      labels.push((entry.1, entry.0))
    }
  }
  labels
}

///|
fn remap_infer_key_labels(
  construction : Construction,
  previous : Array[(String, String)],
  slots : Map[String, String],
) -> Array[(String, String)] raise Abort {
  if !construction.infer_labels {
    return []
  }
  let labels : Array[(String, String)] = []
  for entry in previous {
    spend_infer_key_label_pair(construction, entry)
    if slots.get(entry.0) is Some(slot) {
      labels.push((slot, entry.1))
    }
  }
  labels
}

///|
// Identity-bearing names follow exact surviving slot generations. Linear maps
// replace cross-products, and every metadata pass spends the same allowance
// later lent to Common/carrier checks before performing its work.
fn retain_infer_key_labels(
  construction : Construction,
  previous : Array[(String, String)],
  before : Array[(String, String)],
  after : Array[(String, String)],
  physical : Array[String],
  reset~ : Bool,
) -> Array[(String, String)] raise Abort {
  if !construction.infer_labels {
    return []
  }
  let live : Map[String, Bool] = Map([])
  let old_names : Map[String, Map[String, Bool]] = Map([])
  let indices : Map[String, Int] = Map([])
  let labels : Array[(String, String)] = []
  if !reset {
    for slot in physical {
      construction.infer_budget.spend(1, construction.generated)
      construction.infer_budget.spend_text(slot, construction.generated)
      live[slot] = true
    }
    for entry in previous {
      spend_infer_key_label_pair(construction, entry)
      construction.infer_budget.spend_text(entry.0, construction.generated)
      if live.contains(entry.0) {
        indices[entry.0] = labels.length()
        labels.push(entry)
      }
    }
    for entry in before {
      spend_infer_key_label_pair(construction, entry)
      construction.infer_budget.spend_text(entry.1, construction.generated)
      let names = match old_names.get(entry.1) {
        Some(names) => names
        None => {
          let names : Map[String, Bool] = Map([])
          old_names[entry.1] = names
          names
        }
      }
      names[entry.0] = true
    }
  }
  for entry in after {
    spend_infer_key_label_pair(construction, entry)
    construction.infer_budget.spend_text(entry.1, construction.generated)
    if !reset &&
      old_names
      .get(entry.1)
      .map(names => names.contains(entry.0))
      .unwrap_or(false) {
      continue
    }
    // Only a name introduction/RENAME changes chronology. Visiting an old
    // range or dropping a newer alias never restores its former name.
    match indices.get(entry.1) {
      Some(index) => labels[index] = (entry.1, entry.0)
      None => {
        construction.infer_budget.spend_text(entry.1, construction.generated)
        indices[entry.1] = labels.length()
        labels.push((entry.1, entry.0))
      }
    }
  }
  labels
}

///|
// A scalar value-table range alias names its existing value slot. Do not
// mutate the producer's stored scope while binding a consuming range.
fn rename_infer_key_label(
  construction : Construction,
  previous : Array[(String, String)],
  slot : String,
  name : String,
) -> Array[(String, String)] raise Abort {
  if !construction.infer_labels {
    return []
  }
  let labels : Array[(String, String)] = []
  let mut found = false
  for entry in previous {
    spend_infer_key_label_pair(construction, entry)
    construction.infer_budget.spend_text(slot, construction.generated)
    if entry.0 == slot {
      construction.infer_budget.spend_text(name, construction.generated)
      labels.push((slot, name))
      found = true
    } else {
      labels.push(entry)
    }
  }
  if !found {
    spend_infer_key_label_pair(construction, (slot, name))
    labels.push((slot, name))
  }
  labels
}
