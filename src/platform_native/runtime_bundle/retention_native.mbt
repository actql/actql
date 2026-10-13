///|
fn member_hold_id(binding : @bundle.RemoteBundleHoldBinding) -> String {
  "workspace-set:" + @bundle.bundle_hold_binding_identity(binding)
}

///|
fn new_catalog_incarnation(
  library : @signature.Library,
) -> Result[String, NativeRuntimeBundleStoreIssue] {
  let bytes = match library.random_bytes(32) {
    Ok(value) => value
    Err(issue) => return Err(Signature(issue))
  }
  let digest = @sha.hex(bytes)
  Ok(
    digest[0:8].to_owned() +
    "-" +
    digest[8:12].to_owned() +
    "-" +
    digest[12:16].to_owned() +
    "-" +
    digest[16:20].to_owned() +
    "-" +
    digest[20:32].to_owned(),
  )
}

///|
/// Explicit legacy opt-in. Never replaces a missing or corrupt established
/// incarnation or repairs a retained catalog. Ordinary opening does not migrate.
pub fn NativeRuntimeBundleStore::initialize_retention(
  self : NativeRuntimeBundleStore,
) -> Result[String, NativeRuntimeBundleStoreIssue] {
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if current.catalog_incarnation is Some(value) {
    return Ok(value)
  }
  if self.retention_initialized {
    return Err(RecoveryRequired)
  }
  for entry in current.entries {
    for hold in entry.holds {
      if hold.hold_id.has_prefix("workspace-set:") ||
        hold.binding_body is Some(_) {
        return Err(RecoveryRequired)
      }
    }
  }
  let incarnation = match new_catalog_incarnation(self.signature_library) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let next = {
    ..current,
    revision: current.revision + 1L,
    catalog_incarnation: Some(incarnation),
  }
  match persist_catalog(self, current, next) {
    Ok(_) => {
      self.retention_initialized = true
      Ok(incarnation)
    }
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeRuntimeBundleStore::retention_context(
  self : NativeRuntimeBundleStore,
  runtime_bundle_cid : String,
) -> Result[NativeRuntimeBundleRetentionContext, NativeRuntimeBundleStoreIssue] {
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard current.catalog_incarnation is Some(catalog_incarnation) else {
    return Err(RecoveryRequired)
  }
  guard entry_index(current, runtime_bundle_cid) is Some(index) else {
    return Err(MissingBundle)
  }
  let entry = current.entries[index]
  let state = @bundle.bundle_record_projection(entry.record)
  if entry.reclaim_pending || state[1] == "3" {
    return Err(RecoveryRequired)
  }
  match verify_component(self, entry) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let revision : Int = @string.from_str(state[0]) catch {
    _ => return Err(StateCollision)
  }
  Ok({
    catalog_incarnation,
    runtime_bundle_cid,
    initial_revision: revision,
    manifest: entry.manifest,
  })
}

///|
fn member_receipt(
  catalog : NativeRuntimeBundleCatalog,
  binding : @bundle.RemoteBundleHoldBinding,
) -> Result[NativeRuntimeBundleHoldReceipt, NativeRuntimeBundleStoreIssue] {
  let body = match bundle_result(@bundle.bundle_hold_binding_json(binding)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let binding_cid = @bundle.bundle_hold_binding_identity(binding)
  let runtime_bundle_cid = @bundle.bundle_hold_binding_projection(binding)[8]
  let hold_id = member_hold_id(binding)
  let mut exact = false
  for entry in catalog.entries {
    for hold in entry.holds {
      if hold.hold_id == hold_id {
        if entry_cid(entry) != runtime_bundle_cid ||
          hold.binding_body != Some(body) ||
          hold.kind != "workspace-set" {
          return Err(HoldCollision)
        }
        exact = true
      }
    }
  }
  let entry = entry_index(catalog, runtime_bundle_cid).map(index => {
    catalog.entries[index]
  })
  let revision = match entry {
    Some(value) => {
      let revision : Int = @string.from_str(
        @bundle.bundle_record_projection(value.record)[0],
      ) catch {
        _ => return Err(StateCollision)
      }
      Some(revision)
    }
    None => None
  }
  let observation = match catalog.catalog_incarnation {
    Some(incarnation) =>
      match entry {
        Some(value) if value.reclaim_pending => @bundle.BundleHoldUnavailable
        _ =>
          @bundle.observe_bundle_hold(
            incarnation,
            entry.map(value => value.record),
            binding,
            exact,
          )
      }
    None => @bundle.BundleHoldUnavailable
  }
  Ok({
    binding_cid,
    runtime_bundle_cid,
    observation,
    catalog_incarnation: catalog.catalog_incarnation,
    record_revision: revision,
  })
}

///|
pub fn NativeRuntimeBundleStore::inspect_member_hold(
  self : NativeRuntimeBundleStore,
  binding : @bundle.RemoteBundleHoldBinding,
) -> Result[NativeRuntimeBundleHoldReceipt, NativeRuntimeBundleStoreIssue] {
  let catalog = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let receipt = match member_receipt(catalog, binding) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if receipt.observation == @bundle.BundleHoldRetained ||
    receipt.observation == @bundle.BundleHoldUnresolved {
    guard entry_index(catalog, receipt.runtime_bundle_cid) is Some(index) else {
      return Err(StateCollision)
    }
    if verify_component(self, catalog.entries[index]) is Err(_) {
      return Ok({ ..receipt, observation: @bundle.BundleHoldUnavailable, })
    }
  }
  Ok(receipt)
}

///|
pub fn NativeRuntimeBundleStore::retain_member(
  self : NativeRuntimeBundleStore,
  binding : @bundle.RemoteBundleHoldBinding,
) -> Result[NativeRuntimeBundleHoldReceipt, NativeRuntimeBundleStoreIssue] {
  self.change_member_hold(binding, true)
}

///|
pub fn NativeRuntimeBundleStore::release_member(
  self : NativeRuntimeBundleStore,
  binding : @bundle.RemoteBundleHoldBinding,
) -> Result[NativeRuntimeBundleHoldReceipt, NativeRuntimeBundleStoreIssue] {
  self.change_member_hold(binding, false)
}

///|
fn NativeRuntimeBundleStore::change_member_hold(
  self : NativeRuntimeBundleStore,
  binding : @bundle.RemoteBundleHoldBinding,
  retain : Bool,
) -> Result[NativeRuntimeBundleHoldReceipt, NativeRuntimeBundleStoreIssue] {
  let current = match load_catalog(self) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let receipt = match member_receipt(current, binding) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if receipt.observation == @bundle.BundleHoldUnavailable ||
    receipt.observation == @bundle.BundleHoldFenced {
    return Ok(receipt)
  }
  guard entry_index(current, receipt.runtime_bundle_cid) is Some(index) &&
    current.catalog_incarnation is Some(incarnation) else {
    return Err(StateCollision)
  }
  let entry = current.entries[index]
  if retain {
    if verify_component(self, entry) is Err(_) {
      return Ok({ ..receipt, observation: @bundle.BundleHoldUnavailable, })
    }
    if receipt.observation == @bundle.BundleHoldRetained {
      return Ok(receipt)
    }
  }
  let transition = match
    bundle_result(
      if retain {
        @bundle.prepare_bundle_hold_retain(
          incarnation,
          active_cid(current),
          entry.record,
          binding,
          self.max_owners,
        )
      } else if receipt.observation == @bundle.BundleHoldRetained {
        @bundle.prepare_bundle_release(entry.record)
      } else {
        @bundle.prepare_bundle_hold_fence(
          incarnation,
          entry.record,
          binding,
          false,
        )
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let hold_id = member_hold_id(binding)
  let holds = entry.holds.filter(hold => hold.hold_id != hold_id)
  if retain {
    let body = match bundle_result(@bundle.bundle_hold_binding_json(binding)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    holds.push({ hold_id, kind: "workspace-set", binding_body: Some(body), })
  }
  let replacement = match
    after_transition(entry, transition, holds, entry.reclaim_pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let next = with_catalog_revision(
    current,
    active_cid(current),
    replace_entry(current.entries, index, replacement),
  )
  match persist_catalog(self, current, next) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match bundle_result(@bundle.commit_bundle_transition(transition, true)) {
    Ok(_) => member_receipt(next, binding)
    Err(issue) => Err(issue)
  }
}
