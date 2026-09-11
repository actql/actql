///|
pub(all) enum CandidateRole {
  ProvenUpperBound
  AuthorGuard
  ContractCeiling
  LanguageCeiling
  HostCeiling
} derive(Eq, Debug)

///|
pub(all) enum GuardBinding {
  Absent
  Binding
  CurrentlyNonBinding
} derive(Eq, Debug)

///|
pub(all) struct Candidate {
  node : Int
  role : CandidateRole
}

///|
pub(all) enum CandidateIssue {
  InvalidLimit
  BudgetExceeded
  EmptyCandidates
  MissingNode(Int)
  WrongUnit(Int)
  NonpositiveGuard(Int)
} derive(Eq, Debug)

///|
/// Arithmetic selection only. Roles and applicability need source validation.
struct CandidateMinimum {
  graph : CheckedArithmetic
  candidates : Array[Candidate]
  unit : BoundUnit
  maximum : Int64
  binding : GuardBinding
}

///|
/// Computes all supplied candidates, retaining equal values and repeated nodes.
/// Cannot establish that the caller supplied every applicable source witness.
pub fn select_candidate_minimum(
  graph : CheckedArithmetic,
  candidates : Array[Candidate],
  unit : BoundUnit,
  max_candidates~ : Int,
) -> Result[CandidateMinimum, CandidateIssue] {
  if max_candidates < 0 {
    return Err(InvalidLimit)
  }
  if candidates.length() > max_candidates {
    return Err(BudgetExceeded)
  }
  if candidates.is_empty() {
    return Err(EmptyCandidates)
  }
  let mut minimum = 9007199254740991L
  let mut author : Int64? = None
  let mut other : Int64? = None
  for i in 0..<candidates.length() {
    let candidate = candidates[i]
    guard value_at(graph, candidate.node) is Some(value) else {
      return Err(MissingNode(i))
    }
    if unit_at(graph, candidate.node) != Some(unit) {
      return Err(WrongUnit(i))
    }
    if value < minimum {
      minimum = value
    }
    if candidate.role == AuthorGuard {
      if value == 0L {
        return Err(NonpositiveGuard(i))
      }
      author = Some(
        match author {
          Some(previous) => if previous < value { previous } else { value }
          None => value
        },
      )
    } else {
      other = Some(
        match other {
          Some(previous) => if previous < value { previous } else { value }
          None => value
        },
      )
    }
  }
  let binding = match (author, other) {
    (None, _) => Absent
    (Some(_), None) => Binding
    (Some(a), Some(b)) => if a < b { Binding } else { CurrentlyNonBinding }
  }
  Ok({ graph, candidates: candidates.copy(), unit, maximum: minimum, binding, })
}

///|
pub fn minimum_graph(v : CandidateMinimum) -> CheckedArithmetic {
  v.graph
}

///|
pub fn minimum_value(v : CandidateMinimum) -> Int64 {
  v.maximum
}

///|
pub fn minimum_unit(v : CandidateMinimum) -> BoundUnit {
  v.unit
}

///|
pub fn minimum_guard_binding(v : CandidateMinimum) -> GuardBinding {
  v.binding
}

///|
pub fn minimum_candidate_count(v : CandidateMinimum) -> Int {
  v.candidates.length()
}

///|
pub fn minimum_candidate_at(v : CandidateMinimum, index : Int) -> Candidate? {
  v.candidates.get(index)
}
