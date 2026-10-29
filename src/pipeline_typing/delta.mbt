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
      Unary(op) => transfer_delta(b, source, previous, op)
      GraphDelta(checked~, ..) => {
        let next = empty_delta()
        if @graph.delta_operation(checked) is Difference {
          charge(b, source, "delta")
          next.fields["delta"] = @graph.delta_graph(checked)
        }
        next
      }
      _ => empty_delta()
    }
    evidence.push(next)
  }
}

///|
/// Synchronous callers drive the same original retained transfer body.
fn transfer_delta(
  b : Budget,
  source : @decode.Cursor,
  previous : DeltaEvidence,
  op : @relation.CheckedOperation,
) -> DeltaEvidence raise Stop {
  let original = begin_delta_transfer_read(b, source, previous, op)
  while original.state is Pending(_) {
    advance_delta_transfer_read(original)
  }
  let result = take_delta_transfer_read(original).unwrap()
  clear_delta_transfer_read(original)
  match result {
    Ok(value) => value
    Err(issue) => raise Stop(issue)
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
