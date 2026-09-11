///|
pub(all) struct DemandLimits {
  max_work : Int
  max_text_bytes : Int
  max_links : Int
} derive(Eq, Debug)

///|
pub(all) enum DemandIssue {
  InvalidLimits
  BudgetExceeded
  InvalidNode
} derive(Eq, Debug)

///|
pub(all) enum DemandTestKind {
  IsTrue
  NotTrue
  IsNull
} derive(Eq, Debug)

///|
/// A test of an already evaluated node in the same expression frame.
pub struct DemandTest {
  node_index : Int
  kind : DemandTestKind
} derive(Eq, Debug)

///|
pub(all) struct DemandUsage {
  work : Int
  text_bytes : Int
  links : Int
} derive(Eq, Debug)

///|
priv struct DemandAddress {
  parent : Int?
  segment : @decode.PathSegment?
  bytes : Int
}

///|
priv struct DemandLink {
  previous : Int?
  condition : DemandTest
  count : Int
}

///|
struct DemandPaths {
  expression : TypedExpression
  addresses : Array[DemandAddress]
  positions : Array[Int?]
  conditions : Array[DemandLink]
  heads : Array[Int?]
  usage : DemandUsage
}

///|
priv struct DemandBudget {
  mut work : Int
  mut text : Int
  mut links : Int
}

///|
priv suberror DemandStop {
  DemandStop(DemandIssue)
}

///|
fn demand_spend(b : DemandBudget, n : Int) -> Unit raise DemandStop {
  if n > b.work {
    raise DemandStop(BudgetExceeded)
  }
  b.work -= n
}

///|
fn demand_link(b : DemandBudget) -> Unit raise DemandStop {
  demand_spend(b, 1)
  if b.links == 0 {
    raise DemandStop(BudgetExceeded)
  }
  b.links -= 1
}

///|
fn demand_address(
  addresses : Array[DemandAddress],
  parent : Int,
  segment : @decode.PathSegment,
  b : DemandBudget,
) -> Int raise DemandStop {
  demand_link(b)
  let name = match segment {
    Key(name) => name
    Index(i) => i.to_string()
  }
  demand_spend(b, name.length())
  let raw = match @scalar.admit_utf8_length(name, b.text) {
    Ok(n) => n
    Err(_) => raise DemandStop(BudgetExceeded)
  }
  let mut bytes = raw
  demand_spend(b, name.length())
  for unit in name.iter() {
    if unit == '~' || unit == '/' {
      if bytes >= b.text {
        raise DemandStop(BudgetExceeded)
      }
      bytes += 1
    }
  }
  if bytes >= b.text {
    raise DemandStop(BudgetExceeded)
  }
  bytes += 1 // the JSON Pointer separator
  b.text -= bytes
  if addresses[parent].bytes > 2147483647 - bytes {
    raise DemandStop(BudgetExceeded)
  }
  let index = addresses.length()
  addresses.push({
    parent: Some(parent),
    segment: Some(segment),
    bytes: addresses[parent].bytes + bytes,
  })
  index
}

///|
fn demand_append(
  conditions : Array[DemandLink],
  previous : Int?,
  node_index : Int,
  kind : DemandTestKind,
  b : DemandBudget,
) -> Int raise DemandStop {
  demand_link(b)
  let count = match previous {
    Some(i) => conditions[i].count + 1
    None => 1
  }
  let index = conditions.length()
  conditions.push({ previous, condition: { node_index, kind, }, count, })
  index
}

///|
/// Derive expression-local demand from immutable typed topology. No branch is
/// evaluated and no consumer filter or external identity is invented here.
pub fn derive_demands(
  expression : TypedExpression,
  limits : DemandLimits,
) -> Result[DemandPaths, DemandIssue] {
  if limits.max_work < 0 || limits.max_text_bytes < 0 || limits.max_links < 0 {
    return Err(InvalidLimits)
  }
  let b : DemandBudget = {
    work: limits.max_work,
    text: limits.max_text_bytes,
    links: limits.max_links,
  }
  try {
    let n = node_count(expression)
    demand_spend(b, n)
    demand_spend(b, n)
    let positions : Array[Int?] = Array::make(n, None)
    let heads : Array[Int?] = Array::make(n, None)
    let by_source : Map[Int, Int] = Map([])
    let root = @syntax.tree(expression.expression)
    for i in 0..<n {
      demand_spend(b, 1)
      if expression.layout[i].tag != "#null" {
        by_source[@decode.tree_index(root, expression.layout[i].source).unwrap()] = i
      }
    }
    demand_link(b)
    let addresses : Array[DemandAddress] = [
      { parent: None, segment: None, bytes: 0, },
    ]
    let pending : Array[(@decode.Cursor, Int)] = [(root, 0)]
    while pending.pop() is Some((cursor, address)) {
      demand_spend(b, 1)
      if by_source.get(@decode.tree_index(root, cursor).unwrap()) is Some(i) {
        positions[i] = Some(address)
        // Literal payloads, templates, contracts and reference labels are not
        // expression children. Never discover fake calls inside business data.
        if expression.layout[i].children.is_empty() {
          continue
        }
      }
      if @decode.array_length(cursor) is Some(count) {
        demand_spend(b, count)
        for i = count - 1; i >= 0; i = i - 1 {
          let next = demand_address(addresses, address, Index(i), b)
          pending.push((@decode.element_at(cursor, i).unwrap(), next))
        }
      } else if @decode.object_length(cursor) is Some(count) {
        demand_spend(b, count)
        for i = count - 1; i >= 0; i = i - 1 {
          let (name, value) = @decode.field_at(cursor, i).unwrap()
          let next = demand_address(addresses, address, Key(name), b)
          pending.push((value, next))
        }
      }
    }
    let conditions : Array[DemandLink] = []
    // Parents precede children. Prefixes are shared rather than copied for
    // every CASE clause, coalesce operand or deep conditional descendant.
    for i in 0..<n {
      demand_spend(b, 1)
      let node = expression.layout[i]
      if node.tag != "#null" && positions[i] is None {
        raise DemandStop(InvalidNode)
      }
      let outer = heads[i]
      let children = node.children
      demand_spend(b, children.length())
      match node.tag {
        "if" => {
          heads[children[0]] = outer
          heads[children[1]] = Some(
            demand_append(conditions, outer, children[0], IsTrue, b),
          )
          heads[children[2]] = Some(
            demand_append(conditions, outer, children[0], NotTrue, b),
          )
        }
        "case" => {
          let mut prefix = outer
          let pairs = (children.length() - 1) / 2
          for clause in 0..<pairs {
            let condition = children[clause * 2]
            heads[condition] = prefix
            heads[children[clause * 2 + 1]] = Some(
              demand_append(conditions, prefix, condition, IsTrue, b),
            )
            prefix = Some(
              demand_append(conditions, prefix, condition, NotTrue, b),
            )
          }
          heads[children[children.length() - 1]] = prefix
        }
        "coalesce" => {
          let mut prefix = outer
          for ordinal in 0..<children.length() {
            let child = children[ordinal]
            heads[child] = prefix
            if ordinal + 1 < children.length() {
              prefix = Some(demand_append(conditions, prefix, child, IsNull, b))
            }
          }
        }
        _ =>
          for child in children {
            heads[child] = outer
          }
      }
    }
    Ok({
      expression,
      addresses,
      positions,
      conditions,
      heads,
      usage: {
        work: limits.max_work - b.work,
        text_bytes: limits.max_text_bytes - b.text,
        links: limits.max_links - b.links,
      },
    })
  } catch {
    DemandStop(e) => Err(e)
  }
}

///|
pub fn demand_expression(v : DemandPaths) -> TypedExpression {
  v.expression
}

///|
pub fn demand_usage(v : DemandPaths) -> DemandUsage {
  v.usage
}

///|
/// Return a detached outer-to-inner test list, bounded before allocation.
pub fn demand_tests(
  v : DemandPaths,
  node : Int,
  max_tests~ : Int,
) -> Result[Array[DemandTest], DemandIssue] {
  if max_tests < 0 {
    return Err(InvalidLimits)
  }
  if node < 0 || node >= v.heads.length() {
    return Err(InvalidNode)
  }
  let count = match v.heads[node] {
    Some(i) => v.conditions[i].count
    None => 0
  }
  if count > max_tests {
    return Err(BudgetExceeded)
  }
  let result = []
  let mut head = v.heads[node]
  while head is Some(i) {
    result.push(v.conditions[i].condition)
    head = v.conditions[i].previous
  }
  for i in 0..<(result.length() / 2) {
    let last = result.length() - 1 - i
    let saved = result[i]
    result[i] = result[last]
    result[last] = saved
  }
  Ok(result)
}

///|
/// RFC6901 pointer relative to the normalized expression root (empty string).
/// An implicit CASE ELSE has no source occurrence and returns None.
pub fn demand_pointer(
  v : DemandPaths,
  node : Int,
  max_bytes~ : Int,
) -> Result[String?, DemandIssue] {
  if max_bytes < 0 {
    return Err(InvalidLimits)
  }
  if node < 0 || node >= v.positions.length() {
    return Err(InvalidNode)
  }
  let start = match v.positions[node] {
    Some(i) => i
    None => return Ok(None)
  }
  if v.addresses[start].bytes > max_bytes {
    return Err(BudgetExceeded)
  }
  let segments = []
  let mut index = start
  while v.addresses[index].parent is Some(parent) {
    segments.push(v.addresses[index].segment.unwrap())
    index = parent
  }
  let out = StringBuilder()
  for i = segments.length() - 1; i >= 0; i = i - 1 {
    out.write_char('/')
    match segments[i] {
      Index(n) => out.write_string(n.to_string())
      Key(name) =>
        for c in name.iter() {
          if c == '~' {
            out.write_string("~0")
          } else if c == '/' {
            out.write_string("~1")
          } else {
            out.write_char(c)
          }
        }
    }
  }
  Ok(Some(out.to_string()))
}
