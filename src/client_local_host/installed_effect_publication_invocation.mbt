///|
// Early source-free receipt: record1H3R plus its extra existing Plan field1R
// are48 retained bytes. The new outer Ok receipt carrier1H1R1W is32 bytes
// of workspace, coheld before return; the real issuer's existing tuple/Result
// remains in its original quote. Admit this SAME Request delta before issue.
fn installed_effect_early_publication_receipt_capacity() -> @execution.ExecutionCapacity {
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 1L,
      reference_slots: 4L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 1L,
      reference_slots: 1L,
      scalar_words: 1L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  }).unwrap()
}

///|
// Exact newly owned issuer carriers. Payload variants, including Some, own
// one header, one scalar tag and their payload reference under the shared law.
// Definition marker + successful invocation are 2H2R2W (64 logical bytes).
// Model receipt record is 1H15R1W and its self Some is 1H1R1W: 2H16R2W
// (176 bytes), retained before either constructor. No inferred unboxing/slack.
// Transient return tuple + Ok is 2H3R1W (64 bytes); this also covers Begin's
// smaller Ok(control)/Ok(receipt) carrier without overlapping live payloads.
fn installed_effect_publication_binding_capacity(
  model_transition : Bool,
) -> @execution.ExecutionCapacity {
  let model = if model_transition { 1L } else { 0L }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 2L + 2L * model,
      reference_slots: 2L + 16L * model,
      scalar_words: 2L + 2L * model,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 2L,
      reference_slots: 3L,
      scalar_words: 1L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  }).unwrap()
}

///|
// Closed issuer transition on the existing managed Run. No public callback,
// copied/CID-only publication binding, new owner or replacement Ledger.
fn begin_installed_effect_publication_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  expected_plan : ClientInstalledEffectManagedPlan,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  compilation : @publication_host.ClientEffectCompilation,
  publication_admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  source_slots : Int,
  model_transition? : Bool = false,
) -> Result[ClientEffectOperationControls, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, plan) &&
    physical_equal(plan, expected_plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    owner.source_free_captured is Some(dag) &&
    physical_equal(dag, @strategy.captured_effect_run_dag(captured)) &&
    @strategy.captured_effect_run_matches_checked(
      captured,
      @publication_host.prepared_client_effect_run_graph(bound),
    ) &&
    @publication_host.client_effect_publication_originals_match(
      bound, prepared, compilation, publication_admission, definition,
    ) else {
    return Err(ForeignOriginal)
  }
  if owner.effect_operation_opening ||
    owner.effect_operation_closing ||
    owner.publication_definition is Some(_) ||
    owner.publication_invocation is Some(_) ||
    control.construction_active ||
    control.ledger_codec_active ||
    control.constructor_frame is Some(_) {
    return Err(WrongPhase)
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(Installed(issue))
    Ok(_) => ()
  }
  guard installed_effect_dependency_fixed_capacity(source_slots, 0, 64)
    is Some(fixed) else {
    return Err(Installed(InsufficientCapacity))
  }
  let binding = installed_effect_publication_binding_capacity(model_transition)
  let fixed = match standard_create_sequence_pair_capacity(fixed, binding) {
    Some(value) => value
    None => return Err(Installed(InsufficientCapacity))
  }
  owner.effect_operation_opening = true
  // This existing numeric grow performs the original current fence once.
  // The latch blocks synchronous reentry before that callback and remains
  // held through the actual issuer. Its failed prefix stays on this owner.
  match
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, fixed,
    ) {
    Err(issue) => {
      owner.effect_operation_opening = false
      return Err(Installed(issue))
    }
    Ok(_) => ()
  }
  // Existing exact Definition storage is a consumed-start marker, never an
  // issued invocation. Keep it on every post-start failure until real retire.
  owner.publication_definition = Some(definition)
  Ok(control)
}

///|
fn finish_installed_effect_publication_invocation(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  original_control : ClientEffectOperationControls,
  definition : @publication.PublicationContract,
  value : (@publication.RunEvidenceValue, @publication.PublicationContract),
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.effect_operation_opening &&
    owner.publication_definition is Some(original_definition) &&
    physical_equal(original_definition, definition) &&
    owner.publication_invocation is None &&
    owner.effect_operation_controls is Some(control) &&
    physical_equal(control, original_control) &&
    owner.preparation is Some(PlannedEffectManaged(_, current_plan)) &&
    physical_equal(current_plan, plan) &&
    owner.source_free_captured is Some(dag) &&
    physical_equal(dag, @strategy.captured_effect_run_dag(captured)) &&
    @strategy.captured_effect_run_matches_checked(
      captured,
      @publication_host.prepared_client_effect_run_graph(bound),
    ) else {
    return Err(ForeignOriginal)
  }
  // Only immutable checks occur here; the actual external/current fences
  // belong to Begin and the closed Source/Content/Model caller boundaries.
  owner.publication_invocation = Some(value.1)
  Ok(value)
}

///|
/// Consume the exact early source-free issuer receipt once; never reissue it.
pub fn bind_installed_effect_source_free_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  issued : @publication_host.ClientEffectSourceFreeInvocationOriginal,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  if !@publication_host.client_effect_source_free_invocation_original_matches(
      issued, compilation,
    ) {
    return Err(ForeignOriginal)
  }
  let original_control = match
    begin_installed_effect_publication_invocation(
      owner, prepared, request, plan, bound, captured, compilation, admission, definition,
      0,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  defer {
    owner.effect_operation_opening = false
  }
  finish_installed_effect_publication_invocation(
    owner,
    plan,
    bound,
    captured,
    original_control,
    definition,
    (
      @publication_host.client_effect_source_free_invocation_original_observation(
        issued,
      ),
      @publication_host.client_effect_source_free_invocation_original_invocation(
        issued,
      ),
    ),
  )
}

///|
pub fn issue_installed_effect_captured_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  source : @query.CapturedInputSource,
  source_evidence : String,
  input_logical : String,
  source_ref : String,
  source_contract : String,
  authority : String,
  policy : String,
  started : String,
  completed : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  let original_control = match
    begin_installed_effect_publication_invocation(
      owner, prepared, request, plan, bound, captured, compilation, admission, definition,
      1,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  defer {
    owner.effect_operation_opening = false
  }
  let matches = @strategy.captured_task_source_matches(
    @strategy.captured_effect_run_dag(captured),
    0,
    source,
  )
  // Source availability above is an actual external callback. Fence once
  // after it; immutable codec/helper steps below require no repeated current.
  match require_installed_managed_run(owner) {
    Err(issue) => return Err(Installed(issue))
    Ok(_) => ()
  }
  if !matches {
    return Err(ForeignOriginal)
  }
  let issued = @publication_host.issue_client_effect_captured_invocation(
    prepared, compilation, admission, definition, source, source_evidence, input_logical,
    source_ref, source_contract, authority, policy, started, completed, max_bytes,
    max_nodes, max_depth,
  )
  match issued {
    Err(issue) => Err(PublicationInvocation(issue))
    Ok(value) =>
      finish_installed_effect_publication_invocation(
        owner, plan, bound, captured, original_control, definition, value,
      )
  }
}

///|
pub fn issue_installed_effect_multi_captured_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  sources : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  requirements : Array[@planning.QueryRequirement],
  source_evidence : Array[String],
  input_logical : Array[String],
  authority : String,
  policy : String,
  started : String,
  completed : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  let original_control = match
    begin_installed_effect_publication_invocation(
      owner,
      prepared,
      request,
      plan,
      bound,
      captured,
      compilation,
      admission,
      definition,
      sources.length(),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  defer {
    owner.effect_operation_opening = false
  }
  let dag = @strategy.captured_effect_run_dag(captured)
  let mut matches = true
  for index, source in sources {
    if !@strategy.captured_task_source_matches(dag, index, source) {
      matches = false
    }
  }
  match require_installed_managed_run(owner) {
    Err(issue) => return Err(Installed(issue))
    Ok(_) => ()
  }
  if !matches {
    return Err(ForeignOriginal)
  }
  let issued = @publication_host.issue_client_effect_multi_captured_invocation(
    prepared, compilation, admission, definition, sources, identities, requirements,
    source_evidence, input_logical, authority, policy, started, completed, max_bytes,
    max_nodes, max_depth,
  )
  match issued {
    Err(issue) => Err(PublicationInvocation(issue))
    Ok(value) =>
      finish_installed_effect_publication_invocation(
        owner, plan, bound, captured, original_control, definition, value,
      )
  }
}

///|
pub fn issue_installed_effect_direct_sources_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  sources : Array[@query.CapturedInputSource],
  identities : Array[@query.CapturedSourceRelationIdentity],
  source_evidence : Array[@publication.RunEvidenceValue],
  input_logical : Array[@publication.RunEvidenceValue],
  authority : String,
  policy : String,
  started : String,
  completed : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectDirectSourcesPublication,
  ClientClosedValuesPreparationIssue,
] {
  let original_control = match
    begin_installed_effect_publication_invocation(
      owner,
      prepared,
      request,
      plan,
      bound,
      captured,
      compilation,
      admission,
      definition,
      sources.length(),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  defer {
    owner.effect_operation_opening = false
  }
  let direct = match
    prepared_installed_effect_source_occurrences(plan, prepared, request) {
    Ok(Some(value)) => value
    _ => return Err(ForeignOriginal)
  }
  let count = @publication_host.client_direct_acquisition_occurrence_count(
    direct,
  )
  if count < 1 ||
    count > max_nodes ||
    sources.length() != count ||
    identities.length() != count ||
    source_evidence.length() != count ||
    input_logical.length() != count {
    return Err(ForeignOriginal)
  }
  let originals : Array[@publication_host.ClientDirectSourceOriginal] = []
  let dag = @strategy.captured_effect_run_dag(captured)
  let mut matches = true
  for slot in 0..<count {
    match prepared_installed_effect_managed_whole_source(plan, slot) {
      Ok((acquisition, _, _)) => {
        guard @publication_host.client_direct_acquisition_occurrence_at(
            direct, slot,
          )
          is Some((_, input, task)) else {
          return Err(ForeignOriginal)
        }
        if !@strategy.captured_source_input_original_matches(
            dag,
            task,
            input,
            sources[slot],
          ) {
          matches = false
        }
        originals.push(@publication_host.WholeSourceOriginal(acquisition))
      }
      Err(_) =>
        match prepared_installed_effect_managed_query_requirement(plan, slot) {
          Ok(requirement) => {
            if !@strategy.captured_task_source_matches(dag, slot, sources[slot]) {
              matches = false
            }
            originals.push(@publication_host.QuerySourceOriginal(requirement))
          }
          Err(_) => return Err(ForeignOriginal)
        }
    }
  }
  match require_installed_managed_run(owner) {
    Err(issue) => return Err(Installed(issue))
    Ok(_) => ()
  }
  if !matches {
    return Err(ForeignOriginal)
  }
  match
    @publication_host.prepare_client_effect_direct_sources_publication(
      prepared, compilation, admission, definition, direct, sources, identities,
      originals, source_evidence, input_logical, authority, policy, started, completed,
      max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => Err(PublicationInvocation(issue))
    Ok(value) => {
      match
        finish_installed_effect_publication_invocation(
          owner,
          plan,
          bound,
          captured,
          original_control,
          definition,
          (
            @publication_host.client_effect_direct_sources_publication_observation(
              value,
            ),
            @publication_host.client_effect_direct_sources_publication_invocation(
              value,
            ),
          ),
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      Ok(value)
    }
  }
}

///|
pub fn issue_installed_effect_content_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  compiled : @publication_host.ClientCompiledRun,
  generation : @publication_host.ClientSerializationGeneration,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  if !@publication_host.client_compiled_run_matches_effect(
      compiled, prepared, compilation,
    ) {
    return Err(ForeignOriginal)
  }
  let original_control = match
    begin_installed_effect_publication_invocation(
      owner, prepared, request, plan, bound, captured, compilation, admission, definition,
      0,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  defer {
    owner.effect_operation_opening = false
  }
  let issued = @publication_host.issue_client_serialization_invocation(
    compiled, definition, generation, max_bytes, max_nodes, max_depth,
  )
  // Content liveness can invoke its actual reference owner. Always reobserve
  // original current after that boundary, preserving the issuer's primary Err.
  let current = require_installed_managed_run(owner)
  match issued {
    Err(issue) => Err(PublicationInvocation(issue))
    Ok(value) =>
      match current {
        Err(issue) => Err(Installed(issue))
        Ok(_) =>
          finish_installed_effect_publication_invocation(
            owner, plan, bound, captured, original_control, definition, value,
          )
      }
  }
}

///|
/// Trusted Core-module-only handoff for the existing opaque Model binding.
/// No Node export exposes Begin/Finish/Abort or accepts caller tuple DATA.
/// The sole production caller is the CLOSED typed Model Node bridge: it reads
/// the actual live InvocationBinding, begins, rechecks the same binding after
/// current, finishes synchronously, and aborts in defer. No await or callback
/// may retain this DATA receipt. It grants no capacity, permission or ownership.
struct ClientInstalledEffectModelPublicationTransition {
  mut original : ClientInstalledEffectModelPublicationTransition?
  owner : ClientInstalledManagedRun
  prepared : @publication_host.PreparedClientEffectComputation
  request : @publication_host.ClientRequestIdentity
  plan : ClientInstalledEffectManagedPlan
  bound : @publication_host.PreparedClientEffectRun
  captured : @strategy.CapturedEffectRunDAG
  compilation : @publication_host.ClientEffectCompilation
  admission : @publication.RunPublicationAdmission
  definition : @publication.PublicationContract
  ledger : @resources.Ledger
  preparation : ClientInstalledManagedRunOriginal
  control : ClientEffectOperationControls
  observation : @publication.RunEvidenceValue
  invocation : @publication.PublicationContract
  mut used : Bool
}

///|
pub fn begin_installed_effect_model_publication_transition(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  compilation : @publication_host.ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  invocation : @publication.PublicationContract,
) -> Result[
  ClientInstalledEffectModelPublicationTransition,
  ClientClosedValuesPreparationIssue,
] {
  let original_control = match
    begin_installed_effect_publication_invocation(
      owner,
      prepared,
      request,
      plan,
      bound,
      captured,
      compilation,
      admission,
      definition,
      0,
      model_transition=true,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // Begin above retained/funded these exact fields before this constructor.
  let value : ClientInstalledEffectModelPublicationTransition = {
    original: None,
    owner,
    prepared,
    request,
    plan,
    bound,
    captured,
    compilation,
    admission,
    definition,
    ledger: owner.ledger.unwrap(),
    preparation: owner.preparation.unwrap(),
    control: original_control,
    observation,
    invocation,
    used: false,
  }
  value.original = Some(value)
  Ok(value)
}

///|
pub fn abort_installed_effect_model_publication_transition(
  value : ClientInstalledEffectModelPublicationTransition,
) -> Unit {
  if value.original is Some(original) && physical_equal(original, value) {
    value.used = true
    value.original = None
    value.owner.effect_operation_opening = false
  }
}

///|
pub fn finish_installed_effect_model_publication_transition(
  value : ClientInstalledEffectModelPublicationTransition,
  observation : @publication.RunEvidenceValue,
  invocation : @publication.PublicationContract,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ClientClosedValuesPreparationIssue,
] {
  guard value.original is Some(original) &&
    physical_equal(original, value) &&
    !value.used &&
    value.owner.effect_operation_opening &&
    value.owner.publication_definition is Some(original_definition) &&
    physical_equal(original_definition, value.definition) &&
    value.owner.publication_invocation is None else {
    return Err(WrongPhase)
  }
  value.used = true
  defer abort_installed_effect_model_publication_transition(value)
  if !physical_equal(value.observation, observation) ||
    !physical_equal(value.invocation, invocation) ||
    !@publication_host.client_effect_publication_originals_match(
      value.bound,
      value.prepared,
      value.compilation,
      value.admission,
      value.definition,
    ) ||
    !@strategy.captured_effect_run_matches_checked(
      value.captured,
      @publication_host.prepared_client_effect_run_graph(value.bound),
    ) ||
    !(match value.owner.source_free_captured {
      Some(dag) =>
        physical_equal(dag, @strategy.captured_effect_run_dag(value.captured))
      None => false
    }) {
    return Err(ForeignOriginal)
  }
  match
    check_installed_effect_managed_run_binding(
      value.owner,
      value.prepared,
      value.request,
    ) {
    Err(issue) => return Err(Installed(issue))
    Ok(_) => ()
  }
  match
    check_installed_effect_operation_original(
      value.owner,
      value.ledger,
      value.preparation,
      Some(value.control),
    ) {
    Err(issue) => return Err(Installed(issue))
    Ok(_) => ()
  }
  // This verifies current after the trusted caller rechecks its actual opaque
  // binding. The one-shot latch blocks reentry before this external boundary.
  match require_installed_managed_run(value.owner) {
    Err(issue) => return Err(Installed(issue))
    Ok(_) => ()
  }
  finish_installed_effect_publication_invocation(
    value.owner,
    value.plan,
    value.bound,
    value.captured,
    value.control,
    value.definition,
    (observation, invocation),
  )
}
