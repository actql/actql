///|
/// Unauthenticated CID-addressed arithmetic descriptions, not wire witnesses.
pub(all) enum ReferencedDerivation {
  Source
  PreserveReference(String)
  MinimumReferences(Array[String])
  AddReferences(String, String)
  MultiplyReference(String, Int64)
  ClampReference(String?, Int64)
}

///|
pub(all) struct ReferencedNode {
  cid : String
  unit : BoundUnit
  claimed : Int64
  derivation : ReferencedDerivation
}

///|
pub(all) enum ReferenceIssue {
  InvalidReferenceLimits
  ReferenceBudgetExceeded
  InvalidIdentity(Int)
  InvalidReference(Int)
  DuplicateIdentity(Int)
  MissingReference(Int, String)
  ArithmeticFailure(Issue)
} derive(Eq, Debug)

///|
/// Complete numeric closure only. IDs are not checked against source bodies.
struct LinkedArithmetic {
  arithmetic : CheckedArithmetic
  identities : Array[String]
  indices : Map[String, Int]
}

///|
priv suberror ReferenceStop {
  ReferenceStop(ReferenceIssue)
}

///|
fn valid_identity(id : String) -> Bool {
  if id.length() != 71 || !id.has_prefix("sha256:") {
    return false
  }
  for i = 7; i < 71; i = i + 1 {
    let c = id[i].to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return false
    }
  }
  true
}

///|
fn reference_count(d : ReferencedDerivation) -> Int {
  match d {
    Source | ClampReference(None, _) => 0
    PreserveReference(_)
    | MultiplyReference(_, _)
    | ClampReference(Some(_), _) => 1
    AddReferences(_, _) => 2
    MinimumReferences(refs) => refs.length()
  }
}

///|
fn resolve_reference(
  indices : Map[String, Int],
  id : String,
  node : Int,
) -> Int raise ReferenceStop {
  if !valid_identity(id) {
    raise ReferenceStop(InvalidReference(node))
  }
  match indices.get(id) {
    Some(i) => i
    None => raise ReferenceStop(MissingReference(node, id))
  }
}

///|
/// Resolve every supplied node, including unused branches. Limits bound nodes
/// and reference occurrences before copying or traversing referenced arrays.
/// Repeated Add operands remain repeated; no global registry is consulted.
pub fn link_references(
  nodes : Array[ReferencedNode],
  limits : Limits,
) -> Result[LinkedArithmetic, ReferenceIssue] {
  try {
    if limits.max_nodes < 0 || limits.max_edges < 0 {
      raise ReferenceStop(InvalidReferenceLimits)
    }
    if nodes.length() > limits.max_nodes {
      raise ReferenceStop(ReferenceBudgetExceeded)
    }
    let indices : Map[String, Int] = Map([])
    let identities : Array[String] = []
    let mut edges = 0
    for i = 0; i < nodes.length(); i = i + 1 {
      let n = nodes[i]
      if !valid_identity(n.cid) {
        raise ReferenceStop(InvalidIdentity(i))
      }
      if indices.contains(n.cid) {
        raise ReferenceStop(DuplicateIdentity(i))
      }
      let count = reference_count(n.derivation)
      if count > limits.max_edges - edges {
        raise ReferenceStop(ReferenceBudgetExceeded)
      }
      edges = edges + count
      indices[n.cid] = i
      identities.push(n.cid)
    }
    let resolved : Array[Node] = []
    for i = 0; i < nodes.length(); i = i + 1 {
      let n = nodes[i]
      let derivation = match n.derivation {
        Source => Leaf
        PreserveReference(id) => Preserve(resolve_reference(indices, id, i))
        MinimumReferences(refs) => {
          let inputs : Array[Int] = []
          for id in refs {
            inputs.push(resolve_reference(indices, id, i))
          }
          Minimum(inputs)
        }
        AddReferences(left, right) =>
          Add(
            resolve_reference(indices, left, i),
            resolve_reference(indices, right, i),
          )
        MultiplyReference(id, factor) =>
          Multiply(resolve_reference(indices, id, i), factor)
        ClampReference(input, maximum) => {
          let input = match input {
            Some(id) => Some(resolve_reference(indices, id, i))
            None => None
          }
          Clamp(input, maximum)
        }
      }
      resolved.push({ unit: n.unit, claimed: n.claimed, derivation, })
    }
    match check(resolved, limits) {
      Ok(arithmetic) => Ok({ arithmetic, identities, indices, })
      Err(issue) => Err(ArithmeticFailure(issue))
    }
  } catch {
    ReferenceStop(issue) => Err(issue)
  }
}

///|
pub fn linked_arithmetic(graph : LinkedArithmetic) -> CheckedArithmetic {
  graph.arithmetic
}

///|
pub fn linked_identity_at(graph : LinkedArithmetic, index : Int) -> String? {
  graph.identities.get(index)
}

///|
pub fn linked_index(graph : LinkedArithmetic, cid : String) -> Int? {
  graph.indices.get(cid)
}
