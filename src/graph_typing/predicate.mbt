///|
pub(all) struct PredicateLimits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
  max_tokens : Int
}

///|
pub(all) struct PredicateUsage {
  work : Int
  nodes : Int
  text_bytes : Int
  tokens : Int
}

///|
pub enum PredicateIssue {
  InvalidPredicateLimits
  PredicateBudget(@decode.Cursor)
  ScopeIssue(Issue)
  SyntaxIssue(@syntax.Issue)
  TypingIssue(@typing.Issue)
  UnknownPredicateField(@syntax.FieldReference)
  UntypedPredicateField(@syntax.FieldReference)
  ExpectedPredicateBoolean(@decode.Cursor)
}

///|
struct CheckedPredicate {
  typed : @typing.TypedExpression
  references : Array[(String, @row.FieldName)]
  usage : PredicateUsage
}

///|
/// Check only referenced fields; unrelated open or untyped properties remain valid.
pub fn check_predicate(
  entity : EntityKind,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : PredicateLimits,
) -> Result[CheckedPredicate, PredicateIssue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_tokens < 0 {
    return Err(InvalidPredicateLimits)
  }
  let scope = match
    check_scope(entity, source, input, {
      max_work: limits.max_work,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes,
    }) {
    Ok(s) => s
    Err(e) => return Err(ScopeIssue(e))
  }
  check_predicate_in_scope(scope, source, parameters, limits)
}

///|
// The match checker supplies the exact admitted definition scope. This is the
// same expression checker and evaluator, not a Graph-specific expression engine.
fn check_predicate_in_scope(
  scope : CheckedScope,
  source : @decode.Cursor,
  parameters : @parameter.Declarations?,
  limits : PredicateLimits,
) -> Result[CheckedPredicate, PredicateIssue] {
  if scope.usage.work > limits.max_work ||
    scope.usage.text_bytes > limits.max_text_bytes {
    return Err(PredicateBudget(source))
  }
  let mut work = limits.max_work - scope.usage.work
  let mut nodes = limits.max_nodes
  let mut text = limits.max_text_bytes - scope.usage.text_bytes
  let expression = match
    @syntax.admit(source, {
      max_nodes: nodes.min(work),
      max_depth: limits.max_depth,
      max_text_bytes: text,
      max_tokens: limits.max_tokens,
      tree: {
        max_nodes: nodes.min(work),
        max_depth: limits.max_depth,
        max_string_bytes: text,
        max_total_string_bytes: text,
      },
    }) {
    Ok(e) => e
    Err(e) => return Err(SyntaxIssue(e))
  }
  let syntax_usage = @syntax.usage(expression)
  work -= syntax_usage.nodes
  nodes -= syntax_usage.nodes
  text -= syntax_usage.text_bytes
  let visible : Map[String, @carrier.Field] = Map([])
  let count = @carrier.field_count(scope.fields)
  if count > work {
    return Err(PredicateBudget(source))
  }
  work -= count
  for i in 0..<count {
    let f = @carrier.field_at(scope.fields, i).unwrap()
    visible[@row.reference_name(f.name)] = f
  }
  let groups : Array[Array[(String, @contract.Contract)]] = [[], [], []]
  let seen : Map[String, Bool] = Map([])
  let references : Array[(String, @row.FieldName)] = []
  let count = @syntax.relation_reference_count(expression)
  if count > work {
    return Err(PredicateBudget(source))
  }
  work -= count
  for i in 0..<count {
    let occurrence = @syntax.relation_reference_at(expression, i).unwrap()
    let field = match visible.get(occurrence.name) {
      Some(f) => f
      None => return Err(UnknownPredicateField(occurrence))
    }
    let contract = match field.contract {
      Some(c) => c
      None => return Err(UntypedPredicateField(occurrence))
    }
    references.push((occurrence.name, field.name))
    if !seen.contains(occurrence.name) {
      seen[occurrence.name] = true
      match field.name {
        Unqualified(name) => groups[0].push((name, contract))
        Qualified(Left, name) => groups[1].push((name, contract))
        Qualified(Right, name) => groups[2].push((name, contract))
      }
    }
  }
  let contracts : Array[@contract.Contract?] = []
  for group in groups {
    if group.is_empty() {
      contracts.push(None)
      continue
    }
    if group.length() >= work || nodes == 0 {
      return Err(PredicateBudget(source))
    }
    work -= group.length() + 1
    nodes -= 1
    for (name, _) in group {
      match @scalar.admit_utf8_length(name, text) {
        Ok(n) => text -= n
        Err(_) => return Err(PredicateBudget(source))
      }
    }
    match
      @contract.object_contract(
        group,
        nullable=false,
        max_fields=group.length(),
        max_name_bytes=limits.max_text_bytes,
      ) {
      Ok(c) => contracts.push(Some(c))
      Err(_) => return Err(PredicateBudget(source))
    }
  }
  let typed = match
    @typing.check(
      expression,
      {
        fields: contracts[0],
        left: contracts[1],
        right: contracts[2],
        parameters,
      },
      {
        max_work: work,
        max_nodes: nodes.min(work),
        max_depth: limits.max_depth,
        max_text_bytes: text,
      },
    ) {
    Ok(t) => t
    Err(e) => return Err(TypingIssue(e))
  }
  if !(@typing.result_type(typed).shape is @contract.Boolean) {
    return Err(ExpectedPredicateBoolean(source))
  }
  let usage = @typing.usage(typed)
  Ok({
    typed,
    references,
    usage: {
      work: limits.max_work - work + usage.work,
      nodes: limits.max_nodes - nodes + usage.nodes,
      text_bytes: limits.max_text_bytes - text + usage.text_bytes,
      tokens: syntax_usage.tokens,
    },
  })
}

///|
pub fn predicate_expression(c : CheckedPredicate) -> @typing.TypedExpression {
  c.typed
}

///|
pub fn predicate_reference_count(c : CheckedPredicate) -> Int {
  c.references.length()
}

///|
pub fn predicate_reference_name(c : CheckedPredicate, index : Int) -> String? {
  c.references.get(index).map(value => value.0)
}

///|
pub fn predicate_reference_field(
  c : CheckedPredicate,
  index : Int,
) -> @row.FieldName? {
  c.references.get(index).map(value => value.1)
}

///|
pub fn predicate_usage(c : CheckedPredicate) -> PredicateUsage {
  c.usage
}
