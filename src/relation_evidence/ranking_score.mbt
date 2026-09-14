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
    let declaration : DeclaredScore = {
      source,
      records: rows,
      field,
      contract,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    }
    Ok({
      carrier: input,
      nearest: None,
      fusion: None,
      lexical: None,
      tuples: Map([]),
      score_aliases: Map([(ranking_field_key(field), declaration)]),
      score_declaration: Some(declaration),
    })
  } catch {
    @checking.Stop(e) => Err(e)
  }
}

///|
/// Returns the sole distinct retained declaration, not an arbitrary score field.
/// Use ranking_score_at when more than one input score is declared.
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
  input.score_aliases.get(ranking_field_key(field))
}

///|
fn sole_score(scores : Map[String, DeclaredScore]) -> DeclaredScore? {
  let mut result = None
  for _, declaration in scores {
    match result {
      None => result = Some(declaration)
      Some(previous) =>
        if !physical_equal(previous, declaration) {
          return None
        }
    }
  }
  result
}

///|
/// Admit a field-scoped map of captured-input assertions, never execution proof.
/// Each declaration remains bound to the same original input and its own field.
pub fn declare_ranking_scores(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : @checking.Limits,
) -> Result[RankingTransfer, @checking.Issue] {
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
    guard input is @carrier.Relation(_) else {
      @checking.fail(source, WrongCarrier(@carrier.kind(input)))
    }
    // Preflight the complete map; each declaration's admission is a separate
    // bounded pass whose usage is also returned to the caller.
    @checking.scan(b, source)
    let _ = @checking.decoded(@decode.open_object(source))
    let count = @decode.object_length(source).unwrap()
    @checking.spend(b, source, count)
    let scores : Map[String, DeclaredScore] = Map([])
    for i in 0..<count {
      let (name, at) = @decode.field_at(source, i).unwrap()
      let value = match
        declare_ranking_score(at, input, @row.Unqualified(name), {
          max_work: b.work,
          max_nodes: b.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: b.text,
        }) {
        Ok(value) => value
        Err(issue) => raise @checking.Stop(issue)
      }
      let declaration = value.score_declaration.unwrap()
      b.work -= declaration.usage.work
      b.nodes -= declaration.usage.nodes
      b.text -= declaration.usage.text_bytes
      scores[ranking_field_key(@row.Unqualified(name))] = declaration
    }
    @checking.spend(b, source, count)
    Ok({
      input: {
        ..ranking_relation(input),
        score_aliases: scores,
        score_declaration: sole_score(scores),
      },
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    @checking.Stop(issue) => Err(issue)
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
