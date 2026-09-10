///|
struct DeclaredScore {
  source : @decode.Cursor
  field : @row.FieldName
  contract : ScoreContract
  usage : Usage
}

///|
/// Captured-input semantic assertion, not a normalization operation. Consumers
/// must authenticate the declaration and validate scores against its finite range.
pub fn declare_ranking_score(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  field : @row.FieldName,
  limits : Limits,
) -> Result[RankingInput, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let contract = read_score_contract(source)
    let rows = match input {
      @carrier.Relation(r) => r
      _ => fail(source, WrongCarrier(@carrier.kind(input)))
    }
    spend(b, source, 1)
    charge(b, source, @row.reference_name(field))
    match @carrier.lookup(rows, field) {
      Present({ contract: Some({ nullable: false, shape: Number, }), .. }) => ()
      _ => fail(source, InvalidRankingField(field))
    }
    Ok({
      carrier: input,
      nearest: None,
      fusion: None,
      tuples: Map([]),
      score_declaration: Some({
        source,
        field,
        contract,
        usage: {
          work: limits.max_work - b.work,
          nodes: limits.max_nodes - b.nodes,
          text_bytes: limits.max_text_bytes - b.text,
        },
      }),
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn ranking_score_declaration(input : RankingInput) -> DeclaredScore? {
  input.score_declaration
}

///|
pub fn declared_score_source(value : DeclaredScore) -> @decode.Cursor {
  value.source
}

///|
pub fn declared_score_field(value : DeclaredScore) -> @row.FieldName {
  value.field
}

///|
pub fn declared_score_contract(value : DeclaredScore) -> ScoreContract {
  value.contract
}

///|
pub fn declared_score_usage(value : DeclaredScore) -> Usage {
  value.usage
}
