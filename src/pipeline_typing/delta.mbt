///|
/// Expected contract identity, not proof that a row is a valid Delta.
priv struct DeltaEvidence {
  fields : Map[String, @graph_contract.CheckedContract]
}

///|
fn empty_delta() -> DeltaEvidence {
  { fields: Map([]), }
}

///|
fn delta_at(
  target : Target,
  inputs : Array[DeltaEvidence],
  steps : Array[DeltaEvidence],
) -> DeltaEvidence {
  match target {
    Input(i) => inputs[i]
    Step(i) => steps[i]
  }
}

///|
fn sync_delta(
  b : Budget,
  source : @decode.Cursor,
  inputs : Array[DeltaEvidence],
  steps : Array[CheckedStep],
  evidence : Array[DeltaEvidence],
) -> Unit raise Stop {
  while evidence.length() < steps.length() {
    let step = steps[evidence.length()]
    let previous = match step.input {
      Some(t) => delta_at(t, inputs, evidence)
      None => empty_delta()
    }
    let next = match step.operation {
      GraphDiff(checked~, ..) => {
        spend(b, source, 1)
        charge(b, source, "delta")
        { fields: Map([("delta", @graph.diff_graph_contract(checked))]), }
      }
      Unary(op) => transfer_delta(b, source, previous, op)
      _ => empty_delta()
    }
    evidence.push(next)
  }
}

///|
fn transfer_delta(
  b : Budget,
  source : @decode.Cursor,
  previous : DeltaEvidence,
  op : @relation.CheckedOperation,
) -> DeltaEvidence raise Stop {
  if previous.fields.is_empty() {
    return previous
  }
  match @relation.operation(op) {
    Filter
    | Sort
    | Take
    | AssertRows
    | DedupeRows
    | TopK
    | TopKBy
    | Lag
    | WatermarkRows => previous
    Derive => {
      spend(b, source, @relation.binding_count(op) + previous.fields.length())
      let overwritten : Map[String, Bool] = Map([])
      for i in 0..<@relation.binding_count(op) {
        if @relation.binding_at(op, i).unwrap().name is Some(name) {
          overwritten[name] = true
        }
      }
      let fields : Map[String, @graph_contract.CheckedContract] = Map([])
      for key, value in previous.fields {
        if !overwritten.contains(key) {
          fields[key] = value
        }
      }
      { fields, }
    }
    Select | Rename | Drop | Distinct => {
      if @relation.row_operation(op) is Some(DistinctRows) {
        return previous
      }
      let projection = @relation.projection(op)
      spend(b, source, projection.length())
      let fields : Map[String, @graph_contract.CheckedContract] = Map([])
      for p in projection {
        if previous.fields.get(@schema.reference_name(p.input)) is Some(c) {
          let name = @schema.reference_name(p.output)
          charge(b, source, name)
          fields[name] = c
        }
      }
      { fields, }
    }
    _ => empty_delta()
  }
}

///|
/// A retained expectation still requires exact CID and semantic data admission.
pub fn expected_delta_contract(
  p : CheckedPipeline,
  target : Target,
  field : @schema.FieldName,
) -> @graph_contract.CheckedContract? {
  let values = match target {
    Input(i) =>
      if i < 0 || i >= p.delta_inputs.length() {
        return None
      } else {
        p.delta_inputs[i]
      }
    Step(i) =>
      if i < 0 || i >= p.delta_steps.length() {
        return None
      } else {
        p.delta_steps[i]
      }
  }
  guard carrier(target, p.inputs, p.steps) is @carrier.Relation(rows) else {
    return None
  }
  guard @carrier.lookup(rows, field) is Present(_) else { return None }
  values.fields.get(@schema.reference_name(field))
}
