///|
priv struct StoredMockEffectPublicManifest {
  manifest : @publication.PublicationContract
  definitions : Array[@publication.PublicationContract]
  artifacts : Array[@publication.PublicationContract]
}

///|
fn advance_original_mock_effect_public_receipt(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  materials : @host.ClientEffectRunMaterials,
  manifest : StoredMockEffectPublicManifest,
  publication : @host.ClientEffectDirectSourcesPublication,
) -> Int {
  guard targets.public_receipt is None else { return -32 }
  let limits = @host.client_standard_effect_computation_limits().effects
  let max_bytes = limits.max_admission_text_bytes
  let max_nodes = limits.max_admission_nodes
  let max_depth = limits.max_admission_depth
  guard @local_host.installed_effect_public_receipt_entry(materials)
    is Some(entry) &&
    @resources.reserve_capacity(drive.ledger, 0L, entry) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  let mut active = entry
  let mut inventory = 0L
  let mut retained : Int64? = None
  let mut funding_refused = false
  let grow = fn(peak) {
    if peak <= active {
      return true
    }
    if @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, peak)
      is Err(_) {
      return false
    }
    active = peak
    true
  }
  let receipt = @host.issue_client_effect_direct_sources_computation_receipt(
    publication,
    materials,
    manifest.definitions,
    manifest.artifacts,
    manifest.manifest,
    max_bytes,
    max_nodes,
    max_depth,
    (
      slots => {
        guard @local_host.installed_effect_public_receipt_inventory(
            slots, max_depth,
          )
          is Some(bytes) &&
          grow(bytes) else {
          funding_refused = true
          return false
        }
        inventory = bytes
        true
      },
      (bytes, nodes, depth) => {
        guard @local_host.installed_effect_public_receipt_capacity(
            bytes, nodes, depth, max_bytes, max_nodes, inventory,
          )
          is Some(capacity) &&
          grow(@execution.execution_capacity_execution_bytes(capacity)) else {
          funding_refused = true
          return false
        }
        retained = Some(@execution.execution_capacity_retained_bytes(capacity))
        true
      },
    ),
  )
  guard receipt is Ok(receipt) && retained is Some(retained) else {
    return if funding_refused { -4 } else { -31 }
  }
  if !fund_original_mock_effect_target_bytes(drive, retained) {
    return -4
  }
  targets.public_receipt = Some(receipt)
  if release_original_mock_effect_target_document(drive, targets) {
    1
  } else {
    -9
  }
}
