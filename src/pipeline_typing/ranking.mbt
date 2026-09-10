///|
fn[T] vector_result(
  source : @decode.Cursor,
  result : Result[T, @vector.Issue],
) -> T raise Stop {
  match result {
    Ok(value) => value
    Err(e) =>
      raise Stop({
        kind: Vector(e.kind),
        source,
        path: e.path.copy(),
        span: e.span,
        range: None,
      })
  }
}

///|
fn ranking_at(
  target : Target,
  inputs : Array[(String, @carrier.Carrier)],
  rankings : Array[@vector.RankingInput?],
  steps : Array[@vector.RankingInput],
) -> @vector.RankingInput {
  match target {
    Input(i) => rankings[i].unwrap_or(@vector.ranking_relation(inputs[i].1))
    Step(i) => steps[i]
  }
}

///|
pub fn ranking_evidence(
  value : CheckedPipeline,
  target : Target,
) -> @vector.RankingInput? {
  if carrier_at(value, target) is None {
    return None
  }
  Some(
    ranking_at(target, value.inputs, value.ranked_inputs, value.ranked_steps),
  )
}

///|
fn sync_rankings(
  b : Budget,
  inputs : Array[(String, @carrier.Carrier)],
  rankings : Array[@vector.RankingInput?],
  steps : Array[CheckedStep],
  retained : Array[@vector.RankingInput],
) -> Unit raise Stop {
  while retained.length() < steps.length() {
    let step = steps[retained.length()]
    spend(b, step.source, 1)
    let next = match step.operation {
      Nearest(checked~, ..) => @vector.ranking_from_nearest(checked)
      Ranking(c) => @vector.ranking_from_fusion(c)
      TextRank(checked~, ..) => @vector.ranking_from_text(checked)
      Unary(op) => {
        let previous = ranking_at(
          step.input.unwrap(),
          inputs,
          rankings,
          retained,
        )
        let transfer = vector_result(
          step.source,
          @vector.transfer_ranking_unary(previous, op, {
            max_work: b.work,
            max_nodes: b.nodes,
            max_depth: b.limits.max_depth,
            max_text_bytes: b.text,
          }),
        )
        b.work -= transfer.usage.work
        b.nodes -= transfer.usage.nodes
        b.text -= transfer.usage.text_bytes
        transfer.input
      }
      _ => @vector.ranking_relation(step.output)
    }
    retained.push(next)
  }
}
