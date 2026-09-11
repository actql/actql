///|
struct DeclaredScore {
  source : @decode.Cursor
  records : @carrier.Knowledge
  field : @row.FieldName
  contract : ScoreContract
  usage : @checking.Usage
}

///|
/// Captured-input semantic assertion, not a normalization operation. Consumers
/// must authenticate the declaration and validate scores against its finite range.
pub fn declare_ranking_score(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  field : @row.FieldName,
  limits : @checking.Limits,
) -> Result[RankingInput, @checking.Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      @checking.fail(source, InvalidLimits)
    }
    let b : @checking.Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    @checking.scan(b, source)
    let contract = read_score_contract(source)
    let rows = match input {
      @carrier.Relation(r) => r
      _ => @checking.fail(source, WrongCarrier(@carrier.kind(input)))
    }
    @checking.spend(b, source, 1)
    @checking.charge(b, source, @row.reference_name(field))
    match @carrier.lookup(rows, field) {
      Present({ contract: Some({ nullable: false, shape: Number, }), .. }) => ()
      _ => @checking.fail(source, InvalidRankingField(field))
    }
    Ok({
      carrier: input,
      nearest: None,
      fusion: None,
      lexical: None,
      tuples: Map([]),
      score_aliases: Map([(ranking_field_key(field), true)]),
      score_declaration: Some({
        source,
        records: rows,
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
    @checking.Stop(e) => Err(e)
  }
}

///|
pub fn ranking_score_declaration(input : RankingInput) -> DeclaredScore? {
  if input.score_aliases.is_empty() {
    None
  } else {
    input.score_declaration
  }
}

///|
/// Maps a current alias to its original captured-input declaration.
pub fn ranking_score_at(
  input : RankingInput,
  field : @row.FieldName,
) -> DeclaredScore? {
  if input.score_aliases.contains(ranking_field_key(field)) {
    input.score_declaration
  } else {
    None
  }
}

///|
pub fn declared_score_source(value : DeclaredScore) -> @decode.Cursor {
  value.source
}

///|
/// Original input row contract, before downstream aliases or projections.
pub fn declared_score_records(value : DeclaredScore) -> @carrier.Knowledge {
  value.records
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
pub fn declared_score_usage(value : DeclaredScore) -> @checking.Usage {
  value.usage
}
