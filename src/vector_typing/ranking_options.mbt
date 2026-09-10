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
  usage : Usage
}

///|
fn ranking_positive(at : @decode.Cursor) -> Double raise Stop {
  let n = decoded(@decode.safe_integer(at))
  if n <= 0 {
    fail(at, InvalidBody)
  }
  n.to_double()
}

///|
fn ranking_nonnegative(at : @decode.Cursor) -> Double raise Stop {
  let n = decoded(@decode.finite_number(at))
  if n < 0 || (n == 0 && 1.0 / n < 0) {
    fail(at, InvalidBody)
  }
  n
}

///|
fn ranking_names(
  b : Budget,
  at : @decode.Cursor,
) -> Array[@row.FieldName] raise Stop {
  let items = decoded(@decode.elements(at))
  spend(b, at, items.length())
  items.map(item => role_name(item))
}

///|
fn ranking_input_name(at : @decode.Cursor) -> String raise Stop {
  let name = decoded(@decode.text(at))
  if name.is_empty() {
    fail(at, InvalidBody)
  }
  name
}

///|
fn read_score_contract(at : @decode.Cursor) -> ScoreContract raise Stop {
  let root = decoded(
    @decode.closed_object(at, [
      "domain", "range", "normalization", "higher_is_better",
    ]),
  )
  let domain = ranking_input_name(decoded(@decode.required(root, "domain")))
  let normalization = ranking_input_name(
    decoded(@decode.required(root, "normalization")),
  )
  if @decode.lookup(root, "higher_is_better") is Some(at) {
    if !decoded(@decode.boolean(at)) {
      fail(at, InvalidBody)
    }
  }
  let range_at = decoded(@decode.required(root, "range"))
  let items = decoded(@decode.elements(range_at))
  if items.length() != 2 {
    fail(range_at, InvalidBody)
  }
  let minimum = decoded(@decode.finite_number(items[0]))
  let maximum = decoded(@decode.finite_number(items[1]))
  if minimum > maximum {
    fail(range_at, InvalidBody)
  }
  { domain, normalization, minimum, maximum, }
}

///|
/// Reads policy-specific source options only; it does not certify ranking data
/// or establish that an authored score contract matches either input's evidence.
pub fn read_ranking_options(
  source : @decode.Cursor,
  limits : Limits,
) -> Result[RankingOptions, Issue] {
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
    let root = decoded(
      @decode.closed_object(source, [
        "with", "by", "candidate", "score", "rank", "score_policy", "score_contract",
        "k", "tie_break",
      ]),
    )
    let policy_at = decoded(@decode.required(root, "score_policy"))
    let weights = []
    let mut rank_constant = None
    let mut rank_window = None
    let policy = match @decode.view(policy_at) {
      TextValue("max") => Maximum
      _ => {
        let object = decoded(
          @decode.closed_object(policy_at, ["weighted_sum", "rrf"]),
        )
        if decoded(@decode.object_field_names(policy_at)).length() != 1 {
          fail(policy_at, InvalidBody)
        }
        match @decode.lookup(object, "weighted_sum") {
          Some(at) => {
            let weighted = decoded(@decode.closed_object(at, ["left", "right"]))
            let left = ranking_nonnegative(
              decoded(@decode.required(weighted, "left")),
            )
            let right = ranking_nonnegative(
              decoded(@decode.required(weighted, "right")),
            )
            if left + right != 1.0 {
              fail(at, InvalidBody)
            }
            weights.push(left)
            weights.push(right)
            WeightedSum
          }
          None => {
            let at = decoded(@decode.required(object, "rrf"))
            let rrf = decoded(
              @decode.closed_object(at, [
                "rank_constant", "weights", "rank_window",
              ]),
            )
            rank_constant = Some(
              ranking_positive(decoded(@decode.required(rrf, "rank_constant"))),
            )
            rank_window = Some(
              ranking_positive(decoded(@decode.required(rrf, "rank_window"))),
            )
            let weights_at = decoded(@decode.required(rrf, "weights"))
            let items = decoded(@decode.elements(weights_at))
            spend(b, weights_at, items.length())
            let mut positive = false
            for item in items {
              let weight = ranking_nonnegative(item)
              if weight > 0 {
                positive = true
              }
              weights.push(weight)
            }
            if !positive {
              fail(weights_at, InvalidBody)
            }
            ReciprocalRank
          }
        }
      }
    }
    let with_at = decoded(@decode.required(root, "with"))
    let others = match @decode.view(with_at) {
      ArrayValue(items) if policy == ReciprocalRank => {
        if items.is_empty() {
          fail(with_at, InvalidBody)
        }
        spend(b, with_at, items.length())
        items.map(at => ranking_input_name(at))
      }
      _ => [ranking_input_name(with_at)]
    }
    if policy == ReciprocalRank && weights.length() - 1 != others.length() {
      fail(decoded(@decode.required(root, "score_policy")), InvalidBody)
    }
    let by = ranking_names(b, decoded(@decode.required(root, "by")))
    let candidate = role_name(decoded(@decode.required(root, "candidate")))
    let k = ranking_positive(decoded(@decode.required(root, "k")))
    let mut score = None
    let mut rank = None
    let mut contract = None
    let mut tie_break = None
    if policy == ReciprocalRank {
      for name in ["score", "score_contract", "tie_break"] {
        if @decode.lookup(root, name) is Some(at) {
          fail(at, InvalidBody)
        }
      }
      rank = Some(role_name(decoded(@decode.required(root, "rank"))))
    } else {
      if @decode.lookup(root, "rank") is Some(at) {
        fail(at, InvalidBody)
      }
      score = Some(role_name(decoded(@decode.required(root, "score"))))
      contract = Some(
        read_score_contract(decoded(@decode.required(root, "score_contract"))),
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
    Stop(e) => Err(e)
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
pub fn ranking_options_usage(o : RankingOptions) -> Usage {
  o.usage
}
