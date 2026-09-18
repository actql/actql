///|
pub(all) struct ResolvedLimitRequest {
  subject : String
  candidates : Array[@wire.ProgramProofClaim]
}

///|
pub(all) struct ResolvedLimitLimits {
  max_work : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum ResolvedLimitIssue {
  InvalidLimits
  BudgetExceeded
  MissingCandidate(Int, Int)
  InvalidCandidate(Int, Int)
  ConflictingHostClaim
  Host(Issue)
  Wire(@wire.Issue)
  Mixed(@wire.MixedIssue)
  Program(@wire.ProgramClosureIssue)
  Encoding(@encode.EncodeFailure)
} derive(Debug)

///|
priv suberror ResolvedLimitStop {
  ResolvedLimitStop(ResolvedLimitIssue)
}

///|
struct ResolvedLimitExtension {
  sources : HostSources
  limits : Array[@wire.LimitClaim]
  first_index : Int
  work : Int
  bytes : Int
  nodes : Int
}

///|
fn resolved_enforcement_text(value : @wire.Enforcement) -> String {
  match value {
    Static => "static"
    UnitPreflight => "unit_preflight"
    BeforeProviderDispatch => "before_provider_dispatch"
    BeforeEffectCommit => "before_effect_commit"
    StreamingAtomic => "streaming_atomic"
    EngineAtomic => "engine_atomic"
  }
}

///|
fn resolved_unit_text(value : @derivation.BoundUnit) -> String {
  match value {
    Rows => "rows"
    DistinctKeys => "distinct_keys"
    EffectItems => "effect_items"
    Bytes => "bytes"
    ArrayItems => "array_items"
    Nodes => "nodes"
    Edges => "edges"
    Paths => "paths"
    MatchesPerKey => "matches_per_key"
  }
}

///|
fn emit_resolved_limit(
  candidates : Array[@wire.WireWitness],
  subject : String,
  enforcement : @wire.Enforcement,
  identity : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let mut maximum = @wire.value(candidates[0])
  for candidate in candidates {
    maximum = Int64::min(maximum, @wire.value(candidate))
  }
  @encode.begin_object(writer)
  @encode.key(writer, "author_guard_binding")
  @encode.string_value(writer, "absent")
  @encode.key(writer, "breach")
  @encode.string_value(writer, "fail")
  @encode.key(writer, "candidates")
  @encode.begin_array(writer)
  for candidate in candidates {
    @wire.emit(candidate, writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "effective_max")
  @encode.number_value(writer, maximum.to_double())
  @encode.key(writer, "enforcement")
  @encode.string_value(writer, resolved_enforcement_text(enforcement))
  if identity is Some(identity) {
    @encode.key(writer, "resolved_limit_cid")
    @encode.string_value(writer, identity)
  }
  @encode.key(writer, "subject_ref")
  @encode.string_value(writer, subject)
  @encode.key(writer, "unit")
  @encode.string_value(writer, resolved_unit_text(@wire.unit(candidates[0])))
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-resolved-limit/0.1")
  @encode.end_object(writer)
}

///|
fn emit_limit_bytes(
  candidates : Array[@wire.WireWitness],
  subject : String,
  enforcement : @wire.Enforcement,
  limits : ResolvedLimitLimits,
) -> (Bytes, String, Int, Int) raise @encode.EncodeFailure {
  let hash = @encode.hashing_writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  emit_resolved_limit(candidates, subject, enforcement, None, hash)
  let (digest, _, _) = @encode.finish_hash_usage(hash)
  let identity = "sha256:" + digest
  let measured = @encode.hashing_writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  emit_resolved_limit(
    candidates,
    subject,
    enforcement,
    Some(identity),
    measured,
  )
  let (_, bytes, nodes) = @encode.finish_hash_usage(measured)
  let output = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  emit_resolved_limit(candidates, subject, enforcement, Some(identity), output)
  (@utf8.encode(@encode.finish(output)), identity, bytes, nodes)
}

///|
fn emit_prior_limit_bytes(
  value : @wire.LimitClaim,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bytes raise @encode.EncodeFailure {
  let output = @encode.writer(max_bytes, max_nodes, max_depth)
  @wire.emit_limit(value, output)
  @utf8.encode(@encode.finish(output))
}

///|
fn host_wire(
  witness : Witness,
  limits : ResolvedLimitLimits,
) -> (@wire.WireWitness, Int, Int) raise ResolvedLimitStop {
  let measured = @encode.hashing_writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    issue => raise ResolvedLimitStop(Encoding(issue))
  }
  emit(witness, measured) catch {
    issue => raise ResolvedLimitStop(Encoding(issue))
  }
  let (_, bytes, nodes) = @encode.finish_hash_usage(measured) catch {
    issue => raise ResolvedLimitStop(Encoding(issue))
  }
  let output = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    issue => raise ResolvedLimitStop(Encoding(issue))
  }
  emit(witness, output) catch {
    issue => raise ResolvedLimitStop(Encoding(issue))
  }
  let encoded = @encode.finish(output) catch {
    issue => raise ResolvedLimitStop(Encoding(issue))
  }
  let wire = match
    @wire.admit(@utf8.encode(encoded), cid(witness), {
      max_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) => raise ResolvedLimitStop(Wire(issue))
  }
  (wire, bytes, nodes)
}

///|
/// Add compiler-selected Host limits to one owned source collection. Existing
/// claim handles, source ownership and dependency owners are retained. The
/// request candidates must be exact Program proofs already in the collection.
/// All limits are rebuilt once so a Stage with several joins does not repeatedly
/// reconstruct the same arithmetic graph.
pub fn extend_resolved_limits(
  original : HostSources,
  selected_ceiling : @policy.Ceiling,
  requests : Array[ResolvedLimitRequest],
  enforcement : @wire.Enforcement,
  limits : ResolvedLimitLimits,
) -> Result[ResolvedLimitExtension, ResolvedLimitIssue] {
  if limits.max_work < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if requests.is_empty() {
    return Ok({
      sources: original,
      limits: [],
      first_index: original.local_limits,
      work: 0,
      bytes: 0,
      nodes: 0,
    })
  }
  let mut remaining = limits.max_work
  fn spend(amount : Int) -> Unit raise ResolvedLimitStop {
    if amount < 0 || amount > remaining {
      raise ResolvedLimitStop(BudgetExceeded)
    }
    remaining -= amount
  }
  try {
    spend(1)
    let host = match
      create(selected_ceiling, {
        max_bytes: limits.max_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(value) => value
      Err(issue) => raise ResolvedLimitStop(Host(issue))
    }
    let (wire_host, host_bytes, host_nodes) = host_wire(host, limits)
    let prior = original.claims
    let arithmetic = @wire.program_claim_arithmetic(prior)
    let count = @wire.claim_count(arithmetic)
    spend(count)
    let witnesses : Array[@wire.WireWitness] = []
    for index in 0..<count {
      witnesses.push(@wire.claim_at(arithmetic, index).unwrap())
    }
    let host_index = @wire.claim_index(arithmetic, @wire.cid(wire_host))
    let mut added_host = false
    match host_index {
      Some(index) => {
        guard source_at(original, index) is Some(existing) &&
          physical_equal(
            @policy.ceiling_policy(ceiling(existing)),
            @policy.ceiling_policy(selected_ceiling),
          ) else {
          raise ResolvedLimitStop(ConflictingHostClaim)
        }
      }
      None => {
        witnesses.push(wire_host)
        added_host = true
      }
    }
    let candidate_sets : Array[Array[@wire.WireWitness]] = []
    for request_index, request in requests {
      spend(1)
      spend(request.subject.length())
      let candidates = [wire_host]
      for candidate_index, proof in request.candidates {
        spend(1)
        let wire = @wire.program_proof_witness(proof)
        guard @wire.claim_index(arithmetic, @wire.cid(wire)) is Some(index) &&
          @wire.program_claim_proof_at(prior, index) is Some(owned) &&
          physical_equal(owned, proof) else {
          raise ResolvedLimitStop(
            MissingCandidate(request_index, candidate_index),
          )
        }
        if @wire.unit(wire) != unit(host) ||
          @wire.role(wire) != @derivation.ProvenUpperBound {
          raise ResolvedLimitStop(
            InvalidCandidate(request_index, candidate_index),
          )
        }
        candidates.push(wire)
      }
      candidates.sort_by((left, right) => {
        @wire.cid(left).compare(@wire.cid(right))
      })
      candidate_sets.push(candidates)
    }
    let old_mixed = @wire.program_claim_mixed(prior).unwrap()
    let old_limits = @wire.mixed_limit_count(old_mixed)
    spend(old_limits)
    let (_, old_bytes, old_nodes) = @wire.mixed_usage(old_mixed)
    if old_bytes > 2147483647 - limits.max_bytes ||
      old_nodes > 2147483647 - limits.max_nodes {
      raise ResolvedLimitStop(BudgetExceeded)
    }
    let total_bytes = old_bytes + limits.max_bytes
    let total_nodes = old_nodes + limits.max_nodes
    let artifacts : Array[(Bytes, String)] = []
    for index in 0..<original.local_limits {
      let prior_limit = @wire.mixed_limit_at(old_mixed, index).unwrap()
      let bytes = emit_prior_limit_bytes(
        prior_limit,
        total_bytes,
        total_nodes,
        limits.max_depth,
      ) catch {
        issue => raise ResolvedLimitStop(Encoding(issue))
      }
      artifacts.push((bytes, @wire.limit_cid(prior_limit)))
    }
    let mut metadata_bytes = if added_host { host_bytes } else { 0 }
    let mut metadata_nodes = if added_host { host_nodes } else { 0 }
    for index, request in requests {
      let (bytes, identity, used_bytes, used_nodes) = emit_limit_bytes(
        candidate_sets[index],
        request.subject,
        enforcement,
        limits,
      ) catch {
        issue => raise ResolvedLimitStop(Encoding(issue))
      }
      if used_bytes > limits.max_bytes - metadata_bytes ||
        used_nodes > limits.max_nodes - metadata_nodes {
        raise ResolvedLimitStop(BudgetExceeded)
      }
      metadata_bytes += used_bytes
      metadata_nodes += used_nodes
      artifacts.push((bytes, identity))
    }
    for index in original.local_limits..<old_limits {
      let prior_limit = @wire.mixed_limit_at(old_mixed, index).unwrap()
      let bytes = emit_prior_limit_bytes(
        prior_limit,
        total_bytes,
        total_nodes,
        limits.max_depth,
      ) catch {
        issue => raise ResolvedLimitStop(Encoding(issue))
      }
      artifacts.push((bytes, @wire.limit_cid(prior_limit)))
    }
    spend(witnesses.length())
    spend(artifacts.length())
    let mixed = match
      @wire.check_mixed_claims(witnesses, artifacts, {
        max_entities: limits.max_work,
        max_references: limits.max_work,
        max_bytes: total_bytes,
        max_nodes: total_nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(value) => value
      Err(issue) => raise ResolvedLimitStop(Mixed(issue))
    }
    let proofs : Array[@wire.ProgramProofClaim] = []
    spend(count)
    for index in 0..<count {
      if @wire.program_claim_proof_at(prior, index) is Some(proof) {
        proofs.push(proof)
      }
    }
    let claims = match
      @wire.check_mixed_program_claims(mixed, proofs, {
        max_witnesses: limits.max_work,
        max_references: limits.max_work,
      }) {
      Ok(value) => value
      Err(issue) => raise ResolvedLimitStop(Program(issue))
    }
    let retained = original.sources.copy()
    if added_host {
      retained.push(Some(host))
    }
    let resolved : Array[@wire.LimitClaim] = []
    for index in 0..<requests.length() {
      resolved.push(
        @wire.mixed_limit_at(mixed, original.local_limits + index).unwrap(),
      )
    }
    Ok({
      sources: {
        ..original,
        claims,
        sources: retained,
        count: original.count + (if added_host { 1 } else { 0 }),
        bytes: original.bytes + (if added_host { host_bytes } else { 0 }),
        nodes: original.nodes + (if added_host { host_nodes } else { 0 }),
        local_limits: original.local_limits + requests.length(),
      },
      limits: resolved,
      first_index: original.local_limits,
      work: limits.max_work - remaining,
      bytes: metadata_bytes,
      nodes: metadata_nodes,
    })
  } catch {
    ResolvedLimitStop(issue) => Err(issue)
  }
}

///|
pub fn resolved_limit_sources(v : ResolvedLimitExtension) -> HostSources {
  v.sources
}

///|
pub fn resolved_limit_count(v : ResolvedLimitExtension) -> Int {
  v.limits.length()
}

///|
pub fn resolved_limit_at(
  v : ResolvedLimitExtension,
  index : Int,
) -> @wire.LimitClaim? {
  v.limits.get(index)
}

///|
pub fn resolved_limit_index(v : ResolvedLimitExtension, index : Int) -> Int? {
  if index < 0 || index >= v.limits.length() {
    None
  } else {
    Some(v.first_index + index)
  }
}

///|
pub fn resolved_limit_usage(v : ResolvedLimitExtension) -> (Int, Int, Int) {
  (v.work, v.bytes, v.nodes)
}
