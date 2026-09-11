///|
pub(all) struct TimestampPatternLimits {
  max_work : Int
  max_text_bytes : Int
  max_ast_bytes : Int
  max_ast_nodes : Int
} derive(Eq, Debug)

///|
pub(all) enum TimestampPatternIssue {
  InvalidLimits
  BudgetExceeded
  MissingPolicy(Int)
  MissingBindings(Int)
  InvalidSite(Int)
  InvalidPatternValue(Int)
  PatternCeiling(Int)
  Pattern(Int, @timestamp.Issue)
} derive(Eq, Debug)

///|
pub(all) struct TimestampPatternUsage {
  work : Int
  text_bytes : Int
  ast_bytes : Int
  ast_nodes : Int
} derive(Eq, Debug)

///|
struct TimestampPatternResolution {
  site : ExpressionValidationSite
  pattern : @timestamp.Pattern
  parameter : @parameter.BoundParameter?
  policy : @environment.TextTime
}

///|
struct TimestampPatternChecks {
  context : ExpressionValidationContext
  entries : Array[TimestampPatternResolution]
  usage : TimestampPatternUsage
}

///|
priv struct TimestampBudget {
  mut work : Int
}

///|
priv suberror TimestampStop {
  TimestampStop(TimestampPatternIssue)
}

///|
fn timestamp_spend(
  budget : TimestampBudget,
  count : Int,
) -> Unit raise TimestampStop {
  if count > budget.work {
    raise TimestampStop(BudgetExceeded)
  }
  budget.work -= count
}

///|
fn[T] timestamp_decoded(
  value : Result[T, @decode.Issue],
  index : Int,
) -> T raise TimestampStop {
  match value {
    Ok(v) => v
    Err(_) => raise TimestampStop(InvalidSite(index))
  }
}

///|
fn timestamp_argument(
  site : ExpressionValidationSite,
  operation : String,
  index : Int,
  budget : TimestampBudget,
) -> (String, @parameter.BoundParameter?) raise TimestampStop {
  timestamp_spend(budget, 1)
  let requirement = validation_site_requirement(site)
  let body = match
    @typing.node_form(requirement.expression, requirement.obligation.node_index) {
    Some(@typing.Expression(tag, body)) if tag == operation => body
    _ => raise TimestampStop(InvalidSite(index))
  }
  let body = timestamp_decoded(@decode.open_object(body), index)
  let argument = timestamp_decoded(@decode.required(body, "pattern"), index)
  let argument = timestamp_decoded(@decode.open_object(argument), index)
  if @decode.lookup(argument, "literal") is Some(literal) {
    return (timestamp_decoded(@decode.text(literal), index), None)
  }
  let name = timestamp_decoded(
    @decode.text(timestamp_decoded(@decode.required(argument, "$param"), index)),
    index,
  )
  let bound = match validation_site_parameters(site).bound {
    Some(v) => v
    None => raise TimestampStop(MissingBindings(index))
  }
  let values = @references.bound_values(bound)
  // BoundValues retains declaration order, sorted by UTF-16. Parameter names
  // are ASCII, so String comparison agrees with the canonical ordering here.
  let mut low = 0
  let mut high = @parameter.bound_value_count(values)
  while low < high {
    let mid = low + (high - low) / 2
    let entry = @parameter.bound_value_at(values, mid).unwrap()
    timestamp_spend(budget, 1)
    timestamp_spend(budget, name.length())
    timestamp_spend(budget, entry.name.length())
    let order = name.compare(entry.name)
    if order < 0 {
      high = mid
    } else if order > 0 {
      low = mid + 1
    } else {
      match entry.value.value {
        @value.Text(text) => return (text, Some(entry))
        _ => raise TimestampStop(InvalidPatternValue(index))
      }
    }
  }
  raise TimestampStop(MissingBindings(index))
}

///|
/// Resolve all timestamp-pattern obligations from the owned inventory, including
/// unused branches and repeated producer occurrences. Other kinds stay pending.
pub fn check_timestamp_patterns(
  context : ExpressionValidationContext,
  limits : TimestampPatternLimits,
) -> Result[TimestampPatternChecks, TimestampPatternIssue] {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_ast_bytes < 0 ||
    limits.max_ast_nodes < 0 {
    return Err(InvalidLimits)
  }
  let before = context.usage
  if before.work > limits.max_work || before.text_bytes > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let budget : TimestampBudget = { work: limits.max_work - before.work, }
  let mut text = before.text_bytes
  let mut ast_bytes = 0
  let mut ast_nodes = 0
  let entries : Array[TimestampPatternResolution] = []
  try {
    for i in 0..<expression_validation_count(context) {
      timestamp_spend(budget, 1)
      let site = expression_validation_at(context, i).unwrap()
      let operation = match validation_site_requirement(site).obligation.kind {
        PatternValidation(op) if op == "parse_timestamp" ||
          op == "try_timestamp" ||
          op == "format_timestamp" => op
        _ => continue
      }
      let policy = match context.text_time {
        Some(v) => v
        None => raise TimestampStop(MissingPolicy(i))
      }
      let (source, parameter) = timestamp_argument(site, operation, i, budget)
      let ceiling = @text_policy.ceiling_value(
        @text_policy.ceiling(
          @environment.text_time_policy(policy),
          "max_pattern_bytes",
        ).unwrap(),
      )
      // Every accepted pattern is ASCII. Reject oversize text before allocation;
      // non-ASCII cannot become a successful pattern or bypass this ceiling.
      if source.length().to_int64() > ceiling {
        raise TimestampStop(PatternCeiling(i))
      }
      if source.length() > limits.max_text_bytes - text {
        raise TimestampStop(BudgetExceeded)
      }
      timestamp_spend(budget, source.length())
      let pattern = match
        @timestamp.parse(
          source,
          if operation == "format_timestamp" {
            @timestamp.Format
          } else {
            @timestamp.Parse
          },
          {
            max_pattern_bytes: source.length(),
            max_components: budget.work,
            max_ast_bytes: limits.max_ast_bytes - ast_bytes,
            max_ast_nodes: Int::min(
              limits.max_ast_nodes - ast_nodes,
              budget.work,
            ),
          },
        ) {
        Ok(v) => v
        Err(@timestamp.BudgetExceeded) => raise TimestampStop(BudgetExceeded)
        Err(e) => raise TimestampStop(Pattern(i, e))
      }
      let (bytes, _, output_bytes, nodes) = @timestamp.usage(pattern)
      timestamp_spend(budget, nodes)
      text += bytes
      ast_bytes += output_bytes
      ast_nodes += nodes
      entries.push({ site, pattern, parameter, policy, })
    }
    Ok({
      context,
      entries,
      usage: {
        work: limits.max_work - budget.work,
        text_bytes: text,
        ast_bytes,
        ast_nodes,
      },
    })
  } catch {
    TimestampStop(e) => Err(e)
  }
}

///|
pub fn timestamp_pattern_context(
  v : TimestampPatternChecks,
) -> ExpressionValidationContext {
  v.context
}

///|
pub fn timestamp_pattern_count(v : TimestampPatternChecks) -> Int {
  v.entries.length()
}

///|
pub fn timestamp_pattern_at(
  v : TimestampPatternChecks,
  index : Int,
) -> TimestampPatternResolution? {
  v.entries.get(index)
}

///|
pub fn timestamp_pattern_usage(
  v : TimestampPatternChecks,
) -> TimestampPatternUsage {
  v.usage
}

///|
pub fn timestamp_pattern_site(
  v : TimestampPatternResolution,
) -> ExpressionValidationSite {
  v.site
}

///|
pub fn timestamp_pattern_ast(
  v : TimestampPatternResolution,
) -> @timestamp.Pattern {
  v.pattern
}

///|
pub fn timestamp_pattern_parameter(
  v : TimestampPatternResolution,
) -> @parameter.BoundParameter? {
  v.parameter
}

///|
pub fn timestamp_pattern_policy(
  v : TimestampPatternResolution,
) -> @environment.TextTime {
  v.policy
}
