///|
/// Facts of the exact original capture inputs, not an allocation grant. Only
/// this package constructs the descriptor. The Host must reserve its existing
/// owner before starting the issuer with the same nominal plan.
priv struct CapturedRunConstructionExtent {
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  metadata_nodes : Int
  results : Int
  total_fields : Int
  max_fields : Int
  models : Int
}

///|
struct CapturedRunConstructionPlan {
  mut inputs : CapturedRunIssuanceInputs?
  extent : CapturedRunConstructionExtent
  max_workspace : Int
}

///|
/// One plain capture plan. Source advances and Content generation require
/// their own original extent projection; they cannot be represented as empty.
pub fn prepare_original_effect_free_capture_plan(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
) -> CapturedRunConstructionPlan? {
  // These private reference inventories sever every caller-owned Array alias.
  // Nominal children (contracts, snapshots and canonical values) are immutable.
  // The Host funds this count-derived copy packet before entering this function.
  let definitions = definitions.copy()
  let artifacts = artifacts.copy()
  let snapshots = snapshots.copy()
  let models = models.copy()
  guard captured_plain_run_construction_extent(
      receipt, snapshots, authoring, models,
    )
    is Some(extent) else {
    return None
  }
  Some({
    inputs: Some({
      run_definition,
      invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
      snapshots,
      sources: [],
      local_sources: [],
      advances: [],
      authoring,
      models,
      content_generations: [],
      preview: None,
      plan_values: [],
      max_wire_bytes: extent.max_wire_bytes,
      max_nodes: extent.max_nodes,
      max_depth: extent.max_depth,
      dependency_inventory: None,
    }),
    extent,
    max_workspace: publication_evidence_workspace(extent.max_nodes),
  })
}

///|
/// Read only while this plan still owns its exact input bag. Consuming or
/// cancelling a plan never fabricates a new original or releases Store custody.
pub fn capture_construction_layout_facts(
  original : CapturedRunConstructionPlan,
) -> (Int, Int, Int, Int, Int, Int, Int, Int)? {
  guard original.inputs is Some(_) else { return None }
  let e = original.extent
  Some(
    (
      e.max_wire_bytes,
      e.max_nodes,
      e.max_depth,
      e.metadata_nodes,
      e.results,
      e.total_fields,
      e.max_fields,
      e.models,
    ),
  )
}

///|
pub fn start_planned_captured_run(
  original : CapturedRunConstructionPlan,
) -> CapturedRunIssuancePreparation? {
  guard original.inputs is Some(inputs) else { return None }
  original.inputs = None
  Some(start_captured_computation_preparation(inputs, original.max_workspace))
}

///|
pub fn cancel_capture_construction_plan(
  original : CapturedRunConstructionPlan,
) -> Unit {
  original.inputs = None
}

///|
/// The exact original Run definition, not a CID substitute or a new binding.
pub fn capture_construction_run_definition(
  original : CapturedRunConstructionPlan,
) -> PublicationContract? {
  match original.inputs {
    Some(inputs) => Some(inputs.run_definition)
    None => None
  }
}

///|
pub fn capture_construction_invocation(
  original : CapturedRunConstructionPlan,
) -> PublicationContract? {
  match original.inputs {
    Some(inputs) => Some(inputs.invocation)
    None => None
  }
}
