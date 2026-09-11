///|
pub(all) struct LikePatternLimits {
  max_work : Int
  max_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum LikePatternIssue {
  InvalidLimits
  BudgetExceeded
  InvalidSite(Int)
  MissingBindings(Int)
  InvalidPatternValue(Int)
  TrailingEscape(Int, Int)
} derive(Eq, Debug)

///|
pub(all) struct LikePatternUsage {
  work : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
struct LikePatternResolution {
  site : ExpressionValidationSite
  source : String
  parameter : @parameter.BoundParameter?
}

///|
struct LikePatternChecks {
  context : ExpressionValidationContext
  entries : Array[LikePatternResolution]
  usage : LikePatternUsage
}

///|
priv suberror LikeStop {
  LikeStop(LikePatternIssue)
}

///|
priv struct LikeBudget {
  mut work : Int
}

///|
fn like_spend(b : LikeBudget, n : Int) -> Unit raise LikeStop {
  if n > b.work {
    raise LikeStop(BudgetExceeded)
  }
  b.work -= n
}

///|
fn like_parameter(
  site : ExpressionValidationSite,
  name : String,
  i : Int,
  b : LikeBudget,
) -> (String, @parameter.BoundParameter?) raise LikeStop {
  let bound = match validation_site_parameters(site).bound {
    Some(v) => v
    None => raise LikeStop(MissingBindings(i))
  }
  let values = @references.bound_values(bound)
  let mut lo = 0
  let mut hi = @parameter.bound_value_count(values)
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let entry = @parameter.bound_value_at(values, mid).unwrap()
    like_spend(b, 1)
    like_spend(b, name.length())
    like_spend(b, entry.name.length())
    let order = name.compare(entry.name)
    if order < 0 {
      hi = mid
    } else if order > 0 {
      lo = mid + 1
    } else {
      match entry.value.value {
        @value.Text(v) => return (v, Some(entry))
        _ => raise LikeStop(InvalidPatternValue(i))
      }
    }
  }
  raise LikeStop(MissingBindings(i))
}

///|
/// Validate bound LIKE syntax without executing a matcher or requiring a
/// text-time policy. Preserve the exact source and its owning binding visit.
pub fn check_like_patterns(
  context : ExpressionValidationContext,
  limits : LikePatternLimits,
) -> Result[LikePatternChecks, LikePatternIssue] {
  if limits.max_work < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let before = expression_validation_usage(context)
  if before.work > limits.max_work || before.text_bytes > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let b : LikeBudget = { work: limits.max_work - before.work, }
  let mut text_bytes = before.text_bytes
  let entries : Array[LikePatternResolution] = []
  try {
    for i in 0..<expression_validation_count(context) {
      like_spend(b, 1)
      let site = expression_validation_at(context, i).unwrap()
      let requirement = validation_site_requirement(site)
      if !(requirement.obligation.kind is PatternValidation("like")) {
        continue
      }
      let expression = requirement.expression
      let node = requirement.obligation.node_index
      if !(@typing.node_form(expression, node)
        is Some(@typing.Expression("like", _))) {
        raise LikeStop(InvalidSite(i))
      }
      let child = match @typing.child_at(expression, node, 1) {
        Some(v) => v
        None => raise LikeStop(InvalidSite(i))
      }
      like_spend(b, 1)
      let (source, parameter) = match @typing.node_form(expression, child) {
        Some(@typing.Expression("literal", body)) =>
          match @decode.text(body) {
            Ok(v) => (v, None)
            Err(_) => raise LikeStop(InvalidPatternValue(i))
          }
        Some(@typing.Expression("$param", body)) => {
          let name = match @decode.text(body) {
            Ok(v) => v
            Err(_) => raise LikeStop(InvalidSite(i))
          }
          like_parameter(site, name, i, b)
        }
        _ => raise LikeStop(InvalidSite(i))
      }
      // Owned literal/bound strings are already well-formed and NFC/LF.
      // Precharge each scan before traversing a potentially large string.
      like_spend(b, source.length())
      let bytes = match
        @scalar.admit_utf8_length(source, limits.max_text_bytes - text_bytes) {
        Ok(v) => v
        Err(_) => raise LikeStop(BudgetExceeded)
      }
      text_bytes += bytes
      like_spend(b, source.length())
      let mut escape = false
      for offset in 0..<source.length() {
        if escape {
          escape = false
        } else if source.code_unit_at(offset).to_int() == 92 {
          escape = true
        }
      }
      // Only the parity of a final ASCII backslash run is needed. Scanning
      // code units does not split or reinterpret escaped supplementary scalars.
      if escape {
        raise LikeStop(TrailingEscape(i, source.length() - 1))
      }
      entries.push({ site, source, parameter, })
    }
    Ok({
      context,
      entries,
      usage: { work: limits.max_work - b.work, text_bytes, },
    })
  } catch {
    LikeStop(e) => Err(e)
  }
}

///|
pub fn like_pattern_context(
  v : LikePatternChecks,
) -> ExpressionValidationContext {
  v.context
}

///|
pub fn like_pattern_count(v : LikePatternChecks) -> Int {
  v.entries.length()
}

///|
pub fn like_pattern_at(
  v : LikePatternChecks,
  i : Int,
) -> LikePatternResolution? {
  v.entries.get(i)
}

///|
pub fn like_pattern_usage(v : LikePatternChecks) -> LikePatternUsage {
  v.usage
}

///|
pub fn like_pattern_site(v : LikePatternResolution) -> ExpressionValidationSite {
  v.site
}

///|
pub fn like_pattern_source(v : LikePatternResolution) -> String {
  v.source
}

///|
pub fn like_pattern_parameter(
  v : LikePatternResolution,
) -> @parameter.BoundParameter? {
  v.parameter
}
