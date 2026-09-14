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
  meter? : ValuesMetadataBudget? = None,
) -> Result[@wire.LimitClaim?, ValuesPublicationIssue] {
  if recursive.selected_fields == 0 {
    return Ok(None)
  }
  let host = match
    @host.create(recursive.byte_ceiling, {
      max_bytes: values_metadata_bytes(meter, limits),
      max_nodes: values_metadata_nodes(meter, limits),
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
    reserve_values_metadata(meter, limits, out => @host.emit(host, out))
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
    reserve_values_metadata(meter, limits, out => {
      emit(Some(values_metadata_cid), out)
    })
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
/// measurement passes. Metadata is accounted once per complete artifact (embedded
/// copies included), separately from payload usage; its nodes also consume work.
/// total_limits, when supplied, bounds payload plus metadata across all visits.
/// Per-artifact caps remain independent. No successful execution
/// or backend support is claimed by the returned future-check bindings.
pub fn resolve_program_values_resources(
  index : ProgramOperationResolutionIndex,
  limits : ValuesPublicationLimits,
  total_limits? : @wire.Limits? = None,
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
  let total = total_limits.unwrap_or({
    max_bytes: 2147483647,
    max_nodes: 2147483647,
    max_depth: limits.max_depth,
  })
  if total.max_bytes < 0 || total.max_nodes < 0 || total.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if index.values_bytes > total.max_bytes ||
    index.values_nodes > total.max_nodes ||
    index.values_metadata_bytes > total.max_bytes - index.values_bytes ||
    index.values_metadata_nodes > total.max_nodes - index.values_nodes {
    return Err(BudgetExceeded)
  }
  let meter : ValuesMetadataBudget = {
    bytes: total.max_bytes - index.values_bytes - index.values_metadata_bytes,
    nodes: (total.max_nodes - index.values_nodes - index.values_metadata_nodes).min(
      limits.max_work - work,
    ),
    used_bytes: 0,
    used_nodes: 0,
  }
  let metadata : @wire.LimitLimits = {
    ..limits.metadata,
    max_depth: limits.metadata.max_depth.min(total.max_depth),
  }
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
    meter.nodes = meter.nodes.min(limits.max_work - work)
    let metadata_before = meter.used_nodes
    let wire = match
      resolve_values_wire_limit_metered(
        cells,
        i,
        {
          max_bytes: bytes.min(meter.bytes),
          max_nodes: nodes.min(meter.nodes),
          max_depth: limits.max_depth.min(total.max_depth),
        },
        metadata,
        Some(meter),
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
    let rows = match
      resolve_values_row_limit_metered(wire, metadata, Some(meter)) {
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
        nodes.min(meter.nodes),
        bytes.min(meter.bytes),
        limits.max_depth.min(total.max_depth),
      ) {
      Ok(v) => v
      Err(e) => return Err(Recursive(i, e))
    }
    bytes -= recursive.bytes
    nodes -= recursive.work
    work += recursive.work
    meter.bytes -= recursive.bytes
    meter.nodes -= recursive.work
    let recursive_limit = match
      values_recursive_limit(recursive, metadata, meter=Some(meter)) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    work += meter.used_nodes - metadata_before
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
    values_metadata_bytes: index.values_metadata_bytes + meter.used_bytes,
    values_metadata_nodes: index.values_metadata_nodes + meter.used_nodes,
  })
}
