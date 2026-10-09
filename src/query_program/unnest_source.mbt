///|
// Establish a source-free value table's visible fields from the ordinary
// expression checker, including empty and NULL ARRAYs. This type lookup does
// not discharge profiles, parameter-value checks or runtime obligations.
fn unnest_source_element(
  expression : @query.Expression,
  declarations : @parameters.Declarations?,
  limits : Limits,
  max_work : Int,
  resolve_parameter : ((String) -> Result[String, @expression.Issue])?,
) -> @contract.Contract? raise Abort {
  let source_limits = limits.source
  let origin = @query.expression_origin(
    expression,
    @query.expression_root(expression),
  )
  let lowered = match
    @expression.lower(
      expression,
      _ => None,
      {
        construction: source_limits,
        expression: {
          max_nodes: source_limits.tree.max_nodes,
          max_depth: source_limits.tree.max_depth,
          max_text_bytes: source_limits.tree.max_total_string_bytes,
          max_tokens: source_limits.tree.max_nodes,
          tree: source_limits.tree,
        },
        max_work,
      },
      resolve_parameter~,
    ) {
    Ok(lowered) => lowered
    // Relation-bound correlation has no field schema in this scope probe.
    // The caller lowers it against the actual row/ranges below; explicit
    // projection does not require guessed element fields. Budget and all
    // other lowerer errors still propagate. Unknown stars remain refused.
    Err({ issue: @expression.UnknownReference, .. }) => return None
    Err(diagnostic) => raise Abort(Expression(diagnostic))
  }
  // Use the same authored-member binder as complete query admission before
  // this early type probe. Parameter contracts stay case-exact machine data;
  // only resolved property selectors are rewritten to their declared spelling.
  let resolution : MemberResolution = {
    source: @expression.source(lowered),
    document: @query.expression_document(expression),
    limits,
    work: max_work,
    output_work: 0,
    probe_refused: false,
    replacements: Map([]),
  }
  let mut refused : @typing.Issue? = None
  resolution.expression(
    @builder.cursor(resolution.source),
    None,
    declarations,
    retain_refusal=issue => refused = Some(issue),
  )
  if refused is Some(issue) {
    match issue.kind {
      NullTypeUnresolved => return None
      _ => raise Abort(ExpressionTyping(issue))
    }
  }
  let normalized = resolution.finish()
  let admitted = match
    @expression_syntax.admit(@builder.cursor(normalized), {
      max_nodes: source_limits.tree.max_nodes.min(resolution.work),
      max_depth: source_limits.tree.max_depth,
      max_text_bytes: source_limits.tree.max_total_string_bytes,
      max_tokens: source_limits.tree.max_nodes.min(resolution.work),
      tree: source_limits.tree,
    }) {
    Ok(admitted) => admitted
    Err({ kind: BudgetExceeded, .. }) =>
      raise Abort(Expression({ issue: @expression.WorkLimit, origin, }))
    Err(issue) =>
      raise Abort(Expression({ issue: @expression.Admission(issue), origin, }))
  }
  resolution.spend(
    @builder.cursor(normalized),
    @expression_syntax.usage(admitted).nodes,
  )
  let typed = match
    @typing.check(
      admitted,
      { fields: None, left: None, right: None, parameters: declarations, },
      {
        max_nodes: source_limits.tree.max_nodes,
        max_depth: source_limits.tree.max_depth,
        max_work: resolution.work,
        max_text_bytes: source_limits.tree.max_total_string_bytes,
      },
    ) {
    Ok(typed) => typed
    Err({ kind: BudgetExceeded, .. }) =>
      raise Abort(Expression({ issue: @expression.WorkLimit, origin, }))
    Err({ kind: InvalidLimits, .. }) =>
      raise Abort(Expression({ issue: @expression.InvalidLimits, origin, }))
    // Without an inferred element contract, untyped empty/NULL arrays keep
    // their existing unsupported scope. Proven input violations are different:
    // a star requires this probe to succeed before any Program can be checked.
    Err({ kind: NullTypeUnresolved, .. }) => return None
    Err(issue) => raise Abort(ExpressionTyping(issue))
  }
  match @typing.result_type(typed).shape {
    @contract.Array(element, ..) => Some(element)
    // The checked receiver is known not to be an ARRAY. Missing star fields
    // must not hide that input violation behind an implementation limit.
    _ =>
      raise Abort(Expression({ issue: @expression.InvalidArguments, origin, }))
  }
}

///|
// A value-table range denotes its original value and takes precedence over
// same-named input columns or implicit fields in expression scope. Object
// receivers are not extra star columns; scalar receivers keep their own slots.
fn unnest_expression_columns(
  visible : Array[(String, String)],
  object_receivers : Array[(@query.NamePart, String)],
  scalar_receivers : Array[(@query.NamePart, String)],
) -> Array[(String, String)] {
  let receivers = object_receivers + scalar_receivers
  let columns = visible.filter(entry => {
    !receivers.any(receiver => {
      same_name(receiver.0, { value: entry.0, quoted: false, })
    })
  })
  for (name, slot) in receivers {
    if !pipe_name_exists(columns, name) {
      columns.push((name.value, slot))
    }
  }
  columns
}
