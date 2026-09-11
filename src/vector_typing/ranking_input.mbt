///|
fn ranking_field_key(name : @row.FieldName) -> String {
  match name {
    Unqualified(name) => "u:" + name
    Qualified(Left, name) => "l:" + name
    Qualified(Right, name) => "r:" + name
  }
}

///|
/// Row shape and producer-bound composite identities are distinct evidence.
struct RankingInput {
  carrier : @carrier.Carrier
  nearest : CheckedNearest?
  fusion : CheckedRanking?
  lexical : CheckedTextRank?
  score_declaration : DeclaredScore?
  score_aliases : Map[String, Bool]
  tuples : Map[String, Int]
}

///|
/// Ordinary input rows carry no implicit composite-identity or score evidence.
pub fn ranking_relation(input : @carrier.Carrier) -> RankingInput {
  {
    carrier: input,
    nearest: None,
    fusion: None,
    lexical: None,
    score_declaration: None,
    score_aliases: Map([]),
    tuples: Map([]),
  }
}

///|
/// The producer supplies both the output contract and positional identity domains.
pub fn ranking_from_nearest(input : CheckedNearest) -> RankingInput {
  let tuples : Map[String, Int] = Map([])
  for
    (name, side) in [
      ("query_id", nearest_pair_input(nearest_pair(input), Queries)),
      ("candidate_id", nearest_pair_input(nearest_pair(input), Candidates)),
    ] {
    if nearest_input_vectors(side) is Some(v) &&
      @carrier.vector_identity_count(v) > 1 {
      tuples[ranking_field_key(@row.Unqualified(name))] = @carrier.vector_identity_count(
        v,
      )
    }
  }
  {
    carrier: nearest_output(input),
    nearest: Some(input),
    fusion: None,
    lexical: None,
    score_declaration: None,
    score_aliases: Map([]),
    tuples,
  }
}

///|
/// Reuse semantic identity domains and retained producer obligations for RRF.
pub fn ranking_from_fusion(input : CheckedRanking) -> RankingInput {
  {
    carrier: input.output,
    nearest: None,
    fusion: Some(input),
    lexical: None,
    score_declaration: None,
    score_aliases: Map([]),
    tuples: input.tuples,
  }
}

///|
pub fn ranking_input_fusion(input : RankingInput) -> CheckedRanking? {
  input.fusion
}

///|
pub fn ranking_from_text(input : CheckedTextRank) -> RankingInput {
  {
    carrier: input.output,
    nearest: None,
    fusion: None,
    lexical: Some(input),
    score_declaration: None,
    score_aliases: Map([]),
    tuples: Map([]),
  }
}

///|
pub fn ranking_input_text(input : RankingInput) -> CheckedTextRank? {
  input.lexical
}

///|
pub fn ranking_input_carrier(input : RankingInput) -> @carrier.Carrier {
  input.carrier
}

///|
/// Producer obligations are retained, not discharged by role checking.
pub fn ranking_input_nearest(input : RankingInput) -> CheckedNearest? {
  input.nearest
}

///|
struct RankingShape {
  input : RankingInput
  options : RankingOptions
  schema : @row.Schema
  usage : Usage
}

///|
fn ranking_identity(
  b : @checking.Budget,
  at : @decode.Cursor,
  input : RankingInput,
  name : @row.FieldName,
  contract : @contract.Contract,
  nonnull : Bool,
) -> Unit raise @checking.Stop {
  @checking.spend(b, at, 1)
  @checking.charge(b, at, @row.reference_name(name))
  if nonnull && contract.nullable {
    @checking.fail(at, InvalidRankingField(name))
  }
  if @contract.key_comparable(contract, contract) {
    return
  }
  // Only the producing checker can attest that this object encodes an ordered
  // semantic identity tuple. An arbitrary object with the same shape cannot.
  guard input.tuples.get(ranking_field_key(name)) is Some(count) else {
    @checking.fail(at, InvalidRankingField(name))
  }
  @checking.spend(b, at, count)
}

///|
/// Checks roles against a complete typed ranking input, not the input's rows.
/// Cross-input domain alignment and score-contract matching are separate checks.
pub fn check_ranking_shape(
  options : RankingOptions,
  input : RankingInput,
  limits : Limits,
) -> Result[RankingShape, Issue] {
  try {
    let source = options.source
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
    let rows = match input.carrier {
      @carrier.Relation(r) => r
      _ => @checking.fail(source, WrongCarrier(@carrier.kind(input.carrier)))
    }
    let schema = match @carrier.complete_schema(rows) {
      Some(s) => s
      None => @checking.fail(source, IncompleteRankingInput)
    }
    let root = @checking.decoded(@decode.open_object(source))
    let by = @checking.decoded(
      @decode.elements(@checking.decoded(@decode.required(root, "by"))),
    )
    @checking.spend(b, source, options.by.length())
    for i in 0..<options.by.length() {
      let name = options.by[i]
      let c = match @row.lookup(schema, name) {
        Some(c) => c
        None => @checking.fail(by[i], InvalidRankingField(name))
      }
      ranking_identity(b, by[i], input, name, c, false)
    }
    let at = @checking.decoded(@decode.required(root, "candidate"))
    let name = options.candidate
    let c = match @row.lookup(schema, name) {
      Some(c) => c
      None => @checking.fail(at, InvalidRankingField(name))
    }
    ranking_identity(b, at, input, name, c, true)
    let key = if options.policy == ReciprocalRank { "rank" } else { "score" }
    let at = @checking.decoded(@decode.required(root, key))
    let name = if options.policy == ReciprocalRank {
      options.rank.unwrap()
    } else {
      options.score.unwrap()
    }
    @checking.spend(b, at, 1)
    @checking.charge(b, at, @row.reference_name(name))
    match @row.lookup(schema, name) {
      Some({ nullable: false, shape: Number, }) => ()
      _ => @checking.fail(at, InvalidRankingField(name))
    }
    if options.tie_break is Some(names) {
      let items = @checking.decoded(
        @decode.elements(@checking.decoded(@decode.required(root, "tie_break"))),
      )
      @checking.spend(b, source, names.length())
      for i in 0..<names.length() {
        let name = names[i]
        @checking.spend(b, items[i], 1)
        @checking.charge(b, items[i], @row.reference_name(name))
        match @row.lookup(schema, name) {
          Some(
            {
              shape: Text(_)
              | Number
              | Boolean
              | Decimal(..)
              | Date
              | Timestamp,
              ..
            }
          ) => ()
          _ => @checking.fail(items[i], InvalidRankingField(name))
        }
      }
    }
    Ok({
      input,
      options,
      schema,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    @checking.Stop(e) => Err(e)
  }
}

///|
pub fn ranking_shape_input(value : RankingShape) -> RankingInput {
  value.input
}

///|
pub fn ranking_shape_options(value : RankingShape) -> RankingOptions {
  value.options
}

///|
pub fn ranking_shape_schema(value : RankingShape) -> @row.Schema {
  value.schema
}

///|
pub fn ranking_shape_usage(value : RankingShape) -> Usage {
  value.usage
}
