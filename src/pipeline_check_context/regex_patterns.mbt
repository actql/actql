///|
pub(all) struct RegexPatternLimits {
  max_work : Int
  max_text_bytes : Int
  max_ast_bytes : Int
  max_ast_nodes : Int
  max_pattern_depth : Int
} derive(Eq, Debug)

///|
pub(all) enum RegexPatternIssue {
  InvalidLimits
  BudgetExceeded
  MissingPolicy(Int)
  MissingBindings(Int)
  InvalidSite(Int)
  InvalidArgument(Int, String)
  PatternCeiling(Int)
  UnknownCapture(Int)
  Pattern(Int, @regex.Issue)
  Replacement(Int, @replacement.Issue)
} derive(Eq, Debug)

///|
pub(all) enum RegexOperation {
  Match
  Extract(Int)
  Replace(@replacement.Replacement)
}

///|
pub(all) struct RegexPatternUsage {
  work : Int
  text_bytes : Int
  ast_bytes : Int
  ast_nodes : Int
} derive(Eq, Debug)

///|
struct RegexPatternResolution {
  site : ExpressionValidationSite
  pattern : @regex.Pattern
  operation : RegexOperation
  flags : String?
  pattern_parameter : @parameter.BoundParameter?
  option_parameter : @parameter.BoundParameter?
  policy : @environment.TextTime
}

///|
struct RegexPatternChecks {
  context : ExpressionValidationContext
  entries : Array[RegexPatternResolution]
  usage : RegexPatternUsage
}

///|
priv struct RegexBudget {
  mut work : Int
}

///|
priv suberror RegexStop {
  RegexStop(RegexPatternIssue)
}

///|
fn regex_spend(b : RegexBudget, n : Int) -> Unit raise RegexStop {
  if n > b.work {
    raise RegexStop(BudgetExceeded)
  }
  b.work -= n
}

///|
fn[T] regex_decoded(v : Result[T, @decode.Issue], i : Int) -> T raise RegexStop {
  match v {
    Ok(v) => v
    Err(_) => raise RegexStop(InvalidSite(i))
  }
}

///|
priv enum StaticRegexValue {
  Text(String)
  Number(Double)
}

///|
fn regex_argument(
  site : ExpressionValidationSite,
  body : @decode.ObjectView,
  name : String,
  i : Int,
  b : RegexBudget,
) -> (StaticRegexValue, @parameter.BoundParameter?) raise RegexStop {
  regex_spend(b, 1)
  let source = regex_decoded(@decode.required(body, name), i)
  let source = regex_decoded(@decode.open_object(source), i)
  if @decode.lookup(source, "literal") is Some(v) {
    let value = match @decode.view(v) {
      TextValue(v) => Text(v)
      NumberValue(v) => Number(v)
      _ => raise RegexStop(InvalidArgument(i, name))
    }
    return (value, None)
  }
  let parameter = regex_decoded(
    @decode.text(regex_decoded(@decode.required(source, "$param"), i)),
    i,
  )
  let index = match validation_site_parameters(site).bound {
    Some(v) => v
    None => raise RegexStop(MissingBindings(i))
  }
  let values = @references.bound_values(index)
  let mut lo = 0
  let mut hi = @parameter.bound_value_count(values)
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let entry = @parameter.bound_value_at(values, mid).unwrap()
    regex_spend(b, 1)
    regex_spend(b, parameter.length())
    regex_spend(b, entry.name.length())
    // Admitted Parameter names are ASCII and BoundValues is name-sorted.
    let order = parameter.compare(entry.name)
    if order < 0 {
      hi = mid
    } else if order > 0 {
      lo = mid + 1
    } else {
      let value = match entry.value.value {
        @value.Text(v) => Text(v)
        @value.Number(v) => Number(v)
        _ => raise RegexStop(InvalidArgument(i, name))
      }
      return (value, Some(entry))
    }
  }
  raise RegexStop(MissingBindings(i))
}

///|
fn regex_text(
  value : StaticRegexValue,
  i : Int,
  name : String,
) -> String raise RegexStop {
  match value {
    Text(v) => v
    _ => raise RegexStop(InvalidArgument(i, name))
  }
}

///|
/// Admit patterns and static regex options from the same owned expression visit.
/// Profile and output-envelope obligations remain pending in the retained context.
pub fn check_regex_patterns(
  context : ExpressionValidationContext,
  limits : RegexPatternLimits,
) -> Result[RegexPatternChecks, RegexPatternIssue] {
  if limits.max_work < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_ast_bytes < 0 ||
    limits.max_ast_nodes < 0 ||
    limits.max_pattern_depth < 0 ||
    limits.max_pattern_depth > 1073741822 {
    return Err(InvalidLimits)
  }
  let before = context.usage
  if before.work > limits.max_work || before.text_bytes > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let b : RegexBudget = { work: limits.max_work - before.work, }
  let mut text = before.text_bytes
  let mut ast_bytes = 0
  let mut ast_nodes = 0
  let entries : Array[RegexPatternResolution] = []
  try {
    for i in 0..<expression_validation_count(context) {
      regex_spend(b, 1)
      let site = expression_validation_at(context, i).unwrap()
      let requirement = validation_site_requirement(site)
      let op = match requirement.obligation.kind {
        PatternValidation(op) if op == "regex_match" ||
          op == "regex_extract" ||
          op == "regex_replace" => op
        _ => continue
      }
      let policy = match context.text_time {
        Some(v) => v
        None => raise RegexStop(MissingPolicy(i))
      }
      let node = @typing.node_at(
        requirement.expression,
        requirement.obligation.node_index,
      ).unwrap()
      let object = regex_decoded(@decode.open_object(node.source), i)
      let body = regex_decoded(
        @decode.open_object(regex_decoded(@decode.required(object, op), i)),
        i,
      )
      let flags = match @decode.lookup(body, "flags") {
        None => None
        Some(v) => {
          let flags = regex_decoded(@decode.text(v), i)
          regex_spend(b, flags.length())
          // Retain authored order and absent versus empty; typing has checked the set.
          if !["", "m", "s", "ms", "sm"].contains(flags) {
            raise RegexStop(InvalidArgument(i, "flags"))
          }
          if flags.length() > limits.max_text_bytes - text {
            raise RegexStop(BudgetExceeded)
          }
          text += flags.length()
          Some(flags)
        }
      }
      let (value, pattern_parameter) = regex_argument(
        site, body, "pattern", i, b,
      )
      let source = regex_text(value, i, "pattern")
      regex_spend(b, source.length())
      let ceiling = @text_policy.ceiling_value(
        @text_policy.ceiling(
          @environment.text_time_policy(policy),
          "max_pattern_bytes",
        ).unwrap(),
      )
      let bytes = match @scalar.admit_utf8_length64(source, ceiling) {
        Ok(n) => n
        Err(_) => raise RegexStop(PatternCeiling(i))
      }
      if bytes > (limits.max_text_bytes - text).to_int64() {
        raise RegexStop(BudgetExceeded)
      }
      let bytes = bytes.to_int()
      regex_spend(b, bytes)
      let pattern = match
        @regex.parse(source, {
          max_input_bytes: bytes,
          max_nodes: b.work,
          max_depth: limits.max_pattern_depth,
          max_ast_bytes: limits.max_ast_bytes - ast_bytes,
          max_ast_nodes: Int::min(limits.max_ast_nodes - ast_nodes, b.work),
        }) {
        Ok(v) => v
        Err(@regex.BudgetExceeded) => raise RegexStop(BudgetExceeded)
        Err(e) => raise RegexStop(Pattern(i, e))
      }
      let (_, out, nodes) = @regex.usage(pattern)
      regex_spend(b, nodes)
      text += bytes
      ast_bytes += out
      ast_nodes += nodes
      let (operation, option_parameter) = if op == "regex_extract" {
        let (value, parameter) = regex_argument(site, body, "capture", i, b)
        let n = match value {
          Number(n) => n
          _ => raise RegexStop(InvalidArgument(i, "capture"))
        }
        if @scalar.read_integer_number(n) is None || n < 0.0 {
          raise RegexStop(InvalidArgument(i, "capture"))
        }
        if n > @regex.capture_count(pattern).to_double() {
          raise RegexStop(UnknownCapture(i))
        }
        (RegexOperation::Extract(n.to_int()), parameter)
      } else if op == "regex_replace" {
        let (value, parameter) = regex_argument(site, body, "replacement", i, b)
        let source = regex_text(value, i, "replacement")
        regex_spend(b, source.length())
        let bytes = match
          @scalar.admit_utf8_length(source, limits.max_text_bytes - text) {
          Ok(n) => n
          Err(_) => raise RegexStop(BudgetExceeded)
        }
        regex_spend(b, bytes)
        let replacement = match
          @replacement.parse(source, {
            max_input_bytes: bytes,
            max_parts: b.work,
            max_ast_bytes: limits.max_ast_bytes - ast_bytes,
            max_ast_nodes: Int::min(limits.max_ast_nodes - ast_nodes, b.work),
          }) {
          Ok(v) => v
          Err(@replacement.BudgetExceeded) => raise RegexStop(BudgetExceeded)
          Err(e) => raise RegexStop(Replacement(i, e))
        }
        if @replacement.stats(replacement).max_capture_index >
          @regex.capture_count(pattern) {
          raise RegexStop(UnknownCapture(i))
        }
        let (_, out, nodes) = @replacement.usage(replacement)
        regex_spend(b, nodes)
        text += bytes
        ast_bytes += out
        ast_nodes += nodes
        (RegexOperation::Replace(replacement), parameter)
      } else {
        (RegexOperation::Match, None)
      }
      entries.push({
        site,
        pattern,
        operation,
        flags,
        pattern_parameter,
        option_parameter,
        policy,
      })
    }
    Ok({
      context,
      entries,
      usage: {
        work: limits.max_work - b.work,
        text_bytes: text,
        ast_bytes,
        ast_nodes,
      },
    })
  } catch {
    RegexStop(e) => Err(e)
  }
}

///|
pub fn regex_pattern_context(
  v : RegexPatternChecks,
) -> ExpressionValidationContext {
  v.context
}

///|
pub fn regex_pattern_count(v : RegexPatternChecks) -> Int {
  v.entries.length()
}

///|
pub fn regex_pattern_at(
  v : RegexPatternChecks,
  i : Int,
) -> RegexPatternResolution? {
  v.entries.get(i)
}

///|
pub fn regex_pattern_usage(v : RegexPatternChecks) -> RegexPatternUsage {
  v.usage
}

///|
pub fn regex_pattern_site(
  v : RegexPatternResolution,
) -> ExpressionValidationSite {
  v.site
}

///|
pub fn regex_pattern_ast(v : RegexPatternResolution) -> @regex.Pattern {
  v.pattern
}

///|
pub fn regex_pattern_operation(v : RegexPatternResolution) -> RegexOperation {
  v.operation
}

///|
pub fn regex_pattern_flags(v : RegexPatternResolution) -> String? {
  v.flags
}

///|
pub fn regex_pattern_parameter(
  v : RegexPatternResolution,
) -> @parameter.BoundParameter? {
  v.pattern_parameter
}

///|
pub fn regex_option_parameter(
  v : RegexPatternResolution,
) -> @parameter.BoundParameter? {
  v.option_parameter
}

///|
pub fn regex_pattern_policy(
  v : RegexPatternResolution,
) -> @environment.TextTime {
  v.policy
}
