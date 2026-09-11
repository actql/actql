///|
pub(all) enum BoundUnit {
  Rows
  DistinctKeys
  EffectItems
  Bytes
  ArrayItems
  Nodes
  Edges
  Paths
  MatchesPerKey
} derive(Eq, Debug)

///|
/// References are indices into the supplied graph, not self-authenticating IDs.
/// A Leaf's source remains unvalidated by this numerical checker.
pub(all) enum Derivation {
  Leaf
  Preserve(Int)
  Minimum(Array[Int])
  Add(Int, Int)
  Multiply(Int, Int64)
  Clamp(Int?, Int64)
}

///|
pub(all) struct Node {
  unit : BoundUnit
  claimed : Int64
  derivation : Derivation
}

///|
pub(all) struct Limits {
  max_nodes : Int
  max_edges : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  InvalidValue(Int)
  EmptyMinimum(Int)
  MissingDependency(Int, Int)
  UnitMismatch(Int, Int)
  Overflow(Int)
  ValueMismatch(Int)
  Cycle
} derive(Eq, Debug)

///|
/// Numerical consistency only; not authenticated evidence or a runnable limit.
struct CheckedArithmetic {
  values : Array[@arithmetic.Value]
  units : Array[BoundUnit]
  leaves : Array[Int]
  edges : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn number(n : Int64, index : Int) -> @arithmetic.Value raise Stop {
  match @arithmetic.read(n) {
    Ok(v) => v
    Err(_) => raise Stop(InvalidValue(index))
  }
}

///|
fn dependency_count(d : Derivation) -> Int {
  match d {
    Leaf | Clamp(None, _) => 0
    Preserve(_) | Multiply(_, _) | Clamp(Some(_), _) => 1
    Add(_, _) => 2
    Minimum(inputs) => inputs.length()
  }
}

///|
fn dependency_at(d : Derivation, index : Int) -> Int {
  match d {
    Preserve(i) | Multiply(i, _) | Clamp(Some(i), _) => i
    Add(left, right) => if index == 0 { left } else { right }
    Minimum(inputs) => inputs[index]
    Leaf | Clamp(None, _) => -1
  }
}

///|
/// Validate the entire graph, including unused nodes. Work and memory are
/// O(nodes + dependency occurrences); repeated operands count repeatedly.
/// Multiply may change units; its governing conversion law is not checked here.
pub fn check(
  nodes : Array[Node],
  limits : Limits,
) -> Result[CheckedArithmetic, Issue] {
  try {
    if limits.max_nodes < 0 || limits.max_edges < 0 {
      raise Stop(InvalidLimits)
    }
    let n = nodes.length()
    if n > limits.max_nodes {
      raise Stop(BudgetExceeded)
    }
    let values : Array[@arithmetic.Value] = []
    let units : Array[BoundUnit] = []
    let leaves : Array[Int] = []
    let dependents : Array[Array[Int]] = Array::makei(n, _ => [])
    let remaining = Array::make(n, 0)
    let ready : Array[Int] = []
    let mut edges = 0
    for i = 0; i < n; i = i + 1 {
      let node = nodes[i]
      values.push(number(node.claimed, i))
      units.push(node.unit)
      match node.derivation {
        Minimum(inputs) => if inputs.is_empty() { raise Stop(EmptyMinimum(i)) }
        Multiply(_, factor) | Clamp(_, factor) => ignore(number(factor, i))
        _ => ()
      }
      let count = dependency_count(node.derivation)
      if count > limits.max_edges - edges {
        raise Stop(BudgetExceeded)
      }
      edges = edges + count
      remaining[i] = count
      if count == 0 {
        ready.push(i)
      }
      if node.derivation is Leaf {
        leaves.push(i)
      }
      for j = 0; j < count; j = j + 1 {
        let dep = dependency_at(node.derivation, j)
        if dep < 0 || dep >= n {
          raise Stop(MissingDependency(i, dep))
        }
        // Multiplication can express a law-specific change of quantity, e.g.
        // input rows to output paths. Other operations preserve the unit.
        if !(node.derivation is Multiply(_, _)) && node.unit != nodes[dep].unit {
          raise Stop(UnitMismatch(i, dep))
        }
        dependents[dep].push(i)
      }
    }
    let mut head = 0
    while head < ready.length() {
      let i = ready[head]
      head = head + 1
      let computed = match nodes[i].derivation {
        Leaf => values[i]
        Preserve(input) => values[input]
        Minimum(inputs) => {
          let mut result = values[inputs[0]]
          for input in inputs {
            result = @arithmetic.minimum(result, values[input])
          }
          result
        }
        Add(left, right) =>
          match @arithmetic.add(values[left], values[right]) {
            Ok(v) => v
            Err(_) => raise Stop(Overflow(i))
          }
        Multiply(input, factor) =>
          match @arithmetic.multiply(values[input], number(factor, i)) {
            Ok(v) => v
            Err(_) => raise Stop(Overflow(i))
          }
        Clamp(input, maximum) =>
          @arithmetic.clamp(input.map(i => values[i]), number(maximum, i))
      }
      if computed != values[i] {
        raise Stop(ValueMismatch(i))
      }
      for dependent in dependents[i] {
        remaining[dependent] = remaining[dependent] - 1
        if remaining[dependent] == 0 {
          ready.push(dependent)
        }
      }
    }
    if head != n {
      raise Stop(Cycle)
    }
    Ok({ values, units, leaves, edges, })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn count(checked : CheckedArithmetic) -> Int {
  checked.values.length()
}

///|
pub fn value_at(checked : CheckedArithmetic, index : Int) -> Int64? {
  checked.values.get(index).map(@arithmetic.value)
}

///|
pub fn unit_at(checked : CheckedArithmetic, index : Int) -> BoundUnit? {
  checked.units.get(index)
}

///|
pub fn leaf_count(checked : CheckedArithmetic) -> Int {
  checked.leaves.length()
}

///|
pub fn leaf_at(checked : CheckedArithmetic, index : Int) -> Int? {
  checked.leaves.get(index)
}

///|
pub fn edge_count(checked : CheckedArithmetic) -> Int {
  checked.edges
}
