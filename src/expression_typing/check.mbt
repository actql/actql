///|
fn check_impl(
  expression : @syntax.Expression,
  environment : Environment,
  limits : Limits,
) -> TypedExpression raise Stop {
  let source = @syntax.tree(expression)
  if limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_work < 0 ||
    limits.max_text_bytes < 0 {
    fail(source, InvalidLimits)
  }
  let budget : Budget = {
    work: limits.max_work,
    text: limits.max_text_bytes,
    limits,
  }
  let t : Types = { entries: [], budget, }
  let env = scopes(t, environment, source)
  let nodes = flatten(expression, budget)
  let pending : Array[Obligation] = []
  let profiles : Map[String, Bool] = Map([])
  let work = [(0, false)]
  while work.pop() is Some((i, visited)) {
    spend(budget, nodes[i].source)
    if visited {
      nodes[i].inferred = infer(t, nodes, i, env, pending, profiles)
    } else {
      work.push((i, true))
      let children = nodes[i].children
      for j = children.length() - 1; j >= 0; j = j - 1 {
        work.push((children[j], false))
      }
    }
  }
  let annotations : Array[TypedNode] = []
  let safe : Map[Int, Bool] = Map([])
  for node in nodes {
    let contract = resolve_type(t, node.inferred, node.source)
    if ["array", "empty_array", "object"].contains(node.tag) &&
      !constructor_safe(t, node.inferred, safe, node.source) {
      fail(node.source, ForbiddenConstructorValue)
    }
    annotations.push({ source: node.source, contract, role: node.role, })
  }
  pending.sort_by((a, b) => a.node_index.compare(b.node_index))
  let names = profiles.keys().to_array()
  names.sort_by(@canonical.compare_utf16)
  { expression, environment, annotations, profiles: names, pending, }
}

///|
/// A type proof, not a checked Plan or permission to execute. Every branch is
/// visited. Pending validations must be discharged by subsequent admission.
pub fn check(
  expression : @syntax.Expression,
  environment : Environment,
  limits : Limits,
) -> Result[TypedExpression, Issue] {
  Ok(check_impl(expression, environment, limits)) catch {
    Stop(issue) => Err(issue)
  }
}
