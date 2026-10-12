///|
/// A resolved finite ceiling retained with its admitted Catalog profile.
/// This is an enforcement obligation, not an observed row count or read grant.
struct FileListingRows {
  profile : FileListProfile
  policy : @policy.Policy?
  claim : @bound_wire.LimitClaim
}

///|
pub(all) enum FileListingRowsIssue {
  Unresolved
} derive(Eq, Debug)

///|
let listing_record_bytes = 20000

///|
fn listing_sealed_record(
  body : Json,
  self_field : String,
) -> Result[(Bytes, String), FileListingRowsIssue] {
  try {
    let value = @canonical.from_json(body, 2000, 32, listing_record_bytes)
    let cid = @canonical.cid_value(value, listing_record_bytes, 2000, 32)
    let record = @canonical.object_with_string_field(value, self_field, cid).unwrap()
    Ok(
      (
        @utf8.encode(
          @canonical.stringify_value(record, listing_record_bytes, 2000, 32),
        ),
        cid,
      ),
    )
  } catch {
    _ => Err(Unresolved)
  }
}

///|
fn listing_wire_candidate(
  body : Json,
) -> Result[@bound_wire.WireWitness, FileListingRowsIssue] {
  let (bytes, cid) = match listing_sealed_record(body, "witness_cid") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @bound_wire.admit(bytes, cid, {
    max_bytes: listing_record_bytes,
    max_nodes: 2000,
    max_depth: 32,
  }).map_err(_ => Unresolved)
}

///|
fn listing_candidate_json(value : @bound_wire.WireWitness) -> Json raise {
  let writer = @encode.writer(listing_record_bytes, 2000, 32)
  @bound_wire.emit(value, writer)
  @json.parse(@encode.finish(writer))
}

///|
fn resolve_listing_row_candidates(
  facts_cid : String,
  contract_maximum : Int64?,
  policy : @policy.Policy?,
  subject : String,
) -> Result[@bound_wire.LimitClaim, FileListingRowsIssue] {
  let candidates : Array[@bound_wire.WireWitness] = []
  if contract_maximum is Some(maximum) {
    if maximum <= 0L || maximum > 9007199254740991L {
      return Err(Unresolved)
    }
    let body : Json = {
      "dependencies": Json::array([Json::string(facts_cid)]),
      "derivation": { "op": "source" },
      "law_id": "actql.contract.file-listing-items",
      "role": "contract_ceiling",
      "source": {
        "contract_cid": Json::string(facts_cid),
        "field": "file_listing.max_listing_items",
        "kind": "contract",
      },
      "unit": "rows",
      "value": Json::number(maximum.to_double()),
      "version": "actql-bound-witness/0.1",
    }
    match listing_wire_candidate(body) {
      Ok(value) => candidates.push(value)
      Err(issue) => return Err(issue)
    }
  }
  if policy is Some(policy) &&
    @policy.ceiling(policy, "max_file_listing_items") is Some(ceiling) {
    let host = match
      @bound_host.create(ceiling, {
        max_bytes: listing_record_bytes,
        max_nodes: 2000,
        max_depth: 32,
      }) {
      Ok(value) => value
      Err(_) => return Err(Unresolved)
    }
    let candidate = try {
      let writer = @encode.writer(listing_record_bytes, 2000, 32)
      @bound_host.emit(host, writer)
      @bound_wire.admit(
        @utf8.encode(@encode.finish(writer)),
        @bound_host.cid(host),
        { max_bytes: listing_record_bytes, max_nodes: 2000, max_depth: 32, },
      )
    } catch {
      _ => return Err(Unresolved)
    }
    match candidate {
      Ok(value) => candidates.push(value)
      Err(_) => return Err(Unresolved)
    }
  }
  if candidates.is_empty() || subject.is_empty() {
    return Err(Unresolved)
  }
  candidates.sort_by((left, right) => {
    @bound_wire.cid(left).compare(@bound_wire.cid(right))
  })
  let claims = match
    @bound_wire.check_arithmetic_claims(candidates, {
      max_witnesses: 2,
      max_references: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(Unresolved)
  }
  let mut maximum = @bound_wire.value(candidates[0])
  let bodies = []
  for candidate in candidates {
    maximum = Int64::min(maximum, @bound_wire.value(candidate))
    bodies.push(
      listing_candidate_json(candidate) catch {
        _ => return Err(Unresolved)
      },
    )
  }
  let body : Json = {
    "author_guard_binding": "absent",
    "breach": "fail",
    "candidates": Json::array(bodies),
    "effective_max": Json::number(maximum.to_double()),
    "enforcement": "streaming_atomic",
    "subject_ref": Json::string(subject),
    "unit": "rows",
    "version": "actql-resolved-limit/0.1",
  }
  let (bytes, cid) = match listing_sealed_record(body, "resolved_limit_cid") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @bound_wire.admit_limit(bytes, cid, claims, {
    max_bytes: listing_record_bytes,
    max_nodes: 2000,
    max_depth: 32,
    max_candidates: 2,
  }).map_err(_ => Unresolved)
}

///|
/// Resolve the same Catalog/Host minimum for checking and actual acquisition.
/// The SourceRequest owner has already admitted the profile and its facts CID.
/// A caller cannot substitute an arbitrary facts CID through this public API.
pub fn resolve_file_listing_rows(
  profile : FileListProfile,
  policy : @policy.Policy?,
  subject : String,
) -> Result[FileListingRows, FileListingRowsIssue] {
  let mut maximum : Int64? = None
  for (quantity, value) in profile.limits {
    if quantity == "max_listing_items" {
      maximum = Some(value)
    }
  }
  resolve_listing_row_candidates(profile.facts_cid, maximum, policy, subject).map(claim => {
      profile,
      policy,
      claim,
    },
  )
}

///|
pub fn file_listing_rows_profile(value : FileListingRows) -> FileListProfile {
  value.profile
}

///|
pub fn file_listing_rows_policy(value : FileListingRows) -> @policy.Policy? {
  value.policy
}

///|
pub fn file_listing_rows_claim(
  value : FileListingRows,
) -> @bound_wire.LimitClaim {
  value.claim
}

///|
pub fn file_listing_rows_maximum(value : FileListingRows) -> Int64 {
  @listing_arithmetic.minimum_value(@bound_wire.limit_minimum(value.claim))
}

///|
/// Canonical record allowance for claims and their overlapping admission
/// writer. This is not a physical heap bound for an acquisition or matcher.
pub fn file_listing_rows_record_capacity(_ : FileListingRows) -> Int64 {
  (listing_record_bytes * 4).to_int64()
}
