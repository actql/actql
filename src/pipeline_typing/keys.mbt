///|
fn key_at(
  target : Target,
  inputs : Array[@evidence.KeySet?],
  steps : Array[@evidence.KeySet?],
) -> @evidence.KeySet? {
  match target {
    Input(i) => inputs[i]
    Step(i) => steps[i]
  }
}

///|
fn nearest_input_source(
  target : Target,
  inputs : Array[(String, @carrier.Carrier)],
  steps : Array[CheckedStep],
  keys : Array[@evidence.KeySet?],
  step_keys : Array[@evidence.KeySet?],
) -> @vector.NearestSource {
  match key_at(target, keys, step_keys) {
    Some(k) => KeySource(k)
    None => CarrierSource(carrier(target, inputs, steps))
  }
}

///|
fn asof_input_source(
  target : Target,
  inputs : Array[(String, @carrier.Carrier)],
  steps : Array[CheckedStep],
  keys : Array[@evidence.KeySet?],
  step_keys : Array[@evidence.KeySet?],
) -> @join.AsOfSource {
  match key_at(target, keys, step_keys) {
    Some(k) => KeySource(k)
    None => CarrierSource(carrier(target, inputs, steps))
  }
}

///|
fn sync_keys(
  b : Budget,
  inputs : Array[@evidence.KeySet?],
  steps : Array[CheckedStep],
  keys : Array[@evidence.KeySet?],
) -> Unit raise Stop {
  while keys.length() < steps.length() {
    let step = steps[keys.length()]
    let previous = step.input.bind(t => key_at(t, inputs, keys))
    let next = match (previous, step.operation) {
      (Some(previous), Window(op)) => {
        let transfer = match
          @evidence.transfer_window_keys(previous, op, {
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
        Some(transfer.keys)
      }
      (Some(previous), Set(checked~, ..)) => {
        let transfer = match
          @evidence.transfer_set_keys(previous, checked, {
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
        Some(transfer.keys)
      }
      (Some(previous), Nest(checked~, ..)) => {
        let transfer = match
          @evidence.transfer_nest_keys(previous, checked, {
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
        Some(transfer.keys)
      }
      (_, Projection(op)) if @projection.operation(op) == @projection.NodeRows ||
        @projection.operation(op) == @projection.EdgeRows => {
        let transfer = match
          @evidence.graph_projection_keys(op, {
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
        Some(transfer.keys)
      }
      (_, Projection(op)) if @projection.operation(op) == @projection.Vectors => {
        let transfer = match
          @evidence.vector_projection_keys(op, {
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
        Some(transfer.keys)
      }
      (_, TimeSeries(op)) => {
        let transfer = match
          @evidence.time_series_keys(op, {
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
        Some(transfer.keys)
      }
      (previous, Calendar(op)) => {
        let transfer = match
          @evidence.advance_calendar_keys(previous, op, {
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
        Some(transfer.keys)
      }
      (previous, Unary(op) | WindowGroup(op)) => {
        let transfer = match
          @evidence.advance_keys(previous, op, {
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
        Some(transfer.keys)
      }
      _ => None
    }
    keys.push(next)
  }
}

///|
/// Returns the sole witness, not a preferred key when multiple witnesses exist.
pub fn candidate_key(
  value : CheckedPipeline,
  target : Target,
) -> @evidence.KeyedRelation? {
  candidate_keys(value, target).bind(single_candidate)
}

///|
fn single_candidate(value : @evidence.KeySet) -> @evidence.KeyedRelation? {
  if @evidence.key_witness_count(value) == 1 {
    @evidence.key_witness_at(value, 0)
  } else {
    None
  }
}

///|
/// Conditional witnesses retain their admission requirements, not runtime proof.
pub fn candidate_keys(
  value : CheckedPipeline,
  target : Target,
) -> @evidence.KeySet? {
  match target {
    Input(i) => value.keyed_inputs.get(i).bind(v => v)
    Step(i) => value.keyed_steps.get(i).bind(v => v)
  }
}
