///|
pub(all) enum Tokenizer {
  UnicodeWords
  CharBigram
} derive(Eq, Debug)

///|
pub(all) enum TextRankSide {
  Corpus
  Queries
} derive(Eq, Debug)

///|
pub struct TextRankRoles {
  identity : @row.FieldName
  text : @row.FieldName
}

///|
struct TextRankOptions {
  source : @decode.Cursor
  queries : String
  corpus : TextRankRoles
  query_roles : TextRankRoles
  tokenizer : Tokenizer
  k1 : Double
  length_normalization : Double
  k : Double
  usage : @checking.Usage
}

///|
pub fn read_text_rank_options(
  source : @decode.Cursor,
  limits : @checking.Limits,
) -> Result[TextRankOptions, @checking.Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_depth < 0 {
      @checking.fail(source, InvalidLimits)
    }
    let b : @checking.Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    @checking.scan(b, source)
    let root = @checking.decoded(
      @decode.closed_object(source, [
        "queries", "query_id", "query_text", "candidate_id", "candidate_text", "tokenizer",
        "scoring", "k",
      ]),
    )
    let queries = ranking_input_name(
      @checking.decoded(@decode.required(root, "queries")),
    )
    let corpus = {
      identity: @checking.role_name(
        @checking.decoded(@decode.required(root, "candidate_id")),
      ),
      text: @checking.role_name(
        @checking.decoded(@decode.required(root, "candidate_text")),
      ),
    }
    let query_roles = {
      identity: @checking.role_name(
        @checking.decoded(@decode.required(root, "query_id")),
      ),
      text: @checking.role_name(
        @checking.decoded(@decode.required(root, "query_text")),
      ),
    }
    let at = @checking.decoded(@decode.required(root, "tokenizer"))
    let tokenizer = match @checking.decoded(@decode.text(at)) {
      "unicode_words" => UnicodeWords
      "char_bigram" => CharBigram
      _ => @checking.fail(at, InvalidBody)
    }
    let scoring = @checking.decoded(
      @decode.closed_object(
        @checking.decoded(@decode.required(root, "scoring")),
        ["bm25"],
      ),
    )
    let bm25 = @checking.decoded(
      @decode.closed_object(
        @checking.decoded(@decode.required(scoring, "bm25")),
        ["k1", "b"],
      ),
    )
    let at = @checking.decoded(@decode.required(bm25, "k1"))
    let k1 = @checking.decoded(@decode.finite_number(at))
    if k1 <= 0 {
      @checking.fail(at, InvalidBody)
    }
    let at = @checking.decoded(@decode.required(bm25, "b"))
    let length_normalization = ranking_nonnegative(at)
    if length_normalization > 1 {
      @checking.fail(at, InvalidBody)
    }
    let k = ranking_positive(@checking.decoded(@decode.required(root, "k")))
    Ok({
      source,
      queries,
      corpus,
      query_roles,
      tokenizer,
      k1,
      length_normalization,
      k,
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
pub(all) enum TextRankObligation {
  ValidateCompleteTextInputs
  ValidateGlobalStringIdentities(TextRankSide)
  NormalizeAndTokenizeWithPinnedUnicode
  ResolveTokenizerAndNormalizedTextCeilings
  ComputeStatisticsFromAdmittedCorpusOnly
  EvaluatePinnedBm25AndCorrectlyRoundedLogarithm
  FoldTermsInCanonicalOrder
  RejectNonFiniteTextScores
  ExcludeZeroScoresAndHandleEmptyInputs
  OrderTextScoresAndSemanticIdentities
  AssignContiguousTextRanks
  ResolveTextRankProfile
  ResolveStatisticsScoringAndOutputResources
} derive(Eq, Debug)

///|
struct CheckedTextRank {
  profile : @text_rank_profile.Profile?
  options : TextRankOptions
  corpus : @carrier.Carrier
  queries : @carrier.Carrier
  output : @carrier.Carrier
  usage : @checking.Usage
}

///|
fn text_role(
  b : @checking.Budget,
  root : @decode.ObjectView,
  input : @carrier.Carrier,
  key : String,
  name : @row.FieldName,
) -> @contract.Contract raise @checking.Stop {
  let at = @checking.decoded(@decode.required(root, key))
  let rows = match input {
    @carrier.Relation(r) => r
    _ => @checking.fail(at, WrongCarrier(@carrier.kind(input)))
  }
  @checking.spend(b, at, 1)
  @checking.charge(b, at, @row.reference_name(name))
  match @carrier.lookup(rows, name) {
    Present({ contract: Some(c), .. }) =>
      match c {
        { nullable: false, shape: Text(_), } => c
        _ => @checking.fail(at, InvalidRankingField(name))
      }
    _ => @checking.fail(at, InvalidRankingField(name))
  }
}

///|
pub fn check_text_rank(
  source : @decode.Cursor,
  corpus : @carrier.Carrier,
  queries : @carrier.Carrier,
  limits : @checking.Limits,
  profile? : @text_rank_profile.Profile? = None,
) -> Result[CheckedTextRank, @checking.Issue] {
  let options = match read_text_rank_options(source, limits) {
    Ok(o) => o
    Err(e) => return Err(e)
  }
  let u = options.usage
  match
    check_text_rank_inputs(
      options,
      corpus,
      queries,
      {
        max_work: limits.max_work - u.work,
        max_nodes: limits.max_nodes - u.nodes,
        max_text_bytes: limits.max_text_bytes - u.text_bytes,
        max_depth: limits.max_depth,
      },
      profile~,
    ) {
    Err(e) => Err(e)
    Ok(c) =>
      Ok({
        ..c,
        usage: {
          work: u.work + c.usage.work,
          nodes: u.nodes + c.usage.nodes,
          text_bytes: u.text_bytes + c.usage.text_bytes,
        },
      })
  }
}

///|
/// Reuses admitted options without repeating their source traversal.
pub fn check_text_rank_inputs(
  options : TextRankOptions,
  corpus : @carrier.Carrier,
  queries : @carrier.Carrier,
  limits : @checking.Limits,
  profile? : @text_rank_profile.Profile? = None,
) -> Result[CheckedTextRank, @checking.Issue] {
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
    let root = @checking.decoded(@decode.open_object(source))
    let candidate = text_role(
      b,
      root,
      corpus,
      "candidate_id",
      options.corpus.identity,
    )
    ignore(text_role(b, root, corpus, "candidate_text", options.corpus.text))
    let query = text_role(
      b,
      root,
      queries,
      "query_id",
      options.query_roles.identity,
    )
    ignore(text_role(b, root, queries, "query_text", options.query_roles.text))
    @checking.spend(b, source, 4)
    if b.nodes == 0 {
      @checking.fail(source, BudgetExceeded)
    }
    b.nodes -= 1
    let number = @contract.primitive(NumberType, nullable=false)
    let fields : Array[(@row.FieldName, @contract.Contract?)] = []
    for
      (name, c) in [
        ("query_id", query),
        ("candidate_id", candidate),
        ("score", number),
        ("rank", number),
      ] {
      @checking.charge(b, source, name)
      fields.push((@row.Unqualified(name), Some(c)))
    }
    let output = match
      @carrier.rows(
        fields,
        field_set=Closed,
        max_fields=4,
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(r) => @carrier.relation(r)
      Err(_) => @checking.fail(source, BudgetExceeded)
    }
    Ok({
      profile,
      options,
      corpus,
      queries,
      output,
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
pub fn text_rank_source(o : TextRankOptions) -> @decode.Cursor {
  o.source
}

///|
pub fn text_rank_queries(o : TextRankOptions) -> String {
  o.queries
}

///|
pub fn text_rank_roles(
  o : TextRankOptions,
  side : TextRankSide,
) -> TextRankRoles {
  match side {
    Corpus => o.corpus
    Queries => o.query_roles
  }
}

///|
pub fn text_rank_tokenizer(o : TextRankOptions) -> Tokenizer {
  o.tokenizer
}

///|
pub fn text_rank_bm25(o : TextRankOptions) -> (Double, Double) {
  (o.k1, o.length_normalization)
}

///|
pub fn text_rank_k(o : TextRankOptions) -> Double {
  o.k
}

///|
pub fn text_rank_options_usage(o : TextRankOptions) -> @checking.Usage {
  o.usage
}

///|
pub fn text_rank_options(c : CheckedTextRank) -> TextRankOptions {
  c.options
}

///|
pub fn text_rank_output(c : CheckedTextRank) -> @carrier.Carrier {
  c.output
}

///|
pub fn text_rank_input(
  c : CheckedTextRank,
  side : TextRankSide,
) -> @carrier.Carrier {
  match side {
    Corpus => c.corpus
    Queries => c.queries
  }
}

///|
pub fn text_rank_usage(c : CheckedTextRank) -> @checking.Usage {
  c.usage
}

///|
pub fn text_rank_profile(c : CheckedTextRank) -> @text_rank_profile.Profile? {
  c.profile
}

///|
pub fn text_rank_pending(c : CheckedTextRank) -> Array[TextRankObligation] {
  let obligations = [
    ValidateCompleteTextInputs,
    ValidateGlobalStringIdentities(Corpus),
    ValidateGlobalStringIdentities(Queries),
    NormalizeAndTokenizeWithPinnedUnicode,
    ResolveTokenizerAndNormalizedTextCeilings,
    ComputeStatisticsFromAdmittedCorpusOnly,
    EvaluatePinnedBm25AndCorrectlyRoundedLogarithm,
    FoldTermsInCanonicalOrder,
    RejectNonFiniteTextScores,
    ExcludeZeroScoresAndHandleEmptyInputs,
    OrderTextScoresAndSemanticIdentities,
    AssignContiguousTextRanks,
    ResolveStatisticsScoringAndOutputResources,
  ]
  if c.profile is None {
    obligations.push(ResolveTextRankProfile)
  }
  obligations
}
