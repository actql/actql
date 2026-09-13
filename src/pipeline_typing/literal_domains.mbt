///|
fn literal_at(
  target : Target,
  inputs : Array[@evidence.LiteralDomains?],
  steps : Array[@evidence.LiteralDomains?],
) -> @evidence.LiteralDomains? {
  match target {
    Input(i) => inputs[i]
    Step(i) => steps[i]
  }
}

///|
pub fn literal_domains(
  pipeline : CheckedPipeline,
  target : Target,
) -> @evidence.LiteralDomains? {
  guard carrier_at(pipeline, target) is Some(_) else { return None }
  literal_at(target, pipeline.literal_inputs, pipeline.literal_steps)
}

///|
fn literal_result(
  b : Budget,
  source : @decode.Cursor,
  result : Result[@evidence.LiteralTransfer, @evidence.Issue],
) -> @evidence.LiteralDomains raise Stop {
  match result {
    Ok(value) => {
      b.work -= value.work
      b.text -= value.text_bytes
      value.domains
    }
    Err(e) =>
      raise Stop({
        kind: KeyEvidence(e.kind),
        source,
        path: e.path.copy(),
        span: e.span,
        range: None,
      })
  }
}
