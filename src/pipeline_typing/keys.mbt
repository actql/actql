///|
fn key_at(
  target : Target,
  inputs : Array[@evidence.KeyedRelation?],
  steps : Array[@evidence.KeyedRelation?],
) -> @evidence.KeyedRelation? {
  match target {
    Input(i) => inputs[i]
    Step(i) => steps[i]
  }
}

///|
fn sync_keys(
  b : Budget,
  inputs : Array[@evidence.KeyedRelation?],
  steps : Array[CheckedStep],
  keys : Array[@evidence.KeyedRelation?],
) -> Unit raise Stop {
  while keys.length() < steps.length() {
    let step = steps[keys.length()]
    let previous = step.input.bind(t => key_at(t, inputs, keys))
    let next = match (previous, step.operation) {
      (Some(key), Unary(op)) => {
        let transfer = match
          @evidence.transfer_unary(key, op, {
            max_work: b.work,
            max_name_bytes: b.text,
          }) {
          Ok(v) => v
          Err(e) =>
            raise Stop({
              kind: KeyEvidence(e.kind),
              source: step.source,
              path: e.path.copy(),
              span: e.span,
              range: None,
            })
        }
        b.work -= transfer.work
        b.text -= transfer.name_bytes
        transfer.key
      }
      _ => None
    }
    keys.push(next)
  }
}

///|
/// Conditional key dependencies survive transfers; this is not a data check.
pub fn candidate_key(
  value : CheckedPipeline,
  target : Target,
) -> @evidence.KeyedRelation? {
  match target {
    Input(i) => value.keyed_inputs.get(i).bind(v => v)
    Step(i) => value.keyed_steps.get(i).bind(v => v)
  }
}
