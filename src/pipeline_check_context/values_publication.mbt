///|
pub struct ValuesPublicationCheck {
  site : OperationRequirementSite
  recursive : ValuesRecursiveAdmission
  recursive_limit : @wire.LimitClaim?
}

///|
pub(all) enum ValuesPublicationIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOccurrence(Int)
  RowsExceeded(Int)
  Wire(Int, ValuesWireResolutionIssue)
  Rows(Int, ValuesRowLimitIssue)
  Recursive(Int, ValuesRecursiveIssue)
  Encoding(@encode.EncodeFailure)
  Host(@host.Issue)
  Admission(@wire.Issue)
  Arithmetic(@wire.ClosureIssue)
} derive(Debug)

///|
pub(all) struct ValuesPublicationLimits {
  max_work : Int
  max_values : Int
  max_payload_bytes : Int
  max_payload_nodes : Int
  max_depth : Int
  metadata : @wire.LimitLimits
}

///|
// Only called after typed recursive admission under this exact policy owner.
// No Program law establishes a subset-cell byte witness from the complete-wire
// proof, so that proof cannot be substituted for this Host-scoped candidate.
fn values_recursive_limit(
  recursive : ValuesRecursiveAdmission,
  limits : @wire.LimitLimits,
) -> Result[@wire.LimitClaim?, ValuesPublicationIssue] {
  if recursive.selected_fields == 0 {
    return Ok(None)
  }
  let host = match
    @host.create(recursive.byte_ceiling, {
      max_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(v) => v
    Err(e) => return Err(Host(e))
  }
  fn writer(hash : Bool) -> @encode.Writer raise @encode.EncodeFailure {
    if hash {
      @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
    } else {
      @encode.writer(limits.max_bytes, limits.max_nodes, limits.max_depth)
    }
  }
  try {
    let out = writer(false)
    @host.emit(host, out)
    let witness = match
      @wire.admit(@wire_utf8.encode(@encode.finish(out)), @host.cid(host), {
        max_bytes: limits.max_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) => return Err(Admission(e))
    }
    let claims = match
      @wire.check_arithmetic_claims([witness], {
        max_witnesses: 1,
        max_references: limits.max_nodes,
      }) {
      Ok(v) => v
      Err(e) => return Err(Arithmetic(e))
    }
    fn emit(
      cid : String?,
      out : @encode.Writer,
    ) -> Unit raise @encode.EncodeFailure {
      @encode.begin_object(out)
      @encode.key(out, "author_guard_binding")
      @encode.string_value(out, "absent")
      @encode.key(out, "breach")
      @encode.string_value(out, "fail")
      @encode.key(out, "candidates")
      @encode.begin_array(out)
      @wire.emit(witness, out)
      @encode.end_array(out)
      @encode.key(out, "effective_max")
      @encode.number_value(
        out,
        @policy.ceiling_value(recursive.byte_ceiling).to_double(),
      )
      @encode.key(out, "enforcement")
      @encode.string_value(out, "engine_atomic")
      if cid is Some(cid) {
        @encode.key(out, "resolved_limit_cid")
        @encode.string_value(out, cid)
      }
      @encode.key(out, "subject_ref")
      @encode.string_value(
        out,
        "values:checked-step:" +
        recursive.rows.wire.bound.site.step.to_string() +
        ":recursive",
      )
      @encode.key(out, "unit")
      @encode.string_value(out, "bytes")
      @encode.key(out, "version")
      @encode.string_value(out, "actql-resolved-limit/0.1")
      @encode.end_object(out)
    }
    let hash = writer(true)
    emit(None, hash)
    let cid = "sha256:" + @encode.finish_hash(hash)
    let out = writer(false)
    emit(Some(cid), out)
    match
      @wire.admit_limit(
        @wire_utf8.encode(@encode.finish(out)),
        cid,
        claims,
        limits,
      ) {
      Ok(v) => Ok(Some(v))
      Err(e) => Err(Admission(e))
    }
  } catch {
    e => Err(Encoding(e))
  }
}

///|
/// Resolve every values resource occurrence in this exact index atomically.
/// Payload bytes/nodes and traversal work are shared across operations and both
/// measurement passes. Metadata ceilings apply per bounded artifact pass, with
/// max_values bounding the number of such constructions. No successful execution
/// or backend support is claimed by the returned future-check bindings.
pub fn resolve_program_values_resources(
  index : ProgramOperationResolutionIndex,
  limits : ValuesPublicationLimits,
) -> Result[ProgramOperationResolutionIndex, ValuesPublicationIssue] {
  if limits.max_work < 0 ||
    limits.max_values < 0 ||
    limits.max_payload_bytes < 0 ||
    limits.max_payload_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.metadata.max_bytes < 0 ||
    limits.metadata.max_nodes < 0 ||
    limits.metadata.max_depth < 0 ||
    limits.metadata.max_candidates < 0 {
    return Err(InvalidLimits)
  }
  let count = index.states.length()
  if index.work > limits.max_work || count > limits.max_work - index.work {
    return Err(BudgetExceeded)
  }
  let mut work = index.work + count
  if index.values_bytes > limits.max_payload_bytes ||
    index.values_nodes > limits.max_payload_nodes {
    return Err(BudgetExceeded)
  }
  let mut bytes = limits.max_payload_bytes - index.values_bytes
  let mut nodes = limits.max_payload_nodes - index.values_nodes
  let mut remaining = limits.max_values
  let states = index.states.copy()
  let mut unresolved = index.unresolved
  let cells = index.profiles.calendar.lexical.cells
  for i in 0..<count {
    let site = index.requirements.entries[i]
    guard site.requirement
      is @pipeline.ValuesRequirement(@values.ResolvePublicationResources) else {
      continue
    }
    guard states[i] is Unresolved else { return Err(ForeignOccurrence(i)) }
    if remaining == 0 || work >= limits.max_work {
      return Err(BudgetExceeded)
    }
    remaining -= 1
    work += 1
    let wire = match
      resolve_values_wire_limit(
        cells,
        i,
        {
          max_bytes: bytes,
          max_nodes: nodes.min(limits.max_work - work),
          max_depth: limits.max_depth,
        },
        limits.metadata,
      ) {
      Ok(v) => v
      Err(e) => return Err(Wire(i, e))
    }
    if !physical_equal(wire.bound.site, site) {
      return Err(ForeignOccurrence(i))
    }
    bytes -= wire.bound.bytes
    nodes -= wire.bound.nodes
    work += wire.bound.nodes
    let rows = match resolve_values_row_limit(wire, limits.metadata) {
      Ok(v) => v
      Err(e) => return Err(Rows(i, e))
    }
    if @wire.value(
        @wire.program_proof_witness(@step_bounds.checked_proof(rows.rows)),
      ) >
      @derivation.minimum_value(@wire.limit_minimum(rows.limit)) {
      return Err(RowsExceeded(i))
    }
    let recursive = match
      check_values_recursive_resources(
        rows,
        nodes.min(limits.max_work - work),
        bytes,
        limits.max_depth,
      ) {
      Ok(v) => v
      Err(e) => return Err(Recursive(i, e))
    }
    bytes -= recursive.bytes
    nodes -= recursive.work
    work += recursive.work
    let recursive_limit = match
      values_recursive_limit(recursive, limits.metadata) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    states[i] = Execution(
      ValuesPublication({ site, recursive, recursive_limit, }),
    )
    unresolved -= 1
  }
  Ok({
    profiles: index.profiles,
    requirements: index.requirements,
    states,
    unresolved,
    work,
    values_bytes: limits.max_payload_bytes - bytes,
    values_nodes: limits.max_payload_nodes - nodes,
  })
}
