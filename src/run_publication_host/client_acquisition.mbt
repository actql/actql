///|
pub(all) enum ClientAcquisitionIssue {
  MissingStage
  MissingRequests
  UnsupportedAcquisition(@acquisition.QueryAcquisitionIssue)
}

///|
pub(all) enum ClientQueryRequirementIssue {
  Acquisition(ClientAcquisitionIssue)
  Sequence(@query.QuerySequenceIssue)
  Material(@planning.QueryMaterialIssue)
  Requirement(@planning.QueryRequirementIssue)
}

///|
/// Select a physical acquisition only from the requests sealed by the same
/// checked Program that owns the downstream Run graph. This remains a logical
/// acquisition; the Host must separately authorize a physical source and
/// retain its observed output before opening the captured Run.
pub fn prepare_client_query_acquisition(
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
) -> Result[@acquisition.QueryAcquisition, ClientAcquisitionIssue] {
  let identity = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  guard @context.program_identity_stage_at(identity, stage) is Some(_) else {
    return Err(MissingStage)
  }
  guard @context.program_identity_stage_requests(identity, stage)
    is Some(requests) else {
    return Err(MissingRequests)
  }
  @acquisition.derive_query_acquisition(requests, source_index, 1000000).map_err(issue => {
      UnsupportedAcquisition(issue)
    },
  )
}

///|
/// Compiler-only shape selection retains query-time dependencies unresolved.
/// It supplies no physical predicate material or execution context.
fn prepare_client_query_acquisition_shape(
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
) -> Result[@acquisition.QueryAcquisition, ClientAcquisitionIssue] {
  let identity = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  guard @context.program_identity_stage_at(identity, stage) is Some(_) else {
    return Err(MissingStage)
  }
  guard @context.program_identity_stage_requests(identity, stage)
    is Some(requests) else {
    return Err(MissingRequests)
  }
  @acquisition.derive_query_acquisition_shape(requests, source_index, 1000000).map_err(issue => {
      UnsupportedAcquisition(issue)
    },
  )
}

///|
/// Derive the same checked acquisition from an Effectful Program without
/// exposing its private Effect-free graph view to an installed adapter.
pub fn prepare_client_effect_query_acquisition(
  prepared : PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
) -> Result[@acquisition.QueryAcquisition, ClientAcquisitionIssue] {
  prepare_client_query_acquisition(
    client_effect_program_view(prepared),
    stage,
    source_index,
  )
}

///|
/// Bind the selected source request to the exact checked generated sequence
/// and Program identity before a physical Connector candidate is considered.
pub fn prepare_client_query_requirement(
  prepared : PreparedClientProgram,
  generated : @execution.GeneratedSequence,
  stage : Int,
  source_index : Int,
  guards : @planning.QueryLogicalGuards,
  limits : @planning.QueryMaterialLimits,
) -> Result[@planning.QueryRequirement, ClientQueryRequirementIssue] {
  let acquisition = match
    prepare_client_query_acquisition(prepared, stage, source_index) {
    Ok(value) => value
    Err(issue) => return Err(Acquisition(issue))
  }
  prepare_client_query_requirement_from_acquisition(
    prepared, generated, acquisition, guards, limits,
  )
}

///|
fn prepare_client_query_requirement_from_acquisition(
  prepared : PreparedClientProgram,
  generated : @execution.GeneratedSequence,
  acquisition : @acquisition.QueryAcquisition,
  guards : @planning.QueryLogicalGuards,
  limits : @planning.QueryMaterialLimits,
) -> Result[@planning.QueryRequirement, ClientQueryRequirementIssue] {
  let sequence = match
    @query.prepare_query_sequence(acquisition, generated, limits.max_work) {
    Ok(value) => value
    Err(issue) => return Err(Sequence(issue))
  }
  let material = match @planning.prepare_query_material(sequence, limits) {
    Ok(value) => value
    Err(issue) => return Err(Material(issue))
  }
  let identity = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  @planning.prepare_query_requirement(material, identity, guards, limits).map_err(issue => {
      Requirement(issue)
    },
  )
}

///|
/// Keep acquisition requirements and their generated sequence under the
/// same checked Effect computation. This still grants no provider read.
pub fn prepare_client_effect_query_requirement(
  prepared : PreparedClientEffectComputation,
  generated : @execution.GeneratedSequence,
  stage : Int,
  source_index : Int,
  guards : @planning.QueryLogicalGuards,
  limits : @planning.QueryMaterialLimits,
) -> Result[@planning.QueryRequirement, ClientQueryRequirementIssue] {
  prepare_client_query_requirement(
    client_effect_program_view(prepared),
    generated,
    stage,
    source_index,
    guards,
    limits,
  )
}

///|
/// Read-only correspondence for a later physical Source parent. The exact
/// checked Program, stage requests and original source occurrence must own
/// this requirement; equal canonical identities do not replace those owners.
/// This neither prepares another acquisition nor issues resource/read authority.
pub fn client_query_requirement_matches_program(
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
  requirement : @planning.QueryRequirement,
) -> Bool {
  let identity = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  guard @context.program_identity_stage_requests(identity, stage)
    is Some(requests) else {
    return false
  }
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let acquisition = @query.query_sequence_requirement(sequence)
  physical_equal(@planning.query_requirement_program(requirement), identity) &&
  physical_equal(@acquisition.query_acquisition_owner(acquisition), requests) &&
  @acquisition.query_acquisition_source_index(acquisition) == source_index
}

///|
/// Same original checked Effect preparation, without exposing its graph or
/// re-labelling a pure requirement as an Effect read or permission.
pub fn client_query_requirement_matches_effect_program(
  prepared : PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
  requirement : @planning.QueryRequirement,
) -> Bool {
  client_query_requirement_matches_program(
    client_effect_program_view(prepared),
    stage,
    source_index,
    requirement,
  )
}

///|
/// The graph seals the complete acquisition prefix. Physical task ordinals
/// outside this prefix cannot be substituted as acquired roots.
pub fn prepared_client_acquisition_count(value : PreparedClientProgram) -> Int {
  @strategy.graph_captured_prefix(value.graph)
}

///|
/// The original checked Catalog facts for one Source. These facts are used
/// to validate a later physical observation, never to authorize a file read.
pub fn prepared_client_source_evidence_facts(
  value : PreparedClientProgram,
  stage : Int,
  source_index : Int,
) -> @planning.QuerySourceEvidenceFacts? {
  prepare_client_query_acquisition(value, stage, source_index)
  .to_option()
  .bind(@planning.query_acquisition_source_evidence_facts)
}

///|
pub fn prepared_client_captured_task_source_matches(
  value : PreparedClientProgram,
  source : @query.CapturedInputSource,
  task : Int,
) -> Bool {
  if task < 0 || task >= prepared_client_acquisition_count(value) {
    return false
  }
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
    return false
  }
  @query.captured_source_matches(
    source,
    @checked.source_identity(@strategy.graph_program(value.graph)),
    owner,
  )
}

///|
/// Bind the whole capture tuple to the exact task owner, even when two
/// captures have identical content, schemas, or source contract CIDs.
fn client_captured_task_tuple_matches(
  value : PreparedClientProgram,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  task : Int,
) -> Bool {
  guard @strategy.graph_task_owner(value.graph, task) is Some(owner) else {
    return false
  }
  prepared_client_captured_task_source_matches(value, source, task) &&
  @query.captured_source_relation_identity_matches_source(identity, source) &&
  physical_equal(
    @planning.query_requirement_program(requirement),
    @checked.source_identity(@strategy.graph_program(value.graph)),
  ) &&
  physical_equal(
    @query.query_sequence_owner(
      @planning.query_material_owner(
        @planning.query_requirement_material(requirement),
      ),
    ),
    owner,
  )
}

///|
// A checked slice can add unknown provenance without changing any original
// Source contributor. Reuse only the already checked conservative policy:
// equal CIDs alone cannot substitute foreign occurrences, roles or copies.
fn client_publication_unknown_policy_join(
  left : @checked.PublicationSourcePolicy,
  right : @checked.PublicationSourcePolicy,
) -> @checked.PublicationSourcePolicy? {
  let count = @checked.effective_policy_occurrence_count(left.effective)
  guard left.cid != right.cid &&
    left.unknown_provenance != right.unknown_provenance &&
    count > 0 &&
    count == @checked.effective_policy_occurrence_count(right.effective) &&
    @checked.effective_policy_source_count(left.effective) ==
    @checked.effective_policy_source_count(right.effective) else {
    return None
  }
  for index in 0..<count {
    let same = match
      (
        @checked.effective_policy_occurrence_at(left.effective, index),
        @checked.effective_policy_occurrence_at(right.effective, index),
      ) {
      (Some(@checked.DirectPolicy(a)), Some(@checked.DirectPolicy(b))) =>
        physical_equal(a, b)
      (
        Some(@checked.KeyedResponsePolicy(a)),
        Some(@checked.KeyedResponsePolicy(b)),
      ) => physical_equal(a, b)
      (
        Some(@checked.KeyedStaticRequestPolicy(a)),
        Some(@checked.KeyedStaticRequestPolicy(b)),
      ) => physical_equal(a, b)
      _ => false
    }
    if !same {
      return None
    }
  }
  for index in 0..<@checked.effective_policy_source_count(left.effective) {
    if @checked.effective_policy_source_at(left.effective, index) !=
      @checked.effective_policy_source_at(right.effective, index) {
      return None
    }
  }
  // The immutable nominal occurrences above also bind their original response
  // policies. No response CID is inferred from a surrounding Catalog or source.
  let conservative = if left.unknown_provenance { left } else { right }
  if @checked.publication_policy_classification(conservative)
    is @environment.Unknown {
    Some(conservative)
  } else {
    None
  }
}

///|
/// Resolve effective policy from every exact checked final Result occurrence.
/// Missing, incompatible, or incomplete checked Source provenance is rejected;
/// the first acquisition policy is never promoted to a Run-wide policy.
pub fn prepared_client_publication_data_policy_cid(
  value : PreparedClientProgram,
) -> String? {
  let graph = value.graph
  let program = @strategy.graph_program(graph)
  let count = @strategy.graph_result_count(graph)
  if count == 0 {
    return None
  }
  let policies : Array[@checked.PublicationSourcePolicy] = []
  for result in 0..<count {
    guard @strategy.graph_result_task(graph, result) is Some(task) &&
      @strategy.graph_task_unit_index(graph, task) is Some(unit) &&
      @strategy.graph_result_occurrence(graph, result) is Some(occurrence) &&
      @strategy.graph_task_owner(graph, task) is Some(owner) &&
      physical_equal(
        @execution.managed_result_occurrence_owner(occurrence),
        owner,
      ) &&
      @checked.unit_publication_count(program, unit) is Some(publications) else {
      return None
    }
    let port = @execution.managed_result_occurrence_port(occurrence)
    let mut found : @checked.PublicationSourcePolicy? = None
    for index in 0..<publications {
      let publication = @checked.unit_publication_at(program, unit, index).unwrap()
      let resolution = @context.publication_row_limit_result(
        @checked.publication_selection(publication),
      )
      if resolution.stage == unit &&
        physical_equal(resolution.port, port) &&
        physical_equal(
          @results.port_result(resolution.port),
          @results.port_result(port),
        ) {
        if found is Some(_) {
          return None
        }
        found = @checked.publication_source_policy(publication)
      }
    }
    guard found is Some(policy) else { return None }
    policies.push(policy)
  }
  let mut selected : @checked.PublicationSourcePolicy? = None
  for candidate in policies {
    if !client_publication_policy_covers_source_responses(program, candidate) ||
      !policies.all(original => {
        client_publication_policy_contains_result(candidate, original)
      }) {
      continue
    }
    match selected {
      None => selected = Some(candidate)
      Some(prior) => if prior.cid != candidate.cid { return None }
    }
  }
  selected.map(policy => policy.cid)
}

///|
// Select only an already checked conservative representative. A Result may
// retain fewer original contributors than another exported Result; it cannot
// manufacture a policy union, replace an occurrence with an equal CID, or
// erase unknown provenance/classification from that original Result.
fn client_publication_policy_contains_result(
  candidate : @checked.PublicationSourcePolicy,
  original : @checked.PublicationSourcePolicy,
) -> Bool {
  let count = @checked.effective_policy_occurrence_count(original.effective)
  let covering_count = @checked.effective_policy_occurrence_count(
    candidate.effective,
  )
  let sources = @checked.effective_policy_source_count(original.effective)
  let covering_sources = @checked.effective_policy_source_count(
    candidate.effective,
  )
  if count < 1 ||
    count > covering_count ||
    sources > covering_sources ||
    (original.unknown_provenance && !candidate.unknown_provenance) ||
    (
      @checked.publication_policy_classification(original) !=
      @checked.publication_policy_classification(candidate) &&
      !(@checked.publication_policy_classification(candidate)
      is @environment.Unknown)
    ) {
    return false
  }
  if count == covering_count &&
    sources == covering_sources &&
    original.cid != candidate.cid {
    return client_publication_unknown_policy_join(original, candidate).map(selected => {
        physical_equal(selected, candidate)
      }) ==
      Some(true)
  }
  let mut previous = -1
  for index in 0..<count {
    let mut found = -1
    for covering in 0..<covering_count {
      let same = match
        (
          @checked.effective_policy_occurrence_at(original.effective, index),
          @checked.effective_policy_occurrence_at(candidate.effective, covering),
        ) {
        (Some(@checked.DirectPolicy(a)), Some(@checked.DirectPolicy(b))) =>
          physical_equal(a, b)
        (
          Some(@checked.KeyedResponsePolicy(a)),
          Some(@checked.KeyedResponsePolicy(b)),
        ) => physical_equal(a, b)
        (
          Some(@checked.KeyedStaticRequestPolicy(a)),
          Some(@checked.KeyedStaticRequestPolicy(b)),
        ) => physical_equal(a, b)
        _ => false
      }
      if same {
        if found >= 0 {
          return false
        }
        found = covering
      }
    }
    if found <= previous {
      return false
    }
    previous = found
  }
  for index in 0..<sources {
    let source = @checked.effective_policy_source_at(original.effective, index)
    if source is None {
      return false
    }
    let mut found = 0
    for covering in 0..<covering_sources {
      if @checked.effective_policy_source_at(candidate.effective, covering) ==
        source {
        found += 1
      }
    }
    if found != 1 {
      return false
    }
  }
  true
}

///|
// Whole-Run publication retains every actual response original,
// including a downstream keyed response. Source coordinates and equal CIDs
// are not substitutes for the same checked occurrence. The policy owns the
// existing inventory; this read-only comparison constructs no second policy.
fn client_publication_policy_covers_source_responses(
  program : @checked.CheckedProgram,
  policy : @checked.PublicationSourcePolicy,
) -> Bool {
  let owner = @checked.source_identity(program)
  let policy_count = @checked.publication_policy_source_count(policy)
  let mut responses = 0
  for index in 0..<@checked.source_execution_count(program) {
    let original = @checked.source_execution_at(program, index).unwrap()
    let response = match @checked.source_execution_kind(original) {
      @checked.CarrierResponse =>
        @checked.source_execution_subject(original).request
        is @acquisition.Direct(_, _)
      @checked.KeyedResponse(_) => true
      _ => false
    }
    if response {
      if !physical_equal(
          @checked.source_execution_subject(original).owner,
          owner,
        ) {
        return false
      }
      let mut occurrences = 0
      for policy_index in 0..<policy_count {
        if @checked.publication_policy_source_at(policy, policy_index)
          is Some(candidate) &&
          physical_equal(candidate, original) {
          occurrences += 1
        }
      }
      if occurrences != 1 {
        return false
      }
      responses += 1
    }
  }

  // Extra, duplicate or foreign policy entries cannot fill a missing original.
  responses == policy_count
}
