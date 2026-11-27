///|
fn prepare_original_mock_effect_preview_dispatch_keys(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  authored : @publication.AuthoredEffectPreview,
) -> Result[@local_host.InstalledEffectPreviewDispatchKeys, Int] {
  guard targets.workspace is None &&
    targets.dispatch_keys is None &&
    targets.authored is Some(held) &&
    physical_equal(held, authored) &&
    @host.prepared_client_effect_request_scope(
      original.journal.materials.prepared,
      original.effect.request,
    )
    is Ok(scope) else {
    return Err(-32)
  }
  let preview = @publication.authored_effect_preview_identity(authored)
  let authority = @identity.logical_request_scope_authority(scope)
  for index, selected in targets.members {
    if !mock_effect_target_read_current(original, selected.original) {
      return Err(-20)
    }
    let member_authority = @publication.effect_preview_member_authority_scope_cid(
      preview, index,
    )
    guard member_authority == Some(authority) else { return Err(-32) }
  }
  let (capacity, held_bytes) = match
    @local_host.installed_update_effect_preview_dispatch_capacity(preview) {
    Ok(value) => value
    Err(CapacityExceeded) => return Err(-4)
    Err(_) => return Err(-31)
  }
  let work = @execution.execution_capacity_execution_bytes(capacity)
  guard @resources.reserve_capacity(drive.ledger, 0L, work) is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  guard @local_host.prepare_installed_effect_preview_dispatch_keys(
      preview, scope,
    )
    is Ok(keys) else {
    return Err(-31)
  }
  guard fund_original_mock_effect_target_bytes(drive, held_bytes) else {
    return Err(-4)
  }
  Ok(keys)
}

///|
priv struct StoredMockEffectCompletedPreview {
  wire : String
  identity : @publication.EffectPreviewIdentity
  keys : Array[Array[@effect.EffectDispatchKey]]
}

///|
fn prepare_original_mock_effect_preview_completion(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
) -> Result[StoredMockEffectCompletedPreview, Int] {
  guard targets.workspace is None &&
    targets.completed is None &&
    targets.authored is Some(authored) &&
    targets.dispatch_keys is Some(keys) else {
    return Err(-32)
  }
  if !targets.members.all(selected => {
      mock_effect_target_read_current(original, selected.original)
    }) {
    return Err(-20)
  }
  // Each generated dispatch CID replaces a same-width placeholder. The
  // original author measured this exact geometry before returning its wire.
  let usage = @publication.authored_effect_preview_usage(authored)
  guard @local_host.installed_effect_preview_completion_capacity(usage, keys)
    is Some(quote) &&
    @resources.reserve_capacity(
      drive.ledger,
      0L,
      @execution.execution_capacity_execution_bytes(quote),
    )
    is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  guard @local_host.prepare_installed_effect_preview_dispatch_completion(
      authored, keys,
    )
    is Ok(prepared) &&
    @publication.prepared_effect_preview_dispatch_usage(prepared) == usage &&
    @publication.admit_prepared_effect_preview_dispatch(prepared)
    is Ok((wire, identity)) &&
    @local_host.confirm_installed_effect_preview_dispatch_keys(identity, keys)
    is Ok(confirmed) else {
    return Err(-31)
  }
  Ok({ wire, identity, keys: confirmed, })
}

///|
fn mock_effect_completed_preview_charge(
  inventory : @publication.EffectPreviewIdentityConstructionInventory,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: inventory.record_headers,
    reference_slots: inventory.reference_slots,
    scalar_words: inventory.scalar_words,
    owned_utf16_units: inventory.owned_utf16_units,
    owned_wire_bytes: inventory.owned_wire_bytes,
  })
}

///|
// Completion has returned all of its borrows of the authored Preview and
// key wrapper. Both bodies stay covered by the open workspace until its
// handoff. The existing key allowance keeps the same confirmed key arrays.
fn retain_original_mock_effect_preview_completion(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  completed : StoredMockEffectCompletedPreview,
) -> Bool {
  let retired = targets.authored
    .bind(@publication.authored_effect_preview_retained_inventory)
    .bind(mock_effect_completed_preview_charge)
  let next = @publication.completed_effect_preview_retained_inventory(
    completed.identity,
    completed.wire,
  ).bind(mock_effect_completed_preview_charge)
  guard retired is Some(before) && next is Some(after) else { return false }
  let charged = drive.charged
  guard before <= charged.retained_bytes &&
    before <= charged.execution_bytes &&
    @execution.execution_capacity(
      charged.retained_bytes - before,
      charged.execution_bytes - before,
    ).bind(previous => {
      @execution.execution_capacity(after, after).bind(extra => {
        @execution.add_execution_capacity(previous, extra)
      })
    })
    is Some(capacity) else {
    return false
  }
  if after > before &&
    @resources.grow_capacity_reservation(
      drive.ledger,
      drive.capacity,
      capacity.retained_bytes,
      capacity.execution_bytes,
    )
    is Err(_) {
    return false
  }
  targets.authored = None
  targets.dispatch_keys = None
  targets.completed = Some(completed)
  if after < before &&
    @resources.shrink_capacity_reservation(
      drive.ledger,
      drive.capacity,
      capacity.retained_bytes,
      capacity.execution_bytes,
    )
    is Err(_) {
    return false
  }
  drive.charged = capacity
  true
}
