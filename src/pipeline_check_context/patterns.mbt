///|
pub(all) struct PatternLimits {
  max_work : Int
  max_text_bytes : Int
  max_ast_bytes : Int
  max_ast_nodes : Int
  max_regex_depth : Int
} derive(Eq, Debug)

///|
pub(all) enum PatternIssue {
  InvalidLimits
  BudgetExceeded
  UnsupportedPattern(Int, String)
  Timestamp(TimestampPatternIssue)
  Regex(RegexPatternIssue)
  Like(LikePatternIssue)
} derive(Eq, Debug)

///|
pub(all) struct PatternUsage {
  work : Int
  text_bytes : Int
  ast_bytes : Int
  ast_nodes : Int
} derive(Eq, Debug)

///|
/// A location in an owning PatternChecks collection, not an independently
/// attachable proof or a persistent identity.
pub(all) enum PatternResolution {
  Timestamp(TimestampPatternResolution)
  Regex(RegexPatternResolution)
  Like(LikePatternResolution)
}

///|
struct PatternChecks {
  context : ExpressionValidationContext
  entries : Array[PatternResolution]
  usage : PatternUsage
}

///|
/// Establish every PatternValidation obligation in one context. This does not
/// discharge profile admission or Host envelopes. Failure returns no prefix.
pub fn check_patterns(
  context : ExpressionValidationContext,
  limits : PatternLimits,
) -> Result[PatternChecks, PatternIssue] {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_ast_bytes < 0 ||
    limits.max_ast_nodes < 0 ||
    limits.max_regex_depth < 0 ||
    limits.max_regex_depth > 1073741822 {
    return Err(InvalidLimits)
  }
  let before = expression_validation_usage(context)
  if before.work > limits.max_work || before.text_bytes > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let count = expression_validation_count(context)
  // One inventory preflight and one ordered output pass. Sub-checkers account
  // for their own scans; all source/binding/AST work remains charged as before.
  if count > (limits.max_work - before.work) / 2 {
    return Err(BudgetExceeded)
  }
  let overhead = count * 2
  for i in 0..<count {
    let site = expression_validation_at(context, i).unwrap()
    match validation_site_requirement(site).obligation.kind {
      PatternValidation(op) =>
        if ![
            "parse_timestamp", "try_timestamp", "format_timestamp", "regex_match",
            "regex_extract", "regex_replace", "like",
          ].contains(op) {
          return Err(UnsupportedPattern(i, op))
        }
      _ => ()
    }
  }
  let timestamp = match
    check_timestamp_patterns(context, {
      max_work: limits.max_work - overhead,
      max_text_bytes: limits.max_text_bytes,
      max_ast_bytes: limits.max_ast_bytes,
      max_ast_nodes: limits.max_ast_nodes,
    }) {
    Ok(v) => v
    Err(TimestampPatternIssue::BudgetExceeded) => return Err(BudgetExceeded)
    Err(e) => return Err(Timestamp(e))
  }
  let t = timestamp_pattern_usage(timestamp)
  // Retain the base context charge exactly once. Only the first phase's
  // incremental cost reduces the second phase's effective cumulative caps.
  let regex = match
    check_regex_patterns(context, {
      max_work: limits.max_work - overhead - (t.work - before.work),
      max_text_bytes: limits.max_text_bytes - (t.text_bytes - before.text_bytes),
      max_ast_bytes: limits.max_ast_bytes - t.ast_bytes,
      max_ast_nodes: limits.max_ast_nodes - t.ast_nodes,
      max_pattern_depth: limits.max_regex_depth,
    }) {
    Ok(v) => v
    Err(RegexPatternIssue::BudgetExceeded) => return Err(BudgetExceeded)
    Err(e) => return Err(Regex(e))
  }
  let r = regex_pattern_usage(regex)
  let like = match
    check_like_patterns(context, {
      max_work: limits.max_work -
      overhead -
      (t.work - before.work) -
      (r.work - before.work),
      max_text_bytes: limits.max_text_bytes -
      (t.text_bytes - before.text_bytes) -
      (r.text_bytes - before.text_bytes),
    }) {
    Ok(v) => v
    Err(LikePatternIssue::BudgetExceeded) => return Err(BudgetExceeded)
    Err(e) => return Err(Like(e))
  }
  let l = like_pattern_usage(like)
  let entries : Array[PatternResolution] = []
  let mut ti = 0
  let mut ri = 0
  let mut li = 0
  for i in 0..<count {
    let site = expression_validation_at(context, i).unwrap()
    match validation_site_requirement(site).obligation.kind {
      PatternValidation(op) =>
        if ["parse_timestamp", "try_timestamp", "format_timestamp"].contains(op) {
          entries.push(Timestamp(timestamp_pattern_at(timestamp, ti).unwrap()))
          ti += 1
        } else if op == "like" {
          entries.push(Like(like_pattern_at(like, li).unwrap()))
          li += 1
        } else {
          entries.push(Regex(regex_pattern_at(regex, ri).unwrap()))
          ri += 1
        }
      _ => ()
    }
  }
  Ok({
    context,
    entries,
    usage: {
      work: t.work + (r.work - before.work) + (l.work - before.work) + overhead,
      text_bytes: t.text_bytes +
      (r.text_bytes - before.text_bytes) +
      (l.text_bytes - before.text_bytes),
      ast_bytes: t.ast_bytes + r.ast_bytes,
      ast_nodes: t.ast_nodes + r.ast_nodes,
    },
  })
}

///|
pub fn pattern_context(v : PatternChecks) -> ExpressionValidationContext {
  v.context
}

///|
pub fn pattern_count(v : PatternChecks) -> Int {
  v.entries.length()
}

///|
pub fn pattern_at(v : PatternChecks, i : Int) -> PatternResolution? {
  v.entries.get(i)
}

///|
pub fn pattern_usage(v : PatternChecks) -> PatternUsage {
  v.usage
}

///|
pub fn pattern_site(v : PatternResolution) -> ExpressionValidationSite {
  match v {
    Timestamp(v) => timestamp_pattern_site(v)
    Regex(v) => regex_pattern_site(v)
    Like(v) => like_pattern_site(v)
  }
}
