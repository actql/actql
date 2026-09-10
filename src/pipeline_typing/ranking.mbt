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
  steps : Array[CheckedStep],
) -> @vector.RankingInput {
  match target {
    Input(i) => rankings[i].unwrap_or(@vector.ranking_relation(inputs[i].1))
    Step(i) =>
      match steps[i].operation {
        Nearest(checked~, ..) => @vector.ranking_from_nearest(checked)
        Ranking(checked) => @vector.ranking_from_fusion(checked)
        _ => @vector.ranking_relation(steps[i].output)
      }
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
  Some(ranking_at(target, value.inputs, value.ranked_inputs, value.steps))
}
