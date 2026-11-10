///|
// Constructor DATA for the existing trusted Host verifier. The actual Request
// parent must back inspection, measured output and the Host callback before
// entering them. This record is not a Resource owner or a policy/IO grant.
priv struct PreparedRequestPolicySubject {
  check : SourceExecution
  request_cid : String
  origins : Array[(String, RequestValuePolicyOrigin)]
  bytes : Int
  nodes : Int
  depth : Int
  mut wire : String?
}

///|
priv enum RequestPolicySubjectPhase {
  Unmeasured
  Measuring
  Measured
  Constructing
  Constructed
  Failed
  Retired
} derive(Eq)

///|
struct RequestPolicySubjectPreparation {
  mut original : CheckedProgram?
  subjects : Array[PreparedRequestPolicySubject]
  budget : IdentityBudget
  initial_work : Int
  measurement_work : Int
  cumulative_work : Int64?
  mut construction_work : Int?
  mut additional_work : Int64
  mut output_bytes : Int64
  mut output_nodes : Int64
  mut output_depth : Int
  mut next : Int
  mut phase : RequestPolicySubjectPhase
}

///|
// The same RequestEgress selection as the installed Node consumer, including
// keyed static values and unused declarations. No compiler/Plan is required.
pub fn begin_request_policy_subjects(
  original : CheckedProgram,
  limits : CompileLimits,
  cumulative_work? : Int64? = None,
) -> RequestPolicySubjectPreparation raise UnitBuildFailure {
  if !compile_limits_valid(limits) {
    raise BudgetExceeded
  }
  let measurement_work = match cumulative_work {
    None => limits.work
    Some(maximum) => {
      if maximum < 0L {
        raise BudgetExceeded
      }
      Int64::min(limits.work.to_int64(), maximum).to_int()
    }
  }
  let budget = IdentityBudget::{
    work: measurement_work,
    bytes: limits.artifacts.bytes,
    nodes: limits.artifacts.nodes,
    depth: limits.artifacts.depth,
  }
  {
    original: Some(original),
    subjects: [],
    budget,
    initial_work: limits.work,
    measurement_work,
    cumulative_work,
    construction_work: None,
    additional_work: 0L,
    output_bytes: 0L,
    output_nodes: 0L,
    output_depth: 0,
    next: 0,
    phase: Unmeasured,
  }
}

///|
/// Measure only after the original Request has backed the input-shaped hash,
/// sort and traversal workspace. Keep partial work visible on a typed failure.
pub fn measure_request_policy_subjects(
  prepared : RequestPolicySubjectPreparation,
) -> Unit raise UnitBuildFailure {
  guard prepared.phase == Unmeasured && prepared.original is Some(original) else {
    raise ForeignOwner
  }
  prepared.phase = Measuring
  errdefer {
    prepared.phase = Failed
  }
  let subjects = prepared.subjects
  let budget = prepared.budget
  let checks = original.units[0].source_execution
  identity_charge(budget, checks.length())
  for check in checks {
    guard check.kind is RequestEgress && source_egress_field_count(check) > 0 else {
      continue
    }
    let request_cid = request_value_identity(check.subject.request, budget)
    let origins = request_value_origins(check.subject.request, budget)
    let writer = @encode.measuring_writer(
      budget.bytes,
      budget.nodes,
      budget.depth,
    ) catch {
      issue => raise Encoding(issue)
    }
    emit_request_value_policy_subject(
      check, request_cid, origins, budget, writer,
    )
    let (bytes, nodes, depth) = @encode.finish_measurement_usage(writer) catch {
      issue => raise Encoding(issue)
    }
    identity_charge(budget, bytes)
    identity_charge(budget, nodes)
    // Reserve the artifact budget for these exact future outputs once.
    // Emitting them later spends work, without resetting/refilling this meter.
    budget.bytes -= bytes
    budget.nodes -= nodes
    prepared.output_bytes += bytes.to_int64()
    prepared.output_nodes += nodes.to_int64()
    prepared.output_depth = Int::max(prepared.output_depth, depth)
    subjects.push({
      check,
      request_cid,
      origins,
      bytes,
      nodes,
      depth,
      wire: None,
    })
  }
  prepared.construction_work = Some(
    prepared.measurement_work - prepared.budget.work,
  )
  prepared.phase = Measured
}

///|
// Actual encoded dimensions, before allocating any output String. This is
// DATA for the same Request grow, never a user-supplied extent or a grant.
pub fn request_policy_subject_output_extent(
  prepared : RequestPolicySubjectPreparation,
) -> (Int64, Int64, Int) raise UnitBuildFailure {
  guard prepared.phase != Retired else { raise ForeignOwner }
  (prepared.output_bytes, prepared.output_nodes, prepared.output_depth)
}

///|
// Call only after the same parent backs the measured output and the existing
// text writer. No original request hashing/origin construction is repeated.
pub fn construct_request_policy_subjects(
  prepared : RequestPolicySubjectPreparation,
) -> Unit raise UnitBuildFailure {
  guard prepared.phase == Measured else { raise ForeignOwner }
  // Consume the constructor before entry; a partial failure cannot retry or
  // replace the selected immutable request with a different measurement.
  prepared.phase = Constructing
  let allowance = request_policy_subject_call_allowance(
    prepared,
    prepared.construction_work.unwrap(),
  )
  // The same complete legacy descriptor bound has already admitted the input.
  // Its measured work bounds this additional render, excluding hashing/origins
  // that are not repeated. This is added actual work, not a refill of the
  // original semantic allowance or the Resource receipt.
  let construction = IdentityBudget::{
    work: allowance,
    bytes: prepared.output_bytes.to_int(),
    nodes: prepared.output_nodes.to_int(),
    depth: prepared.output_depth,
  }
  errdefer {
    prepared.additional_work += (allowance - construction.work).to_int64()
  }
  for subject in prepared.subjects {
    // Exact output work is known now: debit it BEFORE the String writer or
    // its emission can allocate/process the body. No refill on late failure.
    identity_charge(construction, subject.bytes)
    identity_charge(construction, subject.nodes)
    let writer = @encode.writer(subject.bytes, subject.nodes, subject.depth) catch {
      issue => raise Encoding(issue)
    }
    emit_request_value_policy_subject(
      subject.check,
      subject.request_cid,
      subject.origins,
      construction,
      writer,
    )
    let (wire, bytes, nodes, depth) = @encode.finish_text_usage(writer) catch {
      issue => raise Encoding(issue)
    }
    if bytes != subject.bytes ||
      nodes != subject.nodes ||
      depth != subject.depth {
      raise ForeignOwner
    }
    subject.wire = Some(wire)
  }
  prepared.additional_work += (allowance - construction.work).to_int64()
  prepared.phase = Constructed
}

///|
pub fn request_policy_subject_wire(
  prepared : RequestPolicySubjectPreparation,
  index : Int,
) -> String raise UnitBuildFailure {
  guard prepared.phase == Constructed &&
    prepared.subjects.get(index) is Some(subject) &&
    subject.wire is Some(wire) else {
    raise ForeignOwner
  }
  wire
}

///|
// The existing admitted-policy selector and exact issuer retain the completed
// immutable request CID/origins. The Host still verifies all contributors;
// undefined is an explicit decline, never evidence of permission or cleanup.
pub fn bind_prepared_request_policy_subject(
  prepared : RequestPolicySubjectPreparation,
  index : Int,
  policy_cid : String?,
) -> HostRequestValuePolicyEvidence? raise UnitBuildFailure {
  guard prepared.phase == Constructed &&
    index == prepared.next &&
    prepared.subjects.get(index) is Some(subject) &&
    subject.wire is Some(_) else {
    raise ForeignOwner
  }
  prepared.next += 1
  guard policy_cid is Some(cid) else { return None }
  // Preserve the existing per-binding logical refusal bound. The original
  // Request's one cumulative Resource receipt charges this actual delta too;
  // no Resource maximum, spent work or phase is reset between callbacks.
  let allowance = request_policy_subject_call_allowance(
    prepared,
    prepared.initial_work,
  )
  let binding = IdentityBudget::{
    work: allowance,
    bytes: prepared.budget.bytes,
    nodes: prepared.budget.nodes,
    depth: prepared.budget.depth,
  }
  errdefer {
    prepared.additional_work += (allowance - binding.work).to_int64()
    prepared.phase = Failed
  }
  let policy = request_value_policy_for_cid(subject.check, cid, binding)
  let environment = request_value_policy_environment(subject.check, policy)
  let proof = bind_request_value_policy_facts(
    subject.check,
    policy,
    environment,
    subject.request_cid,
    subject.origins,
  )
  prepared.additional_work += (allowance - binding.work).to_int64()
  Some(proof)
}

///|
pub fn retire_request_policy_subjects(
  prepared : RequestPolicySubjectPreparation,
) -> Unit {
  prepared.phase = Retired
  prepared.original = None
  prepared.subjects.clear()
}

///|
/// Original meter delta, including any failed measured/constructed prefix.
/// It is logical work, never CPU, physical release or verifier acceptance.
pub fn request_policy_subjects_spent_work(
  prepared : RequestPolicySubjectPreparation,
) -> Int64 {
  (prepared.measurement_work - prepared.budget.work).to_int64() +
  prepared.additional_work
}

///|
pub fn request_policy_subject_count(
  prepared : RequestPolicySubjectPreparation,
) -> Int {
  prepared.subjects.length()
}

///|
pub fn request_policy_subject_bindings_complete(
  prepared : RequestPolicySubjectPreparation,
) -> Bool {
  prepared.phase == Constructed && prepared.next == prepared.subjects.length()
}

///|
// Ordinary Request callers retain their existing cumulative Resource receipt.
// A bounded pure restoration instead shares its original derived phase limit
// across measurement, rendering and every binding, with no per-call refill.
fn request_policy_subject_call_allowance(
  prepared : RequestPolicySubjectPreparation,
  allowance : Int,
) -> Int raise UnitBuildFailure {
  guard prepared.cumulative_work is Some(maximum) else { return allowance }
  let spent = request_policy_subjects_spent_work(prepared)
  guard spent >= 0L && spent <= maximum else { raise BudgetExceeded }
  Int64::min(allowance.to_int64(), maximum - spent).to_int()
}
