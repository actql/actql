///|
pub enum SchemaIssue {
  InvalidLimits
  BudgetExceeded
  UnknownInput(String)
  DuplicateInput(String)
  Assertion(String, @local_input.SchemaIssue)
}

///|
struct SchemaAssertions {
  prepared : Prepared
  agreements : Array[@local_input.SchemaAgreement?]
  usage : Usage
}

///|
/// Reconcile a partial set of supplied schemas against exact source slots.
/// This is type evidence only, not Check Environment or Host admission.
pub fn reconcile_schemas(
  prepared : Prepared,
  supplied : Array[(String, @schema.Schema)],
  limits : Limits,
) -> Result[SchemaAssertions, SchemaIssue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let mut work = limits.max_work
  for
    cost in [prepared.usage.work, prepared.entries.length(), supplied.length()] {
    if cost > work {
      return Err(BudgetExceeded)
    }
    work -= cost
  }
  if prepared.usage.nodes > limits.max_nodes ||
    prepared.usage.text_bytes > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let mut nodes = limits.max_nodes - prepared.usage.nodes
  let mut text = limits.max_text_bytes - prepared.usage.text_bytes
  let names : Map[String, Int] = Map([])
  for i in 0..<prepared.entries.length() {
    names[prepared.entries[i].0] = i
  }
  let agreements : Array[@local_input.SchemaAgreement?] = Array::make(
    prepared.entries.length(),
    None,
  )
  for (name, schema) in supplied {
    match @scalar.admit_utf8_length(name, text) {
      Ok(n) => text -= n
      Err(_) => return Err(BudgetExceeded)
    }
    let index = match names.get(name) {
      Some(i) => i
      None => return Err(UnknownInput(name))
    }
    if agreements[index] is Some(_) {
      return Err(DuplicateInput(name))
    }
    let agreement = match
      @local_input.check_schema(prepared.entries[index].1, schema, {
        max_nodes: if nodes < work {
          nodes
        } else {
          work
        },
        max_depth: limits.max_depth,
        max_text_bytes: text,
      }) {
      Ok(v) => v
      Err(@local_input.BudgetExceeded) => return Err(BudgetExceeded)
      Err(e) => return Err(Assertion(name, e))
    }
    let cost = @local_input.schema_usage(agreement)
    nodes -= cost.nodes
    work -= cost.nodes
    text -= cost.text_bytes
    agreements[index] = Some(agreement)
  }
  Ok({
    prepared,
    agreements,
    usage: {
      work: limits.max_work - work,
      nodes: limits.max_nodes - nodes,
      text_bytes: limits.max_text_bytes - text,
    },
  })
}

///|
pub fn schema_inputs(v : SchemaAssertions) -> Prepared {
  v.prepared
}

///|
pub fn schema_agreement_at(
  v : SchemaAssertions,
  index : Int,
) -> @local_input.SchemaAgreement? {
  v.agreements.get(index).bind(x => x)
}

///|
pub fn schema_assertion_usage(v : SchemaAssertions) -> Usage {
  v.usage
}
