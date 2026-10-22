///|
priv enum LimitBody {
  ParsedLimit(@decode.Cursor)
  ConstructedLimit(Array[WireWitness], (Int, Int), (Int, Int, Int))
}

///|
/// Construct a canonical integrity claim from candidates in the original
/// admitted arithmetic collection. This does not establish source applicability,
/// candidate completeness, authorization or physical enforcement.
/// Creation limits cover the preimage; measure_limit bounds the complete wire.
pub fn create_limit(
  claims : ArithmeticClaims,
  indices : Array[Int],
  unit : @arithmetic.BoundUnit,
  subject : String,
  enforcement : Enforcement,
  limits : LimitLimits,
) -> Result[LimitClaim, Issue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_candidates < 0 {
    return Err(InvalidLimits)
  }
  if indices.length() > limits.max_candidates {
    return Err(BudgetExceeded)
  }
  if subject.is_empty() {
    return Err(InvalidWitness)
  }
  let candidates : Array[WireWitness] = []
  let selection : Array[@arithmetic.Candidate] = []
  let mut previous = ""
  for index in indices {
    guard claims.witnesses.get(index) is Some(witness) else {
      return Err(InvalidWitness)
    }
    if witness.cid < previous {
      return Err(NoncanonicalArtifact)
    }
    previous = witness.cid
    candidates.push(witness)
    selection.push({ node: index, role: witness.role, })
  }
  let minimum = match
    @arithmetic.select_candidate_minimum(
      claim_arithmetic(claims),
      selection,
      unit,
      max_candidates=limits.max_candidates,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidWitness)
  }
  let pending : LimitClaim = {
    nodes: 0,
    body: ConstructedLimit(candidates, (0, 0), (0, 0, 0)),
    claims,
    minimum,
    identity: "",
    subject,
    enforcement,
  }
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_constructed_limit(pending, candidates, writer, false)
    let (digest, bytes, nodes, depth) = @encode.finish_hash_metrics(writer)
    // In this closed body the complete identity adds exactly one string node
    // and 95 ASCII bytes. It adds no container or change to the peak depth.
    // Retain the measured preimage separately from the complete wire extent.
    if bytes > 2147483647 - 95 || nodes == 2147483647 {
      return Err(BudgetExceeded)
    }
    let extent = (bytes + 95, nodes + 1, depth)
    Ok({
      ..pending,
      nodes: nodes + 1,
      identity: "sha256:" + digest,
      body: ConstructedLimit(candidates, (bytes, nodes), extent),
    })
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
fn constructed_limit_enforcement(value : Enforcement) -> String {
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
fn emit_constructed_limit(
  claim : LimitClaim,
  candidates : Array[WireWitness],
  writer : @encode.Writer,
  include_identity : Bool,
) -> Unit raise @encode.EncodeFailure {
  let binding = match @arithmetic.minimum_guard_binding(claim.minimum) {
    Absent => "absent"
    Binding => "binding"
    CurrentlyNonBinding => "currently_non_binding"
  }
  @encode.begin_object(writer)
  @encode.key(writer, "author_guard_binding")
  @encode.string_value(writer, binding)
  @encode.key(writer, "breach")
  @encode.string_value(writer, "fail")
  @encode.key(writer, "candidates")
  @encode.begin_array(writer)
  for candidate in candidates {
    emit(candidate, writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "effective_max")
  @encode.number_value(
    writer,
    @arithmetic.minimum_value(claim.minimum).to_double(),
  )
  @encode.key(writer, "enforcement")
  @encode.string_value(writer, constructed_limit_enforcement(claim.enforcement))
  if include_identity {
    @encode.key(writer, "resolved_limit_cid")
    @encode.string_value(writer, claim.identity)
  }
  @encode.key(writer, "subject_ref")
  @encode.string_value(writer, claim.subject)
  @encode.key(writer, "unit")
  @encode.string_value(
    writer,
    host_source_unit_text(@arithmetic.minimum_unit(claim.minimum)),
  )
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-resolved-limit/0.1")
  @encode.end_object(writer)
}

///|
/// Actual creation usage is available only for an originally constructed claim.
/// Reading this tuple is not wire admission or a source/permission proof.
pub fn limit_creation_usage(claim : LimitClaim) -> (Int, Int)? {
  match claim.body {
    ParsedLimit(_) => None
    ConstructedLimit(_, usage, _) => Some(usage)
  }
}

///|
/// Check the exact complete wire extent against the current output limits.
/// Constructed claims retain the extent from their canonical preimage; parsed
/// claims still use the ordinary bounded emitter when measurement is requested.
pub fn measure_limit(
  claim : LimitClaim,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (Int, Int, Int) raise @encode.EncodeFailure {
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    raise @encode.OutputLimit
  }
  match claim.body {
    ConstructedLimit(_, _, extent) => {
      if extent.0 > max_bytes || extent.1 > max_nodes || extent.2 > max_depth {
        raise @encode.OutputLimit
      }
      extent
    }
    ParsedLimit(_) => {
      let writer = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
      emit_limit(claim, writer)
      @encode.finish_measurement_usage(writer)
    }
  }
}

///|
fn limit_body_bytes(claim : LimitClaim) -> Int {
  match claim.body {
    ParsedLimit(cursor) => {
      let span = @decode.cursor_span(cursor)
      span.end_byte - span.start_byte
    }
    ConstructedLimit(_, _, extent) => extent.0
  }
}
