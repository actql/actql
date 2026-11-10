///|
// Same checked Request inventories and cached input dimensions. No value/type
// checker or estimate-only input traversal is run here. Fixed control frames
// remain in the existing trusted Host overhead; variable arrays/writers use
// their original common construction owners.
fn[I] request_policy_subject_prelude_bytes(
  owner : ClientRequestPreparation[I],
  child : ClientProgramCheckPreparation[I, Unit],
  original : @checked.CheckedProgram,
  limits : @checked.CompileLimits,
) -> (Int64, Int)? {
  if limits.work < 0 || limits.artifacts.nodes < 1 || limits.artifacts.depth < 0 {
    return None
  }
  guard child.arguments is Some(_) &&
    child.check_data is Some(data) &&
    program_check_data_extent_cost(data) is Some(semantic) else {
    return None
  }
  guard request_policy_subject_prelude_inventory(
      original,
      owner.native_parameters,
      limits,
    )
    is Some((inventory, count)) &&
    @execution.preparation_representation_cost(inventory) is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, semantic, 1L)
    is Some(bytes) else {
    return None
  }
  Some((bytes, count))
}

///|
/// Same static Request hash/origin construction inventory for a trusted Host
/// restoring checked material. Completed checking DATA stays with its caller;
/// this inventory neither verifies values nor creates execution authority.
pub fn request_policy_subject_prelude_inventory(
  original : @checked.CheckedProgram,
  supplied : @decode.Cursor?,
  limits : @checked.CompileLimits,
) -> (@execution.PreparationRepresentationUnits, Int)? {
  if limits.work < 0 || limits.artifacts.nodes < 1 || limits.artifacts.depth < 0 {
    return None
  }
  let root = @syntax.program_body(@checked.checked_source_program(original))
  let p = @decode.admission_usage(root)
  let mut nodes = p.nodes.to_int64()
  let mut depth = p.depth
  if supplied is Some(parameters) {
    let supplied = @decode.admission_usage(parameters)
    nodes += supplied.nodes.to_int64()
    depth = Int::max(depth, supplied.depth)
  }
  let count = @checked.source_execution_count(original)
  let mut fields = 0L
  let mut largest = 0
  for index in 0..<count {
    let check = @checked.source_execution_at(original, index).unwrap()
    if @checked.source_execution_kind(check) is @checked.RequestEgress {
      let n = @checked.source_egress_field_count(check)
      guard @execution.checked_preparation_add_product(fields, n.to_int64(), 1L)
        is Some(total) else {
        return None
      }
      fields = total
      largest = Int::max(largest, n)
    }
  }
  // A static field may repeat any one original bound value. The complete
  // original Program plus supplied Parameter trees bound that value's nodes.
  // The descriptor has ten root/value nodes plus at most three origin nodes
  // per static field. The SAME bounded writer refuses before exceeding its
  // existing installed node/depth allowance; enumeration arrays still use
  // the actual untruncated field count below.
  guard @execution.checked_preparation_add_product(
      10L + 3L * largest.to_int64(),
      nodes,
      largest.to_int64(),
    )
    is Some(encoded_nodes) else {
    return None
  }
  let n = Int64::min(limits.artifacts.nodes.to_int64(), encoded_nodes).to_int()
  let d = Int64::min(limits.artifacts.depth.to_int64(), depth.to_int64() + 3L).to_int()
  guard @execution.checked_preparation_add_product(
      2L * n.to_int64(),
      fields,
      2L,
    )
    is Some(records) &&
    @execution.checked_preparation_add_product(4L * n.to_int64(), fields, 4L)
    is Some(references) &&
    @encode.hash_writer_construction_inventory(n, d) is Some(writer) &&
    @shape.collection_construction_extent({
      // Input-proportional origins/sort tuples and the existing value emitter's
      // pending variants/array backing. No second copy of checked values or
      // original name/Text Strings is constructed.
      records,
      record_references: references,
      record_words: 4L * n.to_int64(),
      reference_arrays: 2L * count.to_int64() + 1L,
      reference_items: records,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(arrays) &&
    Some(@execution.PreparationRepresentationUnits::{
      record_headers: writer.record_headers + arrays.record_headers,
      reference_slots: writer.reference_slots + arrays.reference_slots,
      scalar_words: writer.scalar_words + arrays.scalar_words,
      // One retained request CID per occurrence; the hash owner includes its
      // one current digest/hex peak. Original input Strings stay borrowed.
      owned_utf16_units: writer.owned_utf16_units + 71L * count.to_int64(),
      owned_wire_bytes: writer.owned_wire_bytes,
    })
    is Some(inventory) else {
    return None
  }
  Some((inventory, count))
}

///|
// Exact measured output backs the text constructor AND the trusted Host's
// descriptor parse/frozen DATA while the original wire and checked facts live.
// The shared generic JSON owner handles Unicode, keys, tree/backing overlap;
// neither a configured artifact ceiling nor an unrelated Values quote is used.
fn request_policy_subject_output_bytes(
  original : @checked.RequestPolicySubjectPreparation,
) -> Int64? {
  guard request_policy_subject_output_inventory(original) is Some(inventory) else {
    return None
  }
  @execution.preparation_representation_cost(inventory)
}

///|
/// Original measured text writer and trusted verifier parse overlap. This
/// exposes only constructor DATA, not a policy proof or physical capacity.
pub fn request_policy_subject_output_inventory(
  original : @checked.RequestPolicySubjectPreparation,
) -> @execution.PreparationRepresentationUnits? {
  let (bytes, nodes, depth) = @checked.request_policy_subject_output_extent(
    original,
  ) catch {
    _ => return None
  }
  if nodes == 0L {
    return Some({
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
  }
  guard bytes <= 2147483647L &&
    nodes <= 2147483647L &&
    @encode.text_writer_construction_inventory(
      bytes.to_int(),
      nodes.to_int(),
      depth,
    )
    is Some(writer) &&
    @source.json_construction_extent(
      bytes.to_int(),
      nodes.to_int(),
      Int::max(1, depth),
      normalize_keys=false,
    )
    is Some(parsed) &&
    Some(@execution.PreparationRepresentationUnits::{
      record_headers: writer.record_headers + parsed.record_headers,
      reference_slots: writer.reference_slots + parsed.reference_slots,
      scalar_words: writer.scalar_words + parsed.scalar_words,
      owned_utf16_units: writer.owned_utf16_units + parsed.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(inventory) else {
    return None
  }
  Some(inventory)
}

///|
/// Prepare the trusted verifier's original subjects BEFORE compilation. The
/// same Request keeps measured identity/origins, wires and one cumulative work
/// receipt across the caller's awaits. It issues no policy proof or IO grant.
pub fn[I] prepare_request_computation_policy_subjects(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  limits : @checked.CompileLimits,
) -> Result[Int, ClientRequestTerminalIssue] {
  guard owner.phase == ProgramCheck &&
    owner.input is Some(own) &&
    physical_equal(own, input) &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.phase == SemanticCheckComplete &&
    child.arguments is Some(arguments) &&
    physical_equal(arguments.environment, environment) &&
    child.policy_subjects is None &&
    child.policy_subject_work is None else {
    return Err(Preparation(ForeignOriginal))
  }
  let original = match child.effect_candidate {
    Some(effect) => @checked.effect_computation_checked_program(effect)
    None => {
      guard child.check_outcome is Some(@checked.Checked(program)) else {
        return Err(Preparation(WrongPhase))
      }
      program
    }
  }
  guard request_policy_subject_prelude_bytes(owner, child, original, limits)
    is Some((bytes, inspection)) else {
    return Err(Preparation(Policy))
  }
  owner.phase = Selecting
  child.busy = true
  preparation_module_call(
    () => {
      prepare_request_policy_subjects_owned(
        owner, input, child, original, bytes, inspection, limits,
      )
    },
    () => {
      child.busy = false
      if owner.phase == Selecting {
        child.phase = Failed
        owner.phase = ProgramCheckFailed
      }
    },
  )
}

///|
fn[I] prepare_request_policy_subjects_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  child : ClientProgramCheckPreparation[I, Unit],
  original : @checked.CheckedProgram,
  prelude_bytes : Int64,
  inspection : Int,
  limits : @checked.CompileLimits,
) -> Result[Int, ClientRequestTerminalIssue] {
  match grow_request_policy_subjects(owner, input, child, prelude_bytes) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard request_policy_subject_work_limit(inspection, limits) is Some(maximum) else {
    return Err(Preparation(Policy))
  }
  let work = match
    @resources.begin_preparation_phase_work_continuation64(
      owner.capacity,
      input,
      @resources.RequestPolicySubjectPreparation,
      maximum,
    ) {
    Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
    Ok(work) => work
  }
  child.policy_subject_work = Some(work)
  match
    @resources.spend_preparation_phase_work_continuation64(
      work,
      inspection.to_int64(),
    ) {
    Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
    Ok(_) => ()
  }
  let subjects = @checked.begin_request_policy_subjects(original, limits) catch {
    issue => return Err(Preparation(ProgramCheck(RequestPolicySubjects(issue))))
  }
  child.policy_subjects = Some(subjects)
  child.policy_subject_evidence = Some([])
  let result : Result[Unit, ClientRequestTerminalIssue] = try {
    @checked.measure_request_policy_subjects(subjects)
    Ok(())
  } catch {
    issue => Err(Preparation(ProgramCheck(RequestPolicySubjects(issue))))
  }
  match charge_request_policy_subjects(child, 0L) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match result {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard request_policy_subject_output_bytes(subjects) is Some(bytes) else {
    return Err(Preparation(Policy))
  }
  // Return the original constructor before resize/current can reenter, while
  // retaining its SAME work maximum and every completed immutable fact.
  match @resources.return_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
    Ok(_) => ()
  }
  match grow_request_policy_subjects(owner, input, child, bytes) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match @resources.resume_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
    Ok(_) => ()
  }
  let before = @checked.request_policy_subjects_spent_work(subjects)
  let result : Result[Unit, ClientRequestTerminalIssue] = try {
    @checked.construct_request_policy_subjects(subjects)
    Ok(())
  } catch {
    issue => Err(Preparation(ProgramCheck(RequestPolicySubjects(issue))))
  }
  match charge_request_policy_subjects(child, before) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match result {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match @resources.return_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
    Ok(_) => ()
  }
  owner.phase = ProgramCheck
  Ok(@checked.request_policy_subject_count(subjects))
}

///|
fn[I] grow_request_policy_subjects(
  owner : ClientRequestPreparation[I],
  input : I,
  child : ClientProgramCheckPreparation[I, Unit],
  bytes : Int64,
) -> Result[Unit, ClientRequestTerminalIssue] {
  let (r, e) = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
    return Err(Preparation(Policy))
  }
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(_) => ()
  }
  guard owner.phase == Selecting &&
    owner.input is Some(own) &&
    physical_equal(own, input) &&
    owner.program_check is Some(selected) &&
    physical_equal(selected, child) &&
    child.busy else {
    return Err(Preparation(ForeignOriginal))
  }
  Ok(())
}

///|
fn[I] charge_request_policy_subjects(
  child : ClientProgramCheckPreparation[I, Unit],
  before : Int64,
) -> Result[Unit, ClientRequestTerminalIssue] {
  let delta = @checked.request_policy_subjects_spent_work(
      child.policy_subjects.unwrap(),
    ) -
    before
  @resources.spend_preparation_phase_work_continuation64(
    child.policy_subject_work.unwrap(),
    delta,
  ).map_err(issue => Preparation(ProgramCheck(Work(issue))))
}

///|
/// Borrow already constructed immutable descriptor DATA. No current callback,
/// hash, serialization or verification is repeated by this cheap projection.
pub fn[I] request_computation_policy_subject(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  index : Int,
) -> Result[String, ClientRequestTerminalIssue] {
  guard owner.phase == ProgramCheck &&
    owner.input is Some(own) &&
    physical_equal(own, input) &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.phase == SemanticCheckComplete &&
    child.arguments is Some(arguments) &&
    physical_equal(arguments.environment, environment) &&
    child.policy_subjects is Some(subjects) &&
    child.policy_subject_work is Some(_) else {
    return Err(Preparation(ForeignOriginal))
  }
  Ok(@checked.request_policy_subject_wire(subjects, index)) catch {
    issue => Err(Preparation(ProgramCheck(RequestPolicySubjects(issue))))
  }
}

///|
/// Host-only binder after the original verifier returns. CID selects only an
/// already admitted policy for this SAME subject; None is an explicit decline.
pub fn[I] bind_request_computation_policy_subject(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
  index : Int,
  policy_cid : String?,
) -> Result[Unit, ClientRequestTerminalIssue] {
  guard owner.phase == ProgramCheck &&
    owner.input is Some(own) &&
    physical_equal(own, input) &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.phase == SemanticCheckComplete &&
    child.arguments is Some(arguments) &&
    physical_equal(arguments.environment, environment) &&
    child.policy_subjects is Some(subjects) &&
    child.policy_subject_work is Some(work) &&
    child.policy_subject_evidence is Some(evidence) else {
    return Err(Preparation(ForeignOriginal))
  }
  child.busy = true
  owner.phase = Selecting
  preparation_module_call(
    () => {
      match
        @resources.check_working_preparation_capacity_current(
          owner.capacity,
          input,
        ) {
        Err(issue) => return Err(Preparation(Capacity(issue)))
        Ok(_) => ()
      }
      // External current may synchronously reenter; retain only cheap SAME
      // owner/input/child/data fences after it, without another callback.
      guard owner.phase == Selecting &&
        owner.program_check is Some(current) &&
        physical_equal(current, child) &&
        child.busy &&
        child.policy_subjects is Some(current_subjects) &&
        physical_equal(current_subjects, subjects) &&
        owner.input is Some(own) &&
        physical_equal(own, input) else {
        return Err(Preparation(ForeignOriginal))
      }
      match @resources.resume_preparation_phase_work_continuation64(work) {
        Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
        Ok(_) => ()
      }
      let before = @checked.request_policy_subjects_spent_work(subjects)
      let result : Result[
        @checked.HostRequestValuePolicyEvidence?,
        ClientRequestTerminalIssue,
      ] = Ok(
        @checked.bind_prepared_request_policy_subject(
          subjects, index, policy_cid,
        ),
      ) catch {
        issue => Err(Preparation(ProgramCheck(RequestPolicySubjects(issue))))
      }
      match charge_request_policy_subjects(child, before) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      match result {
        Err(issue) => return Err(issue)
        Ok(Some(proof)) => evidence.push(proof)
        Ok(None) => ()
      }
      match @resources.return_preparation_phase_work_continuation64(work) {
        Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
        Ok(_) => ()
      }
      owner.phase = ProgramCheck
      Ok(())
    },
    () => {
      child.busy = false
      if owner.phase == Selecting {
        child.phase = Failed
        owner.phase = ProgramCheckFailed
      }
    },
  )
}

///|
/// Close the original subject work once and invoke the reviewed policy-only
/// supplement on the same child. No incomplete verifier inventory can compile.
pub fn[I] finish_request_computation_policy_subjects(
  owner : ClientRequestPreparation[I],
  input : I,
  environment : @checked.CheckEnvironment,
) -> Result[Unit, ClientRequestTerminalIssue] {
  guard owner.phase == ProgramCheck &&
    owner.input is Some(own) &&
    physical_equal(own, input) &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.phase == SemanticCheckComplete &&
    child.arguments is Some(arguments) &&
    physical_equal(arguments.environment, environment) &&
    child.policy_subjects is Some(subjects) &&
    child.policy_subject_work is Some(work) &&
    child.policy_subject_evidence is Some(evidence) &&
    @checked.request_policy_subject_bindings_complete(subjects) else {
    return Err(Preparation(ForeignOriginal))
  }
  match @resources.finish_preparation_phase_work_continuation64(work) {
    Err(issue) => return Err(Preparation(ProgramCheck(Work(issue))))
    Ok(_) => child.policy_subject_work = None
  }
  let result = supplement_request_computation_policies(
    owner, input, environment, evidence,
  ).map(_ => ())
  @checked.retire_request_policy_subjects(subjects)
  child.policy_subjects = None
  child.policy_subject_evidence = None
  result
}

///|
/// Existing complete subject phase: original inspection, measurement/render,
/// and each original binder's logical envelope. This is DATA for the SAME
/// parent work receipt, never another quota, refill or execution authority.
pub fn request_policy_subject_work_limit(
  inspection : Int,
  limits : @checked.CompileLimits,
) -> Int64? {
  if inspection < 0 || limits.work < 0 {
    return None
  }
  @execution.checked_preparation_add_product(
    inspection.to_int64(),
    limits.work.to_int64(),
    2L + inspection.to_int64(),
  )
}
