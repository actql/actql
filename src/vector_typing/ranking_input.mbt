///|
/// Row shape and producer-bound composite identities are distinct evidence.
struct RankingInput {
  carrier : @carrier.Carrier
  nearest : CheckedNearest?
  fusion : CheckedRanking?
  lexical : CheckedTextRank?
  score_declaration : DeclaredScore?
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
    tuples: Map([]),
  }
}

///|
/// The producer supplies both the output contract and positional identity domains.
pub fn ranking_from_nearest(input : CheckedNearest) -> RankingInput {
  let tuples : Map[String, Int] = Map([])
  for
    (name, side) in [
      ("query_id", input.pair.queries),
      ("candidate_id", input.pair.candidates),
    ] {
    if side.vectors is Some(v) && @carrier.vector_identity_count(v) > 1 {
      tuples[name] = @carrier.vector_identity_count(v)
    }
  }
  {
    carrier: input.output,
    nearest: Some(input),
    fusion: None,
    lexical: None,
    score_declaration: None,
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
  b : Budget,
  at : @decode.Cursor,
  input : RankingInput,
  name : @row.FieldName,
  contract : @contract.Contract,
  nonnull : Bool,
) -> Unit raise Stop {
  spend(b, at, 1)
  charge(b, at, @row.reference_name(name))
  if nonnull && contract.nullable {
    fail(at, InvalidRankingField(name))
  }
  if @contract.key_comparable(contract, contract) {
    return
  }
  // Only the producing checker can attest that this object encodes an ordered
  // semantic identity tuple. An arbitrary object with the same shape cannot.
  guard input.tuples.get(@row.reference_name(name)) is Some(count) else {
    fail(at, InvalidRankingField(name))
  }
  spend(b, at, count)
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
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    let rows = match input.carrier {
      @carrier.Relation(r) => r
      _ => fail(source, WrongCarrier(@carrier.kind(input.carrier)))
    }
    let schema = match @carrier.complete_schema(rows) {
      Some(s) => s
      None => fail(source, IncompleteRankingInput)
    }
    let root = decoded(@decode.open_object(source))
    let by = decoded(@decode.elements(decoded(@decode.required(root, "by"))))
    spend(b, source, options.by.length())
    for i in 0..<options.by.length() {
      let name = options.by[i]
      let c = match @row.lookup(schema, name) {
        Some(c) => c
        None => fail(by[i], InvalidRankingField(name))
      }
      ranking_identity(b, by[i], input, name, c, false)
    }
    let at = decoded(@decode.required(root, "candidate"))
    let name = options.candidate
    let c = match @row.lookup(schema, name) {
      Some(c) => c
      None => fail(at, InvalidRankingField(name))
    }
    ranking_identity(b, at, input, name, c, true)
    let key = if options.policy == ReciprocalRank { "rank" } else { "score" }
    let at = decoded(@decode.required(root, key))
    let name = if options.policy == ReciprocalRank {
      options.rank.unwrap()
    } else {
      options.score.unwrap()
    }
    spend(b, at, 1)
    charge(b, at, @row.reference_name(name))
    match @row.lookup(schema, name) {
      Some({ nullable: false, shape: Number, }) => ()
      _ => fail(at, InvalidRankingField(name))
    }
    if options.tie_break is Some(names) {
      let items = decoded(
        @decode.elements(decoded(@decode.required(root, "tie_break"))),
      )
      spend(b, source, names.length())
      for i in 0..<names.length() {
        let name = names[i]
        spend(b, items[i], 1)
        charge(b, items[i], @row.reference_name(name))
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
          _ => fail(items[i], InvalidRankingField(name))
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
    Stop(e) => Err(e)
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
