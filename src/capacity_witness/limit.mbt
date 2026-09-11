///|
pub(all) enum Enforcement {
  Static
  UnitPreflight
  BeforeProviderDispatch
  BeforeEffectCommit
  StreamingAtomic
  EngineAtomic
} derive(Eq, Debug)

///|
/// Canonical limit assertions linked to arithmetic, not a runnable permission.
struct LimitClaim {
  nodes : Int
  cursor : @decode.Cursor
  claims : ArithmeticClaims
  minimum : @arithmetic.CandidateMinimum
  identity : String
  subject : String
  enforcement : Enforcement
}

///|
pub(all) struct LimitLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_candidates : Int
}

///|
fn enforcement(name : String) -> Enforcement raise Stop {
  match name {
    "static" => Static
    "unit_preflight" => UnitPreflight
    "before_provider_dispatch" => BeforeProviderDispatch
    "before_effect_commit" => BeforeEffectCommit
    "streaming_atomic" => StreamingAtomic
    "engine_atomic" => EngineAtomic
    _ => raise Stop(InvalidWitness)
  }
}

///|
fn limit_emit(
  root : @decode.Cursor,
  writer : @encode.Writer,
  omit : Bool,
) -> Unit raise @encode.EncodeFailure {
  let object = @decode.open_object(root).unwrap()
  // The root shape is closed; nested candidates are compared to admitted bodies.
  @encode.begin_object(writer)
  for
    name in [
      "author_guard_binding", "breach", "candidates", "effective_max", "enforcement",
      "resolved_limit_cid", "subject_ref", "unit", "version",
    ] {
    if omit && name == "resolved_limit_cid" {
      continue
    }
    @encode.key(writer, name)
    emit_cursor(@decode.lookup(object, name).unwrap(), writer, false)
  }
  @encode.end_object(writer)
}

///|
/// All embedded candidates must match admitted witnesses in the supplied graph.
/// Does not prove candidate completeness, source truth or enforcement suitability.
pub fn admit_limit(
  bytes : Bytes,
  expected_cid : String,
  claims : ArithmeticClaims,
  limits : LimitLimits,
) -> Result[LimitClaim, Issue] {
  try {
    if limits.max_bytes < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_candidates < 0 {
      raise Stop(InvalidLimits)
    }
    if bytes.length() > limits.max_bytes {
      raise Stop(BudgetExceeded)
    }
    if !valid_cid(expected_cid) {
      raise Stop(IdentityMismatch)
    }
    let parsed = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: limits.max_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) =>
        match e.issue {
          InputLimit | NodeLimit | DepthLimit => raise Stop(BudgetExceeded)
          _ => raise Stop(InvalidWitness)
        }
    }
    let root = match
      @decode.admit(parsed, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_bytes,
        max_total_string_bytes: limits.max_bytes,
      }) {
      Ok(v) => v
      Err(_) => raise Stop(BudgetExceeded)
    }
    let object = get(
      @decode.closed_object(root, [
        "version", "subject_ref", "unit", "candidates", "effective_max", "author_guard_binding",
        "enforcement", "breach", "resolved_limit_cid",
      ]),
    )
    if text(object, "version") != "actql-resolved-limit/0.1" ||
      text(object, "breach") != "fail" {
      raise Stop(InvalidWitness)
    }
    if identity(object, "resolved_limit_cid") != expected_cid {
      raise Stop(IdentityMismatch)
    }
    let subject = nonempty(object, "subject_ref")
    let unit = read_unit(text(object, "unit"))
    let enforcement = enforcement(text(object, "enforcement"))
    let raw = get(@decode.elements(get(@decode.required(object, "candidates"))))
    if raw.length() > limits.max_candidates {
      raise Stop(BudgetExceeded)
    }
    let candidates : Array[@arithmetic.Candidate] = []
    let mut previous = ""
    for candidate in raw {
      let o = get(@decode.open_object(candidate))
      let cid = identity(o, "witness_cid")
      if cid < previous {
        raise Stop(NoncanonicalArtifact)
      }
      previous = cid
      guard claim_index(claims, cid) is Some(index) else {
        raise Stop(InvalidWitness)
      }
      let witness = claims.witnesses[index]
      if !same_cursor(candidate, witness.cursor) {
        raise Stop(InvalidWitness)
      }
      candidates.push({ node: index, role: witness.role, })
    }
    let minimum = match
      @arithmetic.select_candidate_minimum(
        claim_arithmetic(claims),
        candidates,
        unit,
        max_candidates=limits.max_candidates,
      ) {
      Ok(v) => v
      Err(_) => raise Stop(InvalidWitness)
    }
    let binding = match @arithmetic.minimum_guard_binding(minimum) {
      Absent => "absent"
      Binding => "binding"
      CurrentlyNonBinding => "currently_non_binding"
    }
    if number(object, "effective_max") != @arithmetic.minimum_value(minimum) ||
      text(object, "author_guard_binding") != binding {
      raise Stop(InvalidWitness)
    }
    let nodes = try {
      let hash = @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      limit_emit(root, hash, true)
      if "sha256:" + @encode.finish_hash(hash) != expected_cid {
        raise Stop(IdentityMismatch)
      }
      let full = @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      limit_emit(root, full, false)
      let (hash, _, nodes) = @encode.finish_hash_usage(full)
      if hash != @sha.hex(bytes) {
        raise Stop(NoncanonicalArtifact)
      }
      nodes
    } catch {
      Stop(e) => raise Stop(e)
      _ => raise Stop(BudgetExceeded)
    }
    Ok({
      nodes,
      cursor: root,
      claims,
      minimum,
      identity: expected_cid,
      subject,
      enforcement,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
// Iterative exact comparison before emitting untrusted nested candidate bodies.
fn same_cursor(a : @decode.Cursor, b : @decode.Cursor) -> Bool {
  let pending = [(a, b)]
  while !pending.is_empty() {
    let (left, right) = pending.pop().unwrap()
    match (@decode.view(left), @decode.view(right)) {
      (TextValue(a), TextValue(b)) => if a != b { return false }
      (NumberValue(a), NumberValue(b)) => if a != b { return false }
      (ArrayValue(a), ArrayValue(b)) => {
        if a.length() != b.length() {
          return false
        }
        for i in 0..<a.length() {
          pending.push((a[i], b[i]))
        }
      }
      (ObjectValue(a), ObjectValue(b)) => {
        let names = @decode.object_field_names(left).unwrap()
        if names.length() != @decode.object_field_names(right).unwrap().length() {
          return false
        }
        for name in names {
          guard @decode.lookup(b, name) is Some(value) else { return false }
          pending.push((@decode.lookup(a, name).unwrap(), value))
        }
      }
      _ => return false
    }
  }
  true
}

///|
pub fn limit_claims(v : LimitClaim) -> ArithmeticClaims {
  v.claims
}

///|
pub fn limit_minimum(v : LimitClaim) -> @arithmetic.CandidateMinimum {
  v.minimum
}

///|
pub fn limit_cid(v : LimitClaim) -> String {
  v.identity
}

///|
pub fn limit_subject(v : LimitClaim) -> String {
  v.subject
}

///|
pub fn limit_enforcement(v : LimitClaim) -> Enforcement {
  v.enforcement
}

///|
pub fn emit_limit(
  v : LimitClaim,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  limit_emit(v.cursor, writer, false)
}
