///|
pub(all) enum Algorithm {
  LeftFold
  AdjacentPairs
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  IdentityMismatch
  UnsupportedProfile
  UnknownMember
} derive(Eq, Debug)

///|
pub(all) enum Operation {
  Sum
  Average
} derive(Eq, Debug)

///|
pub(all) enum ReductionIssue {
  InvalidLimits
  ContributorLimit
  WorkLimit
  NonfiniteContributor(Int)
  NonfiniteIntermediate
} derive(Eq, Debug)

///|
pub struct Outcome {
  value : Double?
  count : Int
  work : Int
}

///|
struct Profile {
  bytes : Int
}

///|
struct Reduction {
  owner : Profile
  algorithm : Algorithm
}

///|
/// Select the repository-pinned profile without admitting external bytes.
/// This is profile identity only; it grants no execution or capture authority.
pub fn builtin_profile() -> Profile {
  { bytes: 0, }
}

///|
/// Admit one fixed, pinned contract body. This does not admit an observation,
/// authorize execution, or choose a member on the caller's behalf.
pub fn admit(
  bytes : Bytes,
  expected_cid : String,
  max_bytes : Int,
) -> Result[Profile, Issue] {
  if max_bytes < 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > max_bytes {
    return Err(BudgetExceeded)
  }
  if expected_cid != supported_profile_cid() {
    return Err(UnsupportedProfile)
  }
  if "sha256:" + @sha.hex(bytes) != expected_cid {
    return Err(IdentityMismatch)
  }
  // The accepted digest identifies the complete canonical body, including every
  // member body and pin. No untrusted shape is decoded or retained, and the hash
  // uses fixed workspace. A different self-consistent body is not this profile.
  Ok({ bytes: bytes.length(), })
}

///|
pub fn cid(_ : Profile) -> String {
  supported_profile_cid()
}

///|
pub fn admitted_bytes(p : Profile) -> Int {
  p.bytes
}

///|
pub fn member_count(_ : Profile) -> Int {
  2
}

///|
pub fn member_cid_at(_ : Profile, index : Int) -> String? {
  match index {
    0 => Some(left_fold_cid())
    1 => Some(adjacent_pairs_cid())
    _ => None
  }
}

///|
/// Explicit membership selection, not an executed attempt or capture record.
pub fn select(p : Profile, member_cid : String) -> Result[Reduction, Issue] {
  let algorithm = if member_cid == left_fold_cid() {
    LeftFold
  } else if member_cid == adjacent_pairs_cid() {
    AdjacentPairs
  } else {
    return Err(UnknownMember)
  }
  Ok({ owner: p, algorithm, })
}

///|
pub fn reduction_profile(r : Reduction) -> Profile {
  r.owner
}

///|
pub fn algorithm(r : Reduction) -> Algorithm {
  r.algorithm
}

///|
pub fn reduction_cid(r : Reduction) -> String {
  match r.algorithm {
    LeftFold => left_fold_cid()
    AdjacentPairs => adjacent_pairs_cid()
  }
}

///|
pub fn outcome_value(outcome : Outcome) -> Double? {
  outcome.value
}

///|
pub fn outcome_count(outcome : Outcome) -> Int {
  outcome.count
}

///|
pub fn outcome_work(outcome : Outcome) -> Int {
  outcome.work
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn public_zero(value : Double) -> Double {
  if value == 0.0 {
    0.0
  } else {
    value
  }
}

///|
fn checked_add(left : Double, right : Double) -> Result[Double, ReductionIssue] {
  let value = left + right
  if finite(value) {
    Ok(value)
  } else {
    Err(NonfiniteIntermediate)
  }
}

///|
fn reduce_left_fold(
  contributors : Array[Double],
  work : Ref[Int],
  max_work : Int,
) -> Result[Double, ReductionIssue] {
  let mut value = 0.0
  for contributor in contributors {
    if work.val == max_work {
      return Err(WorkLimit)
    }
    work.val += 1
    value = match checked_add(value, contributor) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  Ok(value)
}

///|
fn reduce_adjacent_pairs(
  contributors : Array[Double],
  work : Ref[Int],
  max_work : Int,
) -> Result[Double, ReductionIssue] {
  if contributors.length() == 1 {
    return Ok(contributors[0])
  }
  let mut current = contributors.copy()
  while current.length() > 1 {
    let next : Array[Double] = []
    let mut index = 0
    while index < current.length() {
      if index + 1 == current.length() {
        next.push(current[index])
      } else {
        if work.val == max_work {
          return Err(WorkLimit)
        }
        work.val += 1
        let value = match checked_add(current[index], current[index + 1]) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        next.push(value)
      }
      index += 2
    }
    current = next
  }
  Ok(current[0])
}

///|
/// Execute one selected reduction member over an already selected contributor
/// sequence. Work charges one unit for each contributor admission, each
/// prescribed addition, and the final average division. This function does not
/// admit an aggregate slot, bind an attempt, or publish capture evidence.
pub fn execute(
  reduction : Reduction,
  operation : Operation,
  contributors : Array[Double],
  max_contributors : Int,
  max_work : Int,
) -> Result[Outcome, ReductionIssue] {
  if max_contributors < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let count = contributors.length()
  if count > max_contributors {
    return Err(ContributorLimit)
  }
  let work = Ref(0)
  for index, contributor in contributors {
    if work.val == max_work {
      return Err(WorkLimit)
    }
    work.val += 1
    if !finite(contributor) {
      return Err(NonfiniteContributor(index))
    }
  }
  if count == 0 {
    return Ok({ value: None, count, work: work.val, })
  }
  let sum = match reduction.algorithm {
    LeftFold => reduce_left_fold(contributors, work, max_work)
    AdjacentPairs => reduce_adjacent_pairs(contributors, work, max_work)
  }
  let mut value = match sum {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if operation is Average {
    if work.val == max_work {
      return Err(WorkLimit)
    }
    work.val += 1
    value /= count.to_double()
    if !finite(value) {
      return Err(NonfiniteIntermediate)
    }
  }
  Ok({ value: Some(public_zero(value)), count, work: work.val, })
}
