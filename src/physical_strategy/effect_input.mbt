///|
/// One checked Effect source occurrence and its exact captured output. The
/// ordinary task port may close while this owner is live. Resident material
/// remains with the installed Host; this neither copies rows nor permits apply.
struct CapturedEffectInput {
  source : CheckedEffectSourcePort
  borrow : CapturedAnyResultBorrow
}

///|
/// One Effect Run's complete source inventory. Members without a Result
/// source retain their position but require no pin. The source inventory is
/// derived from the checked graph, never supplied by a caller.
struct CapturedEffectInputs {
  run : CapturedEffectRunDAG
  entries : Array[CapturedEffectInput?]
  local_results : Array[CapturedEffectLocalResult]
  pins : CapturedAnyResultOutputSet
  mut live : Bool
}

///|
/// A checked private Preview paired with the live captured inputs of its
/// exact Run. Preview order is mapped back to authored Effect occurrences.
/// This is input custody, not Artifact evidence or mutation authority.
struct CapturedEffectPreviewInputs {
  preview : @checked.EffectProgramRunPreview
  inputs : CapturedEffectInputs
  source_indexes : Array[Int?]
}

///|
/// Pin all Result-consuming members as one custody step. A later missing,
/// foreign, or over-limit source cannot strand earlier consumer holdings.
pub fn pin_captured_effect_sources(
  run : CapturedEffectRunDAG,
  max_pins : Int,
  max_dependency_work? : Int = 65536,
  max_dependency_depth? : Int = 64,
) -> Result[CapturedEffectInputs, RunIssue] {
  let local_ports = match
    effect_dependency_ports(
      run.checked.computation,
      Int::min(max_pins, 4096),
      max_dependency_work,
      max_dependency_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let requests : Array[(Int, @execution.ManagedResultOccurrence)] = []
  let sources : Array[CheckedEffectSourcePort?] = []
  let indexes : Map[String, Int] = Map([])
  for index in 0..<captured_effect_run_source_count(run) {
    let source = captured_effect_run_source_at(run, index)
    if source is Some(source) {
      if source.member_index != index {
        return Err(ForeignCandidate)
      }
      indexes[source.stage.to_string() +
      "/" +
      @execution.managed_result_occurrence_name(source.occurrence)] = requests.length()
      requests.push((source.task, source.occurrence))
    }
    sources.push(source)
  }
  let local_indexes : Array[Int] = []
  for port in local_ports {
    let key = port.stage.to_string() +
      "/" +
      @execution.managed_result_occurrence_name(port.occurrence)
    match indexes.get(key) {
      Some(index) => local_indexes.push(index)
      None => {
        let index = requests.length()
        indexes[key] = index
        local_indexes.push(index)
        requests.push((port.task, port.occurrence))
      }
    }
  }
  let pins = match
    pin_captured_any_result_output_set(run.captured, requests, max_pins) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let entries : Array[CapturedEffectInput?] = []
  let mut pin_index = 0
  for source in sources {
    match source {
      Some(source) => {
        let borrow = captured_any_result_output_set_borrow_at(pins, pin_index).unwrap()
        entries.push(Some({ source, borrow, }))
        pin_index += 1
      }
      None => entries.push(None)
    }
  }
  let local_results : Array[CapturedEffectLocalResult] = []
  for index in 0..<local_ports.length() {
    let port = local_ports[index]
    local_results.push({
      stage: port.stage,
      task: port.task,
      borrow: captured_any_result_output_set_borrow_at(
        pins,
        local_indexes[index],
      ).unwrap(),
    })
  }
  Ok({ run, entries, local_results, pins, live: true, })
}

///|
/// Resolve Preview members to the checked source inventory without accepting
/// a caller-supplied index or matching equal-CID but foreign Run owners.
pub fn checked_effect_preview_source_indexes(
  run : CheckedEffectRunDAG,
  preview : @checked.EffectProgramRunPreview,
  max_work : Int,
) -> Result[Array[Int?], RunIssue] {
  if max_work < 0 {
    return Err(PreviewWorkLimit)
  }
  if !physical_equal(
      run.run,
      @checked.effect_program_run_preview_owner(preview),
    ) {
    return Err(ForeignCandidate)
  }
  let stage = @checked.effect_program_run_preview_stage(preview)
  let identity = @checked.effect_program_run_preview_identity(preview)
  let headers = @checked.effect_program_static_headers(
    @checked.effect_program_run_static_candidate(run.run),
  )
  let mut remaining = max_work
  let member_indexes : Map[String, Int] = Map([])
  for index in 0..<@syntax.effect_header_count(headers) {
    if remaining == 0 {
      return Err(PreviewWorkLimit)
    }
    remaining -= 1
    let header = @syntax.effect_header_at(headers, index).unwrap()
    if @syntax.effect_header_stage(header) == stage {
      member_indexes[@syntax.effect_header_id(header)] = index
    }
  }
  let indexes : Array[Int?] = []
  for preview_index in 0..<@publication.effect_preview_member_count(identity) {
    if remaining == 0 {
      return Err(PreviewWorkLimit)
    }
    remaining -= 1
    let id = @publication.effect_preview_member_effect_id(
      identity, preview_index,
    ).unwrap()
    guard member_indexes.get(id) is Some(index) else {
      return Err(ForeignCandidate)
    }
    let source = run.computation.sources.get(index).bind(value => value)
    let expected = @publication.effect_preview_member_source_result(
      identity, preview_index,
    )
    match source {
      Some(source) => {
        if expected !=
          Some(@execution.managed_result_occurrence_name(source.occurrence)) {
          return Err(ForeignCandidate)
        }
        indexes.push(Some(index))
      }
      None => {
        if expected is Some(_) {
          return Err(ForeignCandidate)
        }
        indexes.push(None)
      }
    }
  }
  Ok(indexes)
}

///|
/// Bind a private Preview to the already pinned inputs of the same captured
/// Run. A missing or revoked physical input cannot become Preview custody.
pub fn bind_captured_effect_preview_inputs(
  run : CapturedEffectRunDAG,
  inputs : CapturedEffectInputs,
  preview : @checked.EffectProgramRunPreview,
  max_work : Int,
) -> Result[CapturedEffectPreviewInputs, RunIssue] {
  if !physical_equal(inputs.run, run) {
    return Err(ForeignCandidate)
  }
  if !inputs.live {
    return Err(NotReady)
  }
  let indexes = match
    checked_effect_preview_source_indexes(inputs.run.checked, preview, max_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for index in indexes {
    if index is Some(index) {
      guard inputs.entries.get(index).bind(value => value) is Some(input) &&
        captured_any_result_borrow_available(input.borrow) else {
        return Err(NotReady)
      }
    }
  }
  Ok({ preview, inputs, source_indexes: indexes, })
}

///|
pub fn captured_effect_preview_owner(
  value : CapturedEffectPreviewInputs,
) -> @checked.EffectProgramRunPreview {
  value.preview
}

///|
/// The historical private Preview identity retained by the captured owner.
/// Durable progress may be reconciled after Result pins are released, but
/// this identity is not current material availability or send authority.
pub fn captured_effect_preview_ledger_identity(
  value : CapturedEffectPreviewInputs,
) -> @publication.EffectPreviewIdentity {
  @checked.effect_program_run_preview_identity(value.preview)
}

///|
pub fn captured_effect_preview_input_at(
  value : CapturedEffectPreviewInputs,
  preview_index : Int,
) -> CapturedEffectInput? {
  if !value.inputs.live {
    return None
  }
  let input = value.source_indexes
    .get(preview_index)
    .bind(index => {
      index.bind(index => value.inputs.entries.get(index).bind(entry => entry))
    })
  input.bind(input => {
    if captured_any_result_borrow_available(input.borrow) {
      Some(input)
    } else {
      None
    }
  })
}

///|
pub(all) enum CapturedEffectPlanIssue {
  InvalidMember
  NotReady
  ForeignBinding
  Plan(@results.EffectPlanBindingIssue)
} derive(Debug)

///|
/// Recover the checked Plan for a Preview member from the same captured Run
/// that owns its pinned Result. The caller cannot substitute a rule, Result
/// name, or physical producer. Row evaluation and apply remain separate.
pub fn captured_effect_preview_plan_terminal(
  value : CapturedEffectPreviewInputs,
  preview_index : Int,
  max_fields : Int,
  max_work : Int,
) -> Result[@results.EffectPlanTerminal?, CapturedEffectPlanIssue] {
  if !value.inputs.live {
    return Err(NotReady)
  }
  if max_fields < 0 || max_work < 0 {
    return Err(Plan(@results.EffectPlanBindingIssue::InvalidLimits))
  }
  guard value.source_indexes.get(preview_index) is Some(source_index) else {
    return Err(InvalidMember)
  }
  guard source_index is Some(member_index) else { return Ok(None) }
  guard captured_effect_preview_input_at(value, preview_index) is Some(input) else {
    return Err(NotReady)
  }
  let static_candidate = @checked.effect_program_run_static_candidate(
    value.inputs.run.checked.run,
  )
  let effects = @checked.effect_program_static_effects(static_candidate)
  guard @results.effect_result_binding_at(
      @results.effect_static_candidate_results(effects),
      member_index,
    )
    is Some(binding) &&
    input.source.member_index == member_index else {
    return Err(ForeignBinding)
  }
  if @syntax.effect_header_kind(@results.effect_result_binding_header(binding)) ==
    "command" {
    return Ok(None)
  }
  let rules = @results.effect_static_candidate_mapping_rules(effects)
  let terminal = match
    @results.effect_plan_terminal_for_member(
      rules, member_index, max_fields, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  if terminal is Some(terminal) &&
    @results.effect_plan_terminal_source_result(terminal) !=
    @execution.managed_result_occurrence_name(input.source.occurrence) {
    return Err(ForeignBinding)
  }
  Ok(terminal)
}

///|
pub(all) enum CapturedEffectGuardIssue {
  InvalidLimits
  NotReady
  Current(@effect.EffectPreviewTargetGuardIssue)
} derive(Debug)

///|
/// Check all current target guards while every required checked input remains
/// pinned. The caller must obtain observations under current Site authority.
/// This preflight is not a mutation permit or evidence of payload equality.
pub fn check_captured_effect_preview_target_guards(
  value : CapturedEffectPreviewInputs,
  observations : Array[@effect.EffectTargetVersionObservation],
  max_rows : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectGuardIssue] {
  if max_rows < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  if !value.inputs.live {
    return Err(NotReady)
  }
  for index in 0..<value.source_indexes.length() {
    if value.source_indexes[index] is Some(_) &&
      captured_effect_preview_input_at(value, index) is None {
      return Err(NotReady)
    }
  }
  @effect.check_effect_preview_target_guards(
    @checked.effect_program_run_preview_identity(value.preview),
    observations,
    max_rows,
    max_work,
  ).map_err(issue => Current(issue))
}

///|
pub(all) enum CapturedEffectCurrentBindingIssue {
  InvalidLimits
  CapacityExceeded
  NotReady
  InventoryMismatch
  ForeignSource(Int)
  ForeignContract(Int)
  ForeignCapability(Int)
  ForeignAuthority(Int)
} derive(Debug)

///|
/// Current physical availability is distinct from the semantic bindings in
/// an admitted Preview. A recovered Run must establish availability from its
/// retained Store holdings instead of manufacturing a live captured input.
pub fn captured_effect_preview_inputs_available(
  value : CapturedEffectPreviewInputs,
) -> Bool {
  if !value.inputs.live {
    return false
  }
  for index in 0..<value.source_indexes.length() {
    if value.source_indexes[index] is Some(_) &&
      captured_effect_preview_input_at(value, index) is None {
      return false
    }
  }
  true
}

///|
/// Compare all currently observed source, resolved Contract, capability, and
/// authority bindings against the same private Preview and captured input.
/// The Site must establish current observations under authenticated authority;
/// matching caller-supplied CIDs alone never grant an apply permit.
pub fn check_captured_effect_preview_current_bindings(
  value : CapturedEffectPreviewInputs,
  source_binding_cids : Array[String],
  resolved_contract_cids : Array[String],
  capability_evidence_cids : Array[String],
  authority_scope_cids : Array[String],
  max_members : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectCurrentBindingIssue] {
  if !captured_effect_preview_inputs_available(value) {
    return Err(NotReady)
  }
  check_effect_preview_current_bindings(
    @checked.effect_program_run_preview_identity(value.preview),
    source_binding_cids,
    resolved_contract_cids,
    capability_evidence_cids,
    authority_scope_cids,
    max_members,
    max_work,
  )
}

///|
/// Compare authenticated current observations with an admitted Preview.
/// This does not establish physical source availability or authenticate the
/// observations; the Host must prove both before any recovered send.
pub fn check_effect_preview_current_bindings(
  identity : @publication.EffectPreviewIdentity,
  source_binding_cids : Array[String],
  resolved_contract_cids : Array[String],
  capability_evidence_cids : Array[String],
  authority_scope_cids : Array[String],
  max_members : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectCurrentBindingIssue] {
  if max_members < 1 || max_members > 1000 || max_work < 1 {
    return Err(InvalidLimits)
  }
  let count = @publication.effect_preview_member_count(identity)
  if count < 1 ||
    count > max_members ||
    source_binding_cids.length() != count ||
    resolved_contract_cids.length() != count ||
    capability_evidence_cids.length() != count ||
    authority_scope_cids.length() != count {
    return Err(InventoryMismatch)
  }
  if count > max_work / 4 {
    return Err(CapacityExceeded)
  }
  for index in 0..<count {
    if @publication.effect_preview_member_source_binding_cid(identity, index) !=
      Some(source_binding_cids[index]) {
      return Err(ForeignSource(index))
    }
    if @publication.effect_preview_member_resolved_contract_cid(identity, index) !=
      Some(resolved_contract_cids[index]) {
      return Err(ForeignContract(index))
    }
    if @publication.effect_preview_member_capability_evidence_cid(
        identity, index,
      ) !=
      Some(capability_evidence_cids[index]) {
      return Err(ForeignCapability(index))
    }
    if @publication.effect_preview_member_authority_scope_cid(identity, index) !=
      Some(authority_scope_cids[index]) {
      return Err(ForeignAuthority(index))
    }
  }
  Ok(())
}

///|
pub(all) enum CapturedEffectCapabilityIssue {
  NotReady
  Current(@effect.EffectApplyCapabilityIssue)
} derive(Debug)

///|
/// Selected-route capability must be rechecked for every member while the
/// captured inputs remain available. The Site authenticates the observations;
/// this semantic check alone is not permission to send.
pub fn check_captured_effect_preview_capabilities(
  value : CapturedEffectPreviewInputs,
  observations : Array[@effect.EffectApplyCapabilityObservation],
  max_members : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectCapabilityIssue] {
  if !value.inputs.live {
    return Err(NotReady)
  }
  for index in 0..<value.source_indexes.length() {
    if value.source_indexes[index] is Some(_) &&
      captured_effect_preview_input_at(value, index) is None {
      return Err(NotReady)
    }
  }
  @effect.check_effect_preview_apply_capabilities(
    @checked.effect_program_run_preview_identity(value.preview),
    observations,
    max_members,
    max_work,
  ).map_err(issue => Current(issue))
}

///|
pub(all) enum CapturedEffectRiskIssue {
  NotReady
  Risk(@effect.EffectRiskAcceptanceIssue)
} derive(Debug)

///|
/// The risk body must name this exact live Preview. The Host authenticates
/// issuer, policy, validity, and reviewer authority before this comparison;
/// neither the transported body nor this check is a physical send permit.
/// `require_partial_application` is the Host-declared delegated-decision
/// policy, never derived from the member count.
pub fn check_captured_effect_risk_acceptance_body(
  value : CapturedEffectPreviewInputs,
  body : @effect.EffectRiskAcceptanceBody,
  review_projection_cid : String,
  authority_scope_cid : String,
  policy_cid : String,
  validity_evidence_cid : String,
  issuer_evidence_cid : String,
  authentication_evidence_cid : String,
  issuer_kind : String,
  decision : String,
  require_partial_application : Bool,
) -> Result[Unit, CapturedEffectRiskIssue] {
  if !value.inputs.live {
    return Err(NotReady)
  }
  for index in 0..<value.source_indexes.length() {
    if value.source_indexes[index] is Some(_) &&
      captured_effect_preview_input_at(value, index) is None {
      return Err(NotReady)
    }
  }
  @effect.check_effect_risk_acceptance_body(
    @checked.effect_program_run_preview_identity(value.preview),
    body,
    review_projection_cid,
    authority_scope_cid,
    policy_cid,
    validity_evidence_cid,
    issuer_evidence_cid,
    authentication_evidence_cid,
    issuer_kind,
    decision,
    require_partial_application,
  ).map_err(issue => Risk(issue))
}

///|
pub(all) enum CapturedEffectApplyKeyIssue {
  InvalidLimits
  CapacityExceeded
  NotReady
  Keys(@effect.EffectPreviewApplyIdentityIssue)
} derive(Debug)

///|
/// Check the derived keys of the whole Effect Set against the same captured
/// Preview while every required Result pin remains live. The logical request
/// scope is distinct from a physical attempt; this check does not grant apply.
pub fn check_captured_effect_preview_apply_keys(
  value : CapturedEffectPreviewInputs,
  scope : @effect.LogicalRequestScope,
  keys : Array[Array[@effect.EffectDispatchKey]],
  max_rows : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectApplyKeyIssue] {
  if !captured_effect_preview_inputs_available(value) {
    return Err(NotReady)
  }
  check_effect_preview_apply_keys(
    @checked.effect_program_run_preview_identity(value.preview),
    scope,
    keys,
    max_rows,
    max_work,
  )
}

///|
/// Check every derived dispatch key against an admitted private Preview.
/// A recovered caller must separately prove current source custody and
/// authorization; matching these keys alone never permits a physical send.
pub fn check_effect_preview_apply_keys(
  identity : @publication.EffectPreviewIdentity,
  scope : @effect.LogicalRequestScope,
  keys : Array[Array[@effect.EffectDispatchKey]],
  max_rows : Int,
  max_work : Int,
) -> Result[Unit, CapturedEffectApplyKeyIssue] {
  if max_rows < 0 || max_work < 1 {
    return Err(InvalidLimits)
  }
  let member_count = @publication.effect_preview_member_count(identity)
  if member_count > max_work / 2 {
    return Err(CapacityExceeded)
  }
  let mut remaining = max_work - 2 * member_count
  let mut total_rows = 0
  for member_index in 0..<member_count {
    let row_count = @publication.effect_preview_row_count(
      identity, member_index,
    ).unwrap()
    if row_count > max_rows - total_rows || row_count > remaining {
      return Err(CapacityExceeded)
    }
    total_rows += row_count
    remaining -= row_count
  }
  @effect.check_admitted_effect_preview_apply_keys(identity, scope, keys).map_err(issue => {
      Keys(issue)
    },
  )
}

///|
pub fn release_captured_effect_preview_inputs(
  value : CapturedEffectPreviewInputs,
) -> Bool {
  release_captured_effect_inputs(value.inputs)
}

///|
pub fn captured_effect_inputs_count(value : CapturedEffectInputs) -> Int {
  value.entries.length()
}

///|
/// A captured input inventory may issue local semantic evidence only for the
/// exact checked computation that created its physical source ports.
pub fn captured_effect_inputs_match_computation(
  value : CapturedEffectInputs,
  computation : CheckedEffectComputationDAG,
) -> Bool {
  value.live && physical_equal(value.run.checked.computation, computation)
}

///|
/// Keep the exact admitted Run with a live source pin. A matching checked
/// Program alone cannot transfer this captured input to another Run.
pub fn captured_effect_inputs_run_definition_cid(
  value : CapturedEffectInputs,
) -> String? {
  if !value.live {
    return None
  }
  Some(
    @publication.publication_contract_identity(
      @checked.effect_program_run_definition(value.run.checked.run),
    ),
  )
}

///|
/// Revoke the ordinary output port only while this checked Effect consumer
/// already owns its pin. The caller cannot close a producer merely by naming
/// a task or member before custody has been acquired.
pub fn close_captured_effect_source_port(
  value : CapturedEffectInputs,
  member_index : Int,
) -> Bool {
  if !value.live {
    return false
  }
  guard value.entries.get(member_index).bind(entry => entry) is Some(input) &&
    captured_any_result_borrow_available(input.borrow) else {
    return false
  }
  close_captured_task_output(value.run.captured, input.source.task)
  true
}

///|
pub fn captured_effect_input_at(
  value : CapturedEffectInputs,
  member_index : Int,
) -> CapturedEffectInput? {
  if !value.live {
    return None
  }
  value.entries
  .get(member_index)
  .bind(entry => entry)
  .bind(input => {
    if captured_any_result_borrow_available(input.borrow) {
      Some(input)
    } else {
      None
    }
  })
}

///|
/// Two members may consume one canonical row stream only when their checked
/// Result port, owner, name, and physical producer are the same. Their
/// publication occurrences remain distinct even when this view is shared;
/// equal names or CIDs alone cannot substitute for the owner comparison.
pub fn captured_effect_inputs_share_view(
  value : CapturedEffectInputs,
  first_index : Int,
  second_index : Int,
) -> Bool {
  guard captured_effect_input_at(value, first_index) is Some(first) &&
    captured_effect_input_at(value, second_index) is Some(second) else {
    return false
  }
  let first_occurrence = first.source.occurrence
  let second_occurrence = second.source.occurrence
  first.source.task == second.source.task &&
  @execution.managed_result_occurrence_name(first_occurrence) ==
  @execution.managed_result_occurrence_name(second_occurrence) &&
  physical_equal(
    @execution.managed_result_occurrence_owner(first_occurrence),
    @execution.managed_result_occurrence_owner(second_occurrence),
  ) &&
  physical_equal(
    @execution.managed_result_occurrence_port(first_occurrence),
    @execution.managed_result_occurrence_port(second_occurrence),
  )
}

///|
/// Revoke every consumer alias. Already returned input aliases share the
/// underlying pins and become unavailable after this release.
pub fn release_captured_effect_inputs(value : CapturedEffectInputs) -> Bool {
  if !value.live {
    return false
  }
  value.live = false
  release_captured_any_result_output_set(value.pins) |> ignore
  true
}

///|
/// Capture only the source retained by this checked Effect Run. An authored
/// name or caller-supplied output cannot replace its checked Stage Result port.
/// A resident output can be pinned here, but its concrete representation and
/// checked Result view must still be supplied before any Effect payload exists.
pub fn pin_captured_effect_source(
  run : CapturedEffectRunDAG,
  member_index : Int,
  max_pins : Int,
) -> Result[CapturedEffectInput, RunIssue] {
  guard captured_effect_run_source_at(run, member_index) is Some(source) &&
    source.member_index == member_index else {
    return Err(ForeignCandidate)
  }
  let borrow = match
    borrow_captured_any_result_output(
      run.captured,
      source.task,
      source.occurrence,
      max_pins,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ source, borrow, })
}

///|
pub fn captured_effect_input_member_index(value : CapturedEffectInput) -> Int {
  value.source.member_index
}

///|
/// The producer Task selected by the checked graph expansion. The logical
/// Stage remains on the source occurrence and must not index physical output.
pub fn captured_effect_input_task(value : CapturedEffectInput) -> Int {
  value.source.task
}

///|
pub fn captured_effect_input_stage(value : CapturedEffectInput) -> Int {
  value.source.stage
}

///|
/// The checked occurrence retains its authored Result projection and order.
pub fn captured_effect_input_occurrence(
  value : CapturedEffectInput,
) -> @execution.ManagedResultOccurrence {
  captured_any_result_borrow_occurrence(value.borrow)
}

///|
/// The borrowed producer is live only while both the original completion and
/// this Effect input pin remain live. Projection is applied by the Result view
/// preparation, not by returning a caller-defined table here.
pub fn captured_effect_input_output(
  value : CapturedEffectInput,
) -> @execution.CompletedOutput? {
  captured_any_result_borrow_cell_output(value.borrow)
}

///|
/// The Host's concrete resident output must be the same committed generation
/// that this checked Effect source pinned; an equal CID or Result name is not
/// enough. Matching does not establish a view or grant mutation authority.
pub fn[T] captured_effect_input_matches_managed(
  value : CapturedEffectInput,
  output : @execution.ManagedCompletedOutput[T],
) -> Bool {
  captured_any_result_borrow_matches_managed(value.borrow, output)
}

///|
pub fn captured_effect_input_matches_carrier(
  value : CapturedEffectInput,
  output : @execution.CarrierManagedCompletedOutput,
) -> Bool {
  captured_any_result_borrow_matches_carrier(value.borrow, output)
}

///|
/// Prepare the authored Result projection and order from this exact retained
/// Effect source. The existing bounded Result exporter owns the row traversal;
/// this port does not materialize a second table or accept caller rows. The
/// Effect input pin must remain live until the export has finished or cancelled.
/// The resulting bytes are input evidence, not an Effect Plan or apply permit.
pub fn start_captured_effect_input_export(
  value : CapturedEffectInput,
  result_view : @execution.CompletedResultViewLimits,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[
  @execution.CompletedResultRelationExportPreparation,
  @execution.CompletedExportIssue,
] {
  start_captured_any_result_borrow_export(
    value.borrow,
    result_view,
    max_rows,
    values,
    payload_wire,
    logical_wire,
    schema_limits,
    max_batch_bytes,
  )
}

///|
/// End the Effect consumer's retention once its Preview input has been safely
/// captured or abandoned. This does not acknowledge any mutation outcome.
pub fn release_captured_effect_input(value : CapturedEffectInput) -> Bool {
  release_captured_any_result_borrow(value.borrow)
}

///|
/// Sealed Effect Set Preview identity of one live captured Preview: the
/// exact decision subject for the Effect commit boundary. It is the same
/// semantic CID a risk body binds as `effect_preview_cid`. `None` once the
/// captured inputs are released. It is not a send permit.
pub fn captured_effect_preview_subject_cid(
  value : CapturedEffectPreviewInputs,
) -> String? {
  if !value.inputs.live {
    return None
  }
  Some(
    @publication.effect_preview_semantic_identity(
      @checked.effect_program_run_preview_identity(value.preview),
    ),
  )
}

///|
/// Number of members of the live captured Preview.
pub fn captured_effect_preview_member_count(
  value : CapturedEffectPreviewInputs,
) -> Int? {
  if !value.inputs.live {
    return None
  }
  Some(
    @publication.effect_preview_member_count(
      @checked.effect_program_run_preview_identity(value.preview),
    ),
  )
}
