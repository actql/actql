///|
/// The caller has already charged and validated this declared dependency edge.
/// Repeated source uses do not multiply the adjacency of a shared body.
fn core_contract_dependency(
  b : CoreContractBuilder,
  parent : CoreContractBody,
  target : CoreContractBody,
) -> Unit {
  let cid = core_contract_cid(parent)
  let links = match b.dependencies.get(cid) {
    Some(v) => v
    None => {
      let v = { targets: [], seen: {}, }
      b.dependencies[cid] = v
      v
    }
  }
  let key = core_contract_cid(target)
  if !links.seen.contains(key) {
    links.seen[key] = ()
    links.targets.push(target)
  }
}

///|
fn core_contract_site_stage(
  site : CoreContractSite,
  incoming : ProgramIncomingRequirements,
) -> Int {
  match site {
    StageExpression(stage)
    | OperationLaw(stage, _, _, _, _)
    | OperationCountLaw(stage, _, _)
    | OperationValuesWireLaw(stage, _, _)
    | OperationValuesExecutionRules(stage, _, _)
    | OperationTransferRules(stage, _, _)
    | OperationRelationCountRules(stage, _, _)
    | OperationJoinCountRules(stage, _, _)
    | OperationIntervalSearchRules(stage, _, _)
    | OperationAsOfSearchRules(stage, _, _)
    | OperationWindowCountRules(stage, _, _)
    | OperationGraphCountRules(stage, _, _)
    | OperationRankingCountRules(stage, _, _)
    | OperationSeriesCountRules(stage, _, _)
    | OperationModelContract(stage, _, _, _)
    | NumericAggregateProfile(stage, _, _, _)
    | NumericAggregateSlotRules(stage, _, _, _)
    | CatalogReference(stage, _, _)
    | StageSourceGrammar(stage)
    | StageLocalInputRules(stage, _)
    | StageLocalInputType(stage, _)
    | StageLocalInputScores(stage, _)
    | StageCanonicalIdentityRules(stage)
    | StagePublicationRules(stage, _)
    | StageSourceResponsePolicyRules(stage, _)
    | StageEffectiveDataPolicyRules(stage, _)
    | StageSemanticRules(stage, _)
    | StageEnvironmentRules(stage)
    | OperationDataProfile(stage, _, _, _) => stage
    IncomingRules(index) => incoming.entries[index].stage
  }
}

///|
/// Select only the stage's own roots and their validated declared dependencies.
/// This partitions the supported inventory; it does not certify completeness of
/// a Unit contract closure or introduce a new identity preimage.
fn core_contract_stages(
  b : CoreContractBuilder,
  incoming : ProgramIncomingRequirements,
  count : Int,
) -> Array[Array[CoreContractBody]] raise CoreContractStop {
  let stages : Array[CoreContractDependencies] = []
  for _ in 0..<count {
    core_contract_charge(b)
    stages.push({ targets: [], seen: {}, })
  }
  for root in b.roots {
    core_contract_charge(b)
    let stage = stages[core_contract_site_stage(root.site, incoming)]
    let cid = core_contract_cid(root.body)
    if !stage.seen.contains(cid) {
      stage.seen[cid] = ()
      stage.targets.push(root.body)
    }
  }
  let out = []
  for stage in stages {
    core_contract_charge(b)
    let mut cursor = 0
    while cursor < stage.targets.length() {
      core_contract_charge(b)
      if b.dependencies.get(core_contract_cid(stage.targets[cursor]))
        is Some(links) {
        for target in links.targets {
          core_contract_charge(b)
          let cid = core_contract_cid(target)
          if !stage.seen.contains(cid) {
            stage.seen[cid] = ()
            stage.targets.push(target)
          }
        }
      }
      cursor += 1
    }
    out.push(stage.targets)
  }
  out
}

///|
/// O(1) reads of the retained selection, without re-traversal or array copying.
pub fn core_contract_stage_count(v : CoreContractInventory) -> Int {
  v.stages.length()
}

///|
pub fn core_contract_stage_body_count(
  v : CoreContractInventory,
  stage : Int,
) -> Int? {
  v.stages.get(stage).map(bodies => bodies.length())
}

///|
pub fn core_contract_stage_body_at(
  v : CoreContractInventory,
  stage : Int,
  index : Int,
) -> CoreContractBody? {
  v.stages.get(stage).bind(bodies => bodies.get(index))
}
