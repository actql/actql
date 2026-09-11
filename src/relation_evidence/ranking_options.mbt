///|
pub(all) enum RankingPolicy {
  Maximum
  WeightedSum
  ReciprocalRank
} derive(Eq, Debug)

///|
pub struct ScoreContract {
  domain : String
  normalization : String
  minimum : Double
  maximum : Double
}

///|
struct RankingOptions {
  source : @decode.Cursor
  others : Array[String]
  by : Array[@row.FieldName]
  candidate : @row.FieldName
  score : @row.FieldName?
  rank : @row.FieldName?
  policy : RankingPolicy
  weights : Array[Double]
  rank_constant : Double?
  rank_window : Double?
  contract : ScoreContract?
  tie_break : Array[@row.FieldName]?
  k : Double
  usage : @checking.Usage
}

///|
fn ranking_positive(at : @decode.Cursor) -> Double raise @checking.Stop {
  let n = @checking.decoded(@decode.safe_integer(at))
  if n <= 0 {
    @checking.fail(at, InvalidBody)
  }
  n.to_double()
}

///|
fn ranking_nonnegative(at : @decode.Cursor) -> Double raise @checking.Stop {
  let n = @checking.decoded(@decode.finite_number(at))
  if n < 0 || (n == 0 && 1.0 / n < 0) {
    @checking.fail(at, InvalidBody)
  }
  n
}

///|
fn ranking_names(
  b : @checking.Budget,
  at : @decode.Cursor,
) -> Array[@row.FieldName] raise @checking.Stop {
  let items = @checking.decoded(@decode.elements(at))
  @checking.spend(b, at, items.length())
  items.map(item => @checking.role_name(item))
}

///|
fn ranking_input_name(at : @decode.Cursor) -> String raise @checking.Stop {
  let name = @checking.decoded(@decode.text(at))
  if name.is_empty() {
    @checking.fail(at, InvalidBody)
  }
  name
}

///|
fn read_score_contract(
  at : @decode.Cursor,
) -> ScoreContract raise @checking.Stop {
  let root = @checking.decoded(
    @decode.closed_object(at, [
      "domain", "range", "normalization", "higher_is_better",
    ]),
  )
  let domain = ranking_input_name(
    @checking.decoded(@decode.required(root, "domain")),
  )
  let normalization = ranking_input_name(
    @checking.decoded(@decode.required(root, "normalization")),
  )
  if @decode.lookup(root, "higher_is_better") is Some(at) {
    if !@checking.decoded(@decode.boolean(at)) {
      @checking.fail(at, InvalidBody)
    }
  }
  let range_at = @checking.decoded(@decode.required(root, "range"))
  let items = @checking.decoded(@decode.elements(range_at))
  if items.length() != 2 {
    @checking.fail(range_at, InvalidBody)
  }
  let minimum = @checking.decoded(@decode.finite_number(items[0]))
  let maximum = @checking.decoded(@decode.finite_number(items[1]))
  if minimum > maximum {
    @checking.fail(range_at, InvalidBody)
  }
  { domain, normalization, minimum, maximum, }
}

///|
/// Reads policy-specific source options only; it does not certify ranking data
/// or establish that an authored score contract matches either input's evidence.
pub fn read_ranking_options(
  source : @decode.Cursor,
  limits : @checking.Limits,
) -> Result[RankingOptions, @checking.Issue] {
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
    let root = @checking.decoded(
      @decode.closed_object(source, [
        "with", "by", "candidate", "score", "rank", "score_policy", "score_contract",
        "k", "tie_break",
      ]),
    )
    let policy_at = @checking.decoded(@decode.required(root, "score_policy"))
    let weights = []
    let mut rank_constant = None
    let mut rank_window = None
    let policy = match @decode.view(policy_at) {
      TextValue("max") => Maximum
      _ => {
        let object = @checking.decoded(
          @decode.closed_object(policy_at, ["weighted_sum", "rrf"]),
        )
        if @checking.decoded(@decode.object_field_names(policy_at)).length() !=
          1 {
          @checking.fail(policy_at, InvalidBody)
        }
        match @decode.lookup(object, "weighted_sum") {
          Some(at) => {
            let weighted = @checking.decoded(
              @decode.closed_object(at, ["left", "right"]),
            )
            let left = ranking_nonnegative(
              @checking.decoded(@decode.required(weighted, "left")),
            )
            let right = ranking_nonnegative(
              @checking.decoded(@decode.required(weighted, "right")),
            )
            if left + right != 1.0 {
              @checking.fail(at, InvalidBody)
            }
            weights.push(left)
            weights.push(right)
            WeightedSum
          }
          None => {
            let at = @checking.decoded(@decode.required(object, "rrf"))
            let rrf = @checking.decoded(
              @decode.closed_object(at, [
                "rank_constant", "weights", "rank_window",
              ]),
            )
            rank_constant = Some(
              ranking_positive(
                @checking.decoded(@decode.required(rrf, "rank_constant")),
              ),
            )
            rank_window = Some(
              ranking_positive(
                @checking.decoded(@decode.required(rrf, "rank_window")),
              ),
            )
            let weights_at = @checking.decoded(@decode.required(rrf, "weights"))
            let items = @checking.decoded(@decode.elements(weights_at))
            @checking.spend(b, weights_at, items.length())
            let mut positive = false
            for item in items {
              let weight = ranking_nonnegative(item)
              if weight > 0 {
                positive = true
              }
              weights.push(weight)
            }
            if !positive {
              @checking.fail(weights_at, InvalidBody)
            }
            ReciprocalRank
          }
        }
      }
    }
    let with_at = @checking.decoded(@decode.required(root, "with"))
    let others = match @decode.view(with_at) {
      ArrayValue(items) if policy == ReciprocalRank => {
        if items.is_empty() {
          @checking.fail(with_at, InvalidBody)
        }
        @checking.spend(b, with_at, items.length())
        items.map(at => ranking_input_name(at))
      }
      _ => [ranking_input_name(with_at)]
    }
    if policy == ReciprocalRank && weights.length() - 1 != others.length() {
      @checking.fail(
        @checking.decoded(@decode.required(root, "score_policy")),
        InvalidBody,
      )
    }
    let by = ranking_names(b, @checking.decoded(@decode.required(root, "by")))
    let candidate = @checking.role_name(
      @checking.decoded(@decode.required(root, "candidate")),
    )
    let k = ranking_positive(@checking.decoded(@decode.required(root, "k")))
    let mut score = None
    let mut rank = None
    let mut contract = None
    let mut tie_break = None
    if policy == ReciprocalRank {
      for name in ["score", "score_contract", "tie_break"] {
        if @decode.lookup(root, name) is Some(at) {
          @checking.fail(at, InvalidBody)
        }
      }
      rank = Some(
        @checking.role_name(@checking.decoded(@decode.required(root, "rank"))),
      )
    } else {
      if @decode.lookup(root, "rank") is Some(at) {
        @checking.fail(at, InvalidBody)
      }
      score = Some(
        @checking.role_name(@checking.decoded(@decode.required(root, "score"))),
      )
      contract = Some(
        read_score_contract(
          @checking.decoded(@decode.required(root, "score_contract")),
        ),
      )
      if @decode.lookup(root, "tie_break") is Some(at) {
        tie_break = Some(ranking_names(b, at))
      }
    }
    Ok({
      source,
      others,
      by,
      candidate,
      score,
      rank,
      policy,
      weights,
      rank_constant,
      rank_window,
      contract,
      tie_break,
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
pub fn ranking_source(o : RankingOptions) -> @decode.Cursor {
  o.source
}

///|
pub fn ranking_inputs(o : RankingOptions) -> Array[String] {
  o.others.copy()
}

///|
pub fn ranking_by(o : RankingOptions) -> Array[@row.FieldName] {
  o.by.copy()
}

///|
/// Constant-time partition arity without copying field references.
pub fn ranking_by_count(o : RankingOptions) -> Int {
  o.by.length()
}

///|
pub fn ranking_candidate(o : RankingOptions) -> @row.FieldName {
  o.candidate
}

///|
pub fn ranking_score(o : RankingOptions) -> @row.FieldName? {
  o.score
}

///|
pub fn ranking_rank(o : RankingOptions) -> @row.FieldName? {
  o.rank
}

///|
pub fn ranking_policy(o : RankingOptions) -> RankingPolicy {
  o.policy
}

///|
pub fn ranking_weights(o : RankingOptions) -> Array[Double] {
  o.weights.copy()
}

///|
pub fn ranking_rank_constant(o : RankingOptions) -> Double? {
  o.rank_constant
}

///|
pub fn ranking_rank_window(o : RankingOptions) -> Double? {
  o.rank_window
}

///|
pub fn ranking_score_contract(o : RankingOptions) -> ScoreContract? {
  o.contract
}

///|
pub fn ranking_tie_break(o : RankingOptions) -> Array[@row.FieldName]? {
  o.tie_break.map(v => v.copy())
}

///|
pub fn ranking_k(o : RankingOptions) -> Double {
  o.k
}

///|
pub fn ranking_options_usage(o : RankingOptions) -> @checking.Usage {
  o.usage
}
