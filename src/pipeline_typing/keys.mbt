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
  let actual = carrier(target, inputs, steps)
  if @carrier.kind(actual) != @carrier.RelationKind {
    return CarrierSource(actual)
  }
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
  let actual = carrier(target, inputs, steps)
  if @carrier.kind(actual) != @carrier.RelationKind {
    return CarrierSource(actual)
  }
  match key_at(target, keys, step_keys) {
    Some(k) => KeySource(k)
    None => CarrierSource(carrier(target, inputs, steps))
  }
}

///|
fn graph_key_operation(
  operation : CheckedOperation,
) -> @evidence.GraphKeyOperation? {
  match operation {
    Graph(op) if @graph.operation(op) != NormalizeGraph =>
      Some(GraphOperation(op))
    GraphMatch(op) => Some(MatchOperation(op))
    Reach(op) => Some(ReachOperation(op))
    Traverse(checked~, ..) => Some(TraverseOperation(checked))
    Shortest(checked~, ..) => Some(ShortestOperation(checked))
    _ => None
  }
}

///|
fn sync_keys(
  b : Budget,
  inputs : Array[@evidence.KeySet?],
  steps : Array[CheckedStep],
  keys : Array[@evidence.KeySet?],
  literal_inputs : Array[@evidence.LiteralDomains?],
  literal_steps : Array[@evidence.LiteralDomains?],
) -> Unit raise Stop {
  while keys.length() < steps.length() {
    let step = steps[keys.length()]
    let previous = step.input.bind(t => key_at(t, inputs, keys))
    let previous_literals = step.input.bind(t => {
      literal_at(t, literal_inputs, literal_steps)
    })
    let domains = match step.operation {
      Unary(op) =>
        Some(
          literal_result(
            b,
            step.source,
            @evidence.transfer_literal_domains(previous_literals, op, {
              max_work: b.work,
              max_name_bytes: b.text,
            }),
          ),
        )
      Append(right~, checked~) =>
        Some(
          literal_result(
            b,
            step.source,
            @evidence.append_literal_domains(
              previous_literals,
              literal_at(right, literal_inputs, literal_steps),
              checked,
              { max_work: b.work, max_name_bytes: b.text, },
            ),
          ),
        )
      _ => None
    }
    let next = match (previous, step.operation) {
      (previous, Append(right~, checked~)) => {
        let transfer = match
          @evidence.append_keys(
            previous,
            key_at(right, inputs, keys),
            previous_literals,
            literal_at(right, literal_inputs, literal_steps),
            checked,
            { max_work: b.work, max_name_bytes: b.text, },
          ) {
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
      (_, Ranking(checked)) => {
        let transfer = match
          @evidence.merged_ranking_keys(checked, {
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
      (_, TextRank(checked~, ..)) => {
        let transfer = match
          @evidence.text_rank_keys(checked, {
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
      (_, Nearest(checked~, ..)) => {
        let transfer = match
          @evidence.nearest_keys(checked, {
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
      (_, op) if graph_key_operation(op) is Some(operation) => {
        let transfer = match
          @evidence.graph_query_keys(operation, {
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
      (_, Sequence(operation)) => {
        let transfer = match
          @evidence.sequence_keys(operation, {
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
      (previous, AsOfJoin(checked~, ..)) => {
        let transfer = match
          @evidence.transfer_asof_keys(previous, checked, {
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
      (previous, IntervalJoin(right~, checked~)) => {
        let transfer = match
          @evidence.transfer_interval_join_keys(
            previous,
            key_at(right, inputs, keys),
            checked,
            { max_work: b.work, max_name_bytes: b.text, },
          ) {
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
      (previous, CrossJoin(right~, checked~)) => {
        let transfer = match
          @evidence.transfer_cross_join_keys(
            previous,
            key_at(right, inputs, keys),
            checked,
            { max_work: b.work, max_name_bytes: b.text, },
          ) {
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
      (previous, Join(right~, checked~)) => {
        let transfer = match
          @evidence.transfer_join_keys(
            previous,
            key_at(right, inputs, keys),
            checked,
            { max_work: b.work, max_name_bytes: b.text, },
          ) {
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
      (previous, Event(op)) => {
        let t = match
          @evidence.advance_event_keys(previous, op, {
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
        b.work -= t.work
        b.text -= t.name_bytes
        Some(t.keys)
      }
      (Some(previous), Projection(op)) if @projection.operation(op) ==
        @projection.Events => {
        let t = match
          @evidence.transfer_events_projection_keys(previous, op, {
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
        b.work -= t.work
        b.text -= t.name_bytes
        Some(t.keys)
      }
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
      (previous, Set(checked~, ..)) => {
        let transfer = match
          @evidence.advance_set_keys(previous, checked, {
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
    literal_steps.push(domains)
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
  guard carrier_at(value, target) is Some(@carrier.Relation(_)) else {
    return None
  }
  match target {
    Input(i) => value.keyed_inputs.get(i).bind(v => v)
    Step(i) => value.keyed_steps.get(i).bind(v => v)
  }
}
