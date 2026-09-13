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
struct Profile {
  bytes : Int
}

///|
struct Reduction {
  owner : Profile
  algorithm : Algorithm
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
