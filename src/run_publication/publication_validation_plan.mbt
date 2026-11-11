///|
priv struct PublicationValidationUsage {
  mut bytes : Int
  mut nodes : Int
  mut depth : Int
  mut occurrence_nodes : Int64
  mut metadata_bytes : Int
  mut metadata_nodes : Int
  mut metadata_depth : Int
}

///|
fn PublicationValidationUsage::add_contract(
  self : PublicationValidationUsage,
  value : PublicationContract,
  captured? : Bool = false,
) -> Bool {
  guard value.wire_usage is Some((b, n, d)) else { return false }
  if b < 1 || n < 1 || d < 1 {
    return false
  }
  self.bytes = Int::max(self.bytes, b)
  self.nodes = Int::max(self.nodes, n)
  self.depth = Int::max(self.depth, d)
  if !captured {
    self.metadata_bytes = Int::max(self.metadata_bytes, b)
    self.metadata_nodes = Int::max(self.metadata_nodes, n)
    self.metadata_depth = Int::max(self.metadata_depth, d)
  }
  self.occurrence_nodes += n.to_int64()
  self.occurrence_nodes <= 2147483647L
}

///|
fn PublicationValidationUsage::include_all(
  self : PublicationValidationUsage,
  values : Array[PublicationContract],
) -> Bool {
  for value in values {
    if !self.add_contract(value) {
      return false
    }
  }
  true
}

///|
fn PublicationValidationUsage::retain_completed_extent(
  self : PublicationValidationUsage,
  retained : CapturedRunIssuancePreparation?,
  captured : PublicationContract,
) -> Unit {
  if retained is Some(original) &&
    !original.closed &&
    original.completed is Some(completed) &&
    original.contract is Some(contract) &&
    physical_equal(contract, captured) {
    // Preserve the same issuer's conservative extent so the existing exact
    // original matcher may reuse its completed fact. Other contracts can still
    // enlarge any dimension; no retained fact skips new commit dependencies.
    self.bytes = Int::max(self.bytes, completed.max_wire_bytes)
    self.nodes = Int::max(self.nodes, completed.max_nodes)
    self.depth = Int::max(self.depth, completed.max_depth)
  }
}

///|
priv enum PublicationValidationOriginals {
  Chain(ComputationEvidenceInputs)
  Commit(PublicationCommitInputs)
}

///|
/// Immutable owned reference inventories bind the measured originals through
/// reservation and validation. No row/canonical tree is copied or re-admitted.
/// This descriptor is not a physical grant; the Host reserves its same owner.
struct PublicationValidationPlan {
  mut originals : PublicationValidationOriginals?
  mut retained : CapturedRunIssuancePreparation?
  usage : PublicationValidationUsage
  workspace : Int
  reuse_capture : Bool
}

///|
fn original_chain_validation_inputs(
  usage : PublicationValidationUsage,
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
) -> ComputationEvidenceInputs? {
  if !usage.add_contract(run_definition) ||
    !usage.add_contract(invocation) ||
    !usage.include_all(definitions) ||
    !usage.include_all(artifacts) ||
    !usage.add_contract(manifest) ||
    !usage.add_contract(receipt) ||
    !usage.add_contract(captured_run, captured=true) {
    return None
  }
  Some({
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    captured_run,
    preview: None,
    max_wire_bytes: usage.bytes,
    max_nodes: usage.nodes,
    max_depth: usage.depth,
  })
}

///|
pub fn prepare_original_effect_free_chain_validation(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  retained? : CapturedRunIssuancePreparation? = None,
) -> PublicationValidationPlan? {
  let definitions = definitions.copy()
  let artifacts = artifacts.copy()
  let usage = {
    bytes: 0,
    nodes: 0,
    depth: 0,
    occurrence_nodes: 0L,
    metadata_bytes: 0,
    metadata_nodes: 0,
    metadata_depth: 0,
  }
  usage.retain_completed_extent(retained, captured_run)
  guard original_chain_validation_inputs(
      usage, run_definition, invocation, definitions, artifacts, manifest, receipt,
      captured_run,
    )
    is Some(inputs) else {
    return None
  }
  let reuse_capture = retained is Some(original) &&
    original.matches_computation(inputs)
  Some({
    originals: Some(Chain(inputs)),
    retained: if reuse_capture {
      retained
    } else {
      None
    },
    usage,
    workspace: publication_evidence_workspace(usage.occurrence_nodes.to_int()),
    reuse_capture,
  })
}

///|
pub fn prepare_original_effect_free_commit_validation(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  derivations : Array[PublicationContract],
  orderings : Array[PublicationContract],
  retentions : Array[PublicationContract],
  bindings : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  request : PublicationContract,
  attempt : PublicationContract,
  index_entry : PublicationContract,
  retained? : CapturedRunIssuancePreparation? = None,
) -> PublicationValidationPlan? {
  let definitions = definitions.copy()
  let artifacts = artifacts.copy()
  let derivations = derivations.copy()
  let orderings = orderings.copy()
  let retentions = retentions.copy()
  let bindings = bindings.copy()
  let usage = {
    bytes: 0,
    nodes: 0,
    depth: 0,
    occurrence_nodes: 0L,
    metadata_bytes: 0,
    metadata_nodes: 0,
    metadata_depth: 0,
  }
  // Include the entire commit before projecting the computation limits. A tiny
  // captured Run does not bound a larger request/attempt/Index or binding.
  if !usage.include_all(derivations) ||
    !usage.include_all(orderings) ||
    !usage.include_all(retentions) ||
    !usage.include_all(bindings) ||
    !usage.add_contract(request) ||
    !usage.add_contract(attempt) ||
    !usage.add_contract(index_entry) {
    return None
  }
  usage.retain_completed_extent(retained, captured_run)
  guard original_chain_validation_inputs(
      usage, run_definition, invocation, definitions, artifacts, manifest, receipt,
      captured_run,
    )
    is Some(computation) else {
    return None
  }
  let reuse_capture = retained is Some(original) &&
    original.matches_computation(computation)
  Some({
    originals: Some(
      Commit({
        origin: OwnedInputs,
        computation,
        derivations,
        orderings,
        retentions,
        bindings,
        request,
        attempt,
        index_entry,
      }),
    ),
    retained: if reuse_capture {
      retained
    } else {
      None
    },
    usage,
    workspace: publication_evidence_workspace(usage.occurrence_nodes.to_int()),
    reuse_capture,
  })
}

///|
pub fn publication_validation_plan_limits(
  plan : PublicationValidationPlan,
) -> (Int, Int, Int, Int)? {
  guard plan.originals is Some(_) else { return None }
  Some((plan.usage.bytes, plan.usage.nodes, plan.usage.depth, plan.workspace))
}

///|
pub fn start_planned_chain_validation(
  plan : PublicationValidationPlan,
  max_workspace? : Int? = None,
) -> ComputationEvidenceCheck? {
  guard plan.originals is Some(Chain(i)) else { return None }
  guard publication_validation_plan_reuses_capture(plan) is Some(_) else {
    return None
  }
  let workspace = match max_workspace {
    Some(ceiling) => Int::min(plan.workspace, ceiling)
    None => plan.workspace
  }
  if workspace < 1 {
    return None
  }
  let original = plan.retained
  plan.originals = None
  plan.retained = None
  Some(
    match original {
      Some(original) =>
        start_effect_free_run_evidence_check_retained(
          original,
          i.run_definition,
          i.invocation,
          i.definitions,
          i.artifacts,
          i.manifest,
          i.receipt,
          i.captured_run,
          i.max_wire_bytes,
          i.max_nodes,
          i.max_depth,
          workspace,
        )
      None => start_computation_evidence_check(i, workspace)
    },
  )
}

///|
pub fn start_planned_commit_validation(
  plan : PublicationValidationPlan,
  max_workspace? : Int? = None,
) -> PublicationCommitPreparation? {
  guard plan.originals is Some(Commit(i)) else { return None }
  guard publication_validation_plan_reuses_capture(plan) is Some(_) else {
    return None
  }
  let workspace = match max_workspace {
    Some(ceiling) => Int::min(plan.workspace, ceiling)
    None => plan.workspace
  }
  if workspace < 1 {
    return None
  }
  let original = plan.retained
  plan.originals = None
  plan.retained = None
  let c = i.computation
  // These are private owned arrays, unlike the old public borrowed-input path.
  let preparation : PublicationCommitPreparation = {
    inputs: Some(i),
    retained_capture: None,
    retained_effectful: None,
    max_workspace: workspace,
    phase: BeginResultEvidence,
    live: 12,
    peak: 12,
    closed: false,
    view: None,
  }
  if original is Some(original) &&
    workspace > preparation.live &&
    original.matches_computation(c) {
    preparation.retained_capture = Some(original)
    preparation.live += 1
    preparation.peak = preparation.live
  }
  Some(preparation)
}

///|
pub fn cancel_publication_validation_plan(
  plan : PublicationValidationPlan,
) -> Unit {
  plan.originals = None
  plan.retained = None
}

///|
/// A quote may select the metadata-only path only from this plan's original
/// matcher. Losing that original fails stale; it never switches to full work
/// under a previously selected metadata-only grant. The derived workspace is
/// at least4096, above the existing validators'12 control slots.
pub fn publication_validation_plan_reuses_capture(
  plan : PublicationValidationPlan,
) -> Bool? {
  guard plan.originals is Some(originals) else { return None }
  if !plan.reuse_capture {
    return Some(false)
  }
  let computation = match originals {
    Chain(value) => value
    Commit(value) => value.computation
  }
  guard plan.retained is Some(original) &&
    original.matches_computation(computation) else {
    return None
  }
  Some(true)
}

///|
/// Copied reference slots, all contract occurrence nodes, and metadata nodes
/// excluding the captured contract. The last field is usable only with the
/// same plan's proven retained-reuse classification; otherwise fund full work.
pub fn publication_validation_plan_inventory(
  plan : PublicationValidationPlan,
) -> (Int, Int, Int, Int, Int, Int, Int)? {
  guard plan.originals is Some(originals) else { return None }
  let (computation, extra, arrays) = match originals {
    Chain(value) => (value, 0L, 2)
    Commit(value) =>
      (
        value.computation,
        value.derivations.length().to_int64() +
        value.orderings.length().to_int64() +
        value.retentions.length().to_int64() +
        value.bindings.length().to_int64(),
        6,
      )
  }
  let copied = extra +
    computation.definitions.length().to_int64() +
    computation.artifacts.length().to_int64()
  guard computation.captured_run.wire_usage is Some((_, captured_nodes, _)) else {
    return None
  }
  if copied > 2147483647L {
    return None
  }
  Some(
    (
      copied.to_int(),
      arrays,
      plan.usage.occurrence_nodes.to_int(),
      (plan.usage.occurrence_nodes - captured_nodes.to_int64()).to_int(),
      plan.usage.metadata_bytes,
      plan.usage.metadata_nodes,
      plan.usage.metadata_depth,
    ),
  )
}
