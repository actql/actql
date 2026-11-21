///|
/// The original occurrence-bound resolution, retained by lowering only after
/// producer and typed-node identity checks. This view is not Host admission.
struct ExpressionTextBound {
  original : @context.TextBoundResolution
  pattern : @context.PatternResolution?
}

///|
pub fn text_bound_output(value : ExpressionTextBound) -> @text_bounds.Output {
  @context.text_bound_output(value.original)
}

///|
pub fn text_bound_policy(value : ExpressionTextBound) -> @environment.TextTime {
  @context.text_bound_policy(value.original)
}

///|
/// Preserve the original typed filter identity without exposing a checker site.
pub fn text_bound_filter(
  value : ExpressionTextBound,
) -> @typing.TypedExpression? {
  let requirement = @context.validation_site_requirement(
    @context.text_bound_site(value.original),
  )
  requirement.filter.map(filter => filter.expression)
}

///|
/// The actual checked pattern attached to the same typed occurrence and producer.
/// No wire reparse, Parameter rebind or pattern issuance occurs at execution.
pub fn text_bound_timestamp_pattern(
  value : ExpressionTextBound,
) -> @timestamp.Pattern? {
  if value.pattern is Some(@context.Timestamp(pattern)) {
    Some(@context.timestamp_pattern_ast(pattern))
  } else {
    None
  }
}

///|
/// The exact checked regex and its authored flags remain sidecar data of this
/// occurrence. The runtime receives the original AST without another parser.
pub fn text_bound_regex_pattern(
  value : ExpressionTextBound,
) -> (@regex.Pattern, String?)? {
  if value.pattern is Some(@context.Regex(pattern)) &&
    @context.regex_pattern_operation(pattern) is @context.Match {
    Some(
      (
        @context.regex_pattern_ast(pattern),
        @context.regex_pattern_flags(pattern),
      ),
    )
  } else {
    None
  }
}

///|
/// The capture index is the Check-owned literal or bound Parameter result.
pub fn text_bound_regex_extract(
  value : ExpressionTextBound,
) -> (@regex.Pattern, String?, Int)? {
  if value.pattern is Some(@context.Regex(pattern)) &&
    @context.regex_pattern_operation(pattern) is @context.Extract(capture) {
    Some(
      (
        @context.regex_pattern_ast(pattern),
        @context.regex_pattern_flags(pattern),
        capture,
      ),
    )
  } else {
    None
  }
}
