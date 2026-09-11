///|
pub(all) struct TextBoundsLimits {
  max_work : Int
  max_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum TextBoundsIssue {
  InvalidLimits
  BudgetExceeded
  MissingPolicy(Int)
  MissingBindings(Int)
  InvalidSite(Int)
  UnsupportedOperation(Int, String)
  Value(Int, @value.Issue)
  Bounds(Int, @bounds.Issue)
  Demand(Int, @typing.DemandIssue)
} derive(Eq, Debug)

///|
pub(all) struct TextBoundsUsage {
  work : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
struct TextBoundResolution {
  site : ExpressionValidationSite
  output : @bounds.Output
  input_parameter : @parameter.BoundParameter?
  length_parameter : @parameter.BoundParameter?
  policy : @environment.TextTime
  demands : @typing.DemandPaths
}

///|
struct TextBoundsChecks {
  patterns : PatternChecks
  entries : Array[TextBoundResolution]
  usage : TextBoundsUsage
}

///|
priv suberror TextBoundStop {
  TextBoundStop(TextBoundsIssue)
}

///|
priv struct TextBoundBudget {
  mut work : Int
  mut text : Int
}

///|
fn bound_spend(b : TextBoundBudget, n : Int) -> Unit raise TextBoundStop {
  if n > b.work {
    raise TextBoundStop(BudgetExceeded)
  }
  b.work -= n
}

///|
fn bound_parameter(
  site : ExpressionValidationSite,
  body : @decode.Cursor,
  index : Int,
  b : TextBoundBudget,
) -> @parameter.BoundParameter raise TextBoundStop {
  let name = match @decode.text(body) {
    Ok(v) => v
    Err(_) => raise TextBoundStop(InvalidSite(index))
  }
  let bound = match validation_site_parameters(site).bound {
    Some(v) => v
    None => raise TextBoundStop(MissingBindings(index))
  }
  let values = @references.bound_values(bound)
  let mut lo = 0
  let mut hi = @parameter.bound_value_count(values)
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let entry = @parameter.bound_value_at(values, mid).unwrap()
    bound_spend(b, 1)
    bound_spend(b, name.length())
    bound_spend(b, entry.name.length())
    let order = name.compare(entry.name)
    if order < 0 {
      hi = mid
    } else if order > 0 {
      lo = mid + 1
    } else {
      return entry
    }
  }
  raise TextBoundStop(MissingBindings(index))
}

///|
fn[T] bound_result(
  v : Result[T, @bounds.Issue],
  index : Int,
) -> T raise TextBoundStop {
  match v {
    Ok(v) => v
    Err(@bounds.BudgetExceeded) => raise TextBoundStop(BudgetExceeded)
    Err(e) => raise TextBoundStop(Bounds(index, e))
  }
}

///|
fn bound_value(
  value : @value.CheckedValue,
  policy : @text_policy.Policy,
  index : Int,
  b : TextBoundBudget,
) -> @bounds.Input raise TextBoundStop {
  let units = match value.value {
    @value.Text(v) | @value.Timestamp(v) => v.length()
    _ => 0
  }
  // from_value scans for UTF-8 length and scalar count, with a caller byte cap.
  bound_spend(b, units)
  bound_spend(b, units)
  let input = bound_result(
    @bounds.from_value(value, policy, max_text_bytes=b.text),
    index,
  )
  let (_, bytes) = @bounds.input_extent(input)
  b.text -= bytes.to_int()
  input
}

///|
fn bound_input(
  expression : @typing.TypedExpression,
  child : Int,
  outputs : Array[@bounds.Output?],
  site : ExpressionValidationSite,
  index : Int,
  policy : @text_policy.Policy,
  b : TextBoundBudget,
) -> (@bounds.Input, @parameter.BoundParameter?) raise TextBoundStop {
  if outputs[child] is Some(v) {
    return (bound_result(@bounds.from_output(v), index), None)
  }
  let contract = @typing.node_at(expression, child).unwrap().contract
  match @typing.node_form(expression, child) {
    Some(@typing.Expression("$param", body)) => {
      let parameter = bound_parameter(site, body, index, b)
      (bound_value(parameter.value, policy, index, b), Some(parameter))
    }
    Some(@typing.Expression("literal", body)) => {
      let units = match @decode.view(body) {
        TextValue(v) => v.length()
        _ => 0
      }
      // Scalar literal admission establishes a CheckedValue, not evaluation.
      bound_spend(b, 1)
      bound_spend(b, units)
      let value = match
        @value.admit(contract, body, {
          max_nodes: 1,
          max_depth: 0,
          max_text_bytes: b.text,
        }) {
        Ok(v) => v
        Err(@value.ValueIssue(@value.BudgetExceeded, ..)) =>
          raise TextBoundStop(BudgetExceeded)
        Err(e) => raise TextBoundStop(Value(index, e))
      }
      (bound_value(value, policy, index, b), None)
    }
    _ => (bound_result(@bounds.from_contract(contract, policy), index), None)
  }
}

///|
fn bound_length(
  expression : @typing.TypedExpression,
  node : Int,
  ordinal : Int,
  site : ExpressionValidationSite,
  index : Int,
  b : TextBoundBudget,
) -> (Double?, @parameter.BoundParameter?) raise TextBoundStop {
  let child = match @typing.child_at(expression, node, ordinal) {
    Some(v) => v
    None => raise TextBoundStop(InvalidSite(index))
  }
  bound_spend(b, 1)
  match @typing.node_form(expression, child) {
    Some(@typing.Expression("literal", body)) =>
      match @decode.view(body) {
        NumberValue(v) => (Some(v), None)
        _ => (None, None)
      }
    Some(@typing.Expression("$param", body)) => {
      let parameter = bound_parameter(site, body, index, b)
      let number = match parameter.value.value {
        @value.Number(v) => Some(v)
        _ => None
      }
      (number, Some(parameter))
    }
    _ => (None, None)
  }
}

///|
/// Connect portable extent derivations to the same expression/binding/pattern
/// owners. This does not construct semantic envelope CIDs or admit profiles.
pub fn check_text_bounds(
  patterns : PatternChecks,
  limits : TextBoundsLimits,
) -> Result[TextBoundsChecks, TextBoundsIssue] {
  if limits.max_work < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let before = pattern_usage(patterns)
  if before.work > limits.max_work || before.text_bytes > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let b : TextBoundBudget = {
    work: limits.max_work - before.work,
    text: limits.max_text_bytes - before.text_bytes,
  }
  let context = pattern_context(patterns)
  let resolved_patterns : Map[(Int, Int), PatternResolution] = Map([])
  let entries : Array[TextBoundResolution] = []
  try {
    bound_spend(b, pattern_count(patterns))
    for i in 0..<pattern_count(patterns) {
      let pattern = pattern_at(patterns, i).unwrap()
      resolved_patterns[validation_site_location(pattern_site(pattern))] = pattern
    }
    let mut start = 0
    let count = expression_validation_count(context)
    while start < count {
      let first = expression_validation_at(context, start).unwrap()
      let first_req = validation_site_requirement(first)
      let stage = validation_site_location(first).0
      let expression = first_req.expression
      let hosts : Map[Int, (ExpressionValidationSite, Int)] = Map([])
      let local_patterns : Map[Int, PatternResolution] = Map([])
      let order : Array[Int] = []
      let mut end = start
      while end < count {
        let site = expression_validation_at(context, end).unwrap()
        let req = validation_site_requirement(site)
        if validation_site_location(site).0 != stage ||
          req.visit != first_req.visit ||
          req.slot != first_req.slot {
          break
        }
        bound_spend(b, 1)
        match req.obligation.kind {
          HostEnvelope => {
            hosts[req.obligation.node_index] = (site, end)
            order.push(req.obligation.node_index)
          }
          PatternValidation(_) => {
            let pattern = resolved_patterns
              .get(validation_site_location(site))
              .unwrap()
            local_patterns[req.obligation.node_index] = pattern
          }
          _ => ()
        }
        end += 1
      }
      if !order.is_empty() {
        let policy = match expression_validation_text_time(context) {
          Some(v) => v
          None => raise TextBoundStop(MissingPolicy(hosts[order[0]].1))
        }
        let p = @environment.text_time_policy(policy)
        let demands = match
          @typing.derive_demands(expression, {
            max_work: b.work,
            max_text_bytes: b.text,
            max_links: b.work,
          }) {
          Ok(v) => v
          Err(@typing.BudgetExceeded) => raise TextBoundStop(BudgetExceeded)
          Err(e) => raise TextBoundStop(Demand(hosts[order[0]].1, e))
        }
        let demand_usage = @typing.demand_usage(demands)
        bound_spend(b, demand_usage.work)
        b.text -= demand_usage.text_bytes
        let n = @typing.node_count(expression)
        // Charge allocation and the postorder scan before creating node tables.
        bound_spend(b, n)
        bound_spend(b, n)
        let outputs : Array[@bounds.Output?] = Array::make(n, None)
        let resolutions : Map[Int, TextBoundResolution] = Map([])
        for node = n - 1; node >= 0; node = node - 1 {
          let (site, index) = match hosts.get(node) {
            Some(v) => v
            None => continue
          }
          let tag = match @typing.node_form(expression, node) {
            Some(@typing.Expression(tag, _)) => tag
            _ => raise TextBoundStop(InvalidSite(index))
          }
          let child = match @typing.child_at(expression, node, 0) {
            Some(v) => v
            None => raise TextBoundStop(InvalidSite(index))
          }
          let (input, input_parameter) = bound_input(
            expression, child, outputs, site, index, p, b,
          )
          let mut length_parameter = None
          let operation = match tag {
            "split_part" => @bounds.SplitPart
            "substring" | "utf8_truncate" => {
              let (number, parameter) = bound_length(
                expression,
                node,
                if tag == "substring" {
                  2
                } else {
                  1
                },
                site,
                index,
                b,
              )
              length_parameter = parameter
              if tag == "substring" {
                @bounds.Substring(number)
              } else {
                @bounds.Utf8Truncate(number)
              }
            }
            "try_number" => @bounds.TryNumber
            "nfkc" => @bounds.Nfkc
            "case_fold" => @bounds.CaseFold
            "parse_timestamp" => @bounds.ParseTimestamp
            "try_timestamp" => @bounds.TryTimestamp
            "format_timestamp" =>
              match local_patterns.get(node) {
                Some(Timestamp(v)) =>
                  @bounds.FormatTimestamp(timestamp_pattern_ast(v))
                _ => raise TextBoundStop(InvalidSite(index))
              }
            "regex_match" => @bounds.RegexMatch
            "regex_extract" => @bounds.RegexExtract
            "regex_replace" =>
              match local_patterns.get(node) {
                Some(Regex(v)) =>
                  match regex_pattern_operation(v) {
                    Replace(r) => @bounds.RegexReplace(r)
                    _ => raise TextBoundStop(InvalidSite(index))
                  }
                _ => raise TextBoundStop(InvalidSite(index))
              }
            _ => raise TextBoundStop(UnsupportedOperation(index, tag))
          }
          let output = bound_result(
            @bounds.derive_output(
              input,
              operation,
              additional_nullable=@typing.node_at(expression, node).unwrap().contract.nullable,
            ),
            index,
          )
          outputs[node] = Some(output)
          resolutions[node] = {
            site,
            output,
            input_parameter,
            length_parameter,
            policy,
            demands,
          }
        }
        bound_spend(b, order.length())
        for node in order {
          entries.push(resolutions[node])
        }
      }
      start = end
    }
    Ok({
      patterns,
      entries,
      usage: {
        work: limits.max_work - b.work,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    TextBoundStop(e) => Err(e)
  }
}

///|
pub fn text_bounds_patterns(v : TextBoundsChecks) -> PatternChecks {
  v.patterns
}

///|
pub fn text_bound_count(v : TextBoundsChecks) -> Int {
  v.entries.length()
}

///|
pub fn text_bound_at(v : TextBoundsChecks, i : Int) -> TextBoundResolution? {
  v.entries.get(i)
}

///|
pub fn text_bounds_usage(v : TextBoundsChecks) -> TextBoundsUsage {
  v.usage
}

///|
pub fn text_bound_site(v : TextBoundResolution) -> ExpressionValidationSite {
  v.site
}

///|
pub fn text_bound_output(v : TextBoundResolution) -> @bounds.Output {
  v.output
}

///|
pub fn text_bound_input_parameter(
  v : TextBoundResolution,
) -> @parameter.BoundParameter? {
  v.input_parameter
}

///|
pub fn text_bound_length_parameter(
  v : TextBoundResolution,
) -> @parameter.BoundParameter? {
  v.length_parameter
}

///|
pub fn text_bound_policy(v : TextBoundResolution) -> @environment.TextTime {
  v.policy
}

///|
/// Expression-local demand only; consumer filters and semantic root placement
/// still belong to the enclosing compilation boundary.
pub fn text_bound_demands(v : TextBoundResolution) -> @typing.DemandPaths {
  v.demands
}
