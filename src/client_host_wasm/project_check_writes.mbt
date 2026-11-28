///|
// The actual original Mapping and its publication's installation stamps.
// Both the Check and prepared Request keep the same Project parent pinned.
priv struct StoredMockProjectWriteTarget {
  source : StoredMockProjectSource
  write : @row_host.ProjectMockWriteDeclaration
  target : String
  binding_cid : String
  owner_cid : String
  mut preparation : StoredMockProjectTargetContract?
}

///|
priv struct StoredMockProjectTargetContract {
  data : Bytes
  row : @row_host.ProjectMockRowSelection
  limits : @row_host.RowPageLimits
  raw_limits : @row_host.RowPageLimits
  contract : @row_host.RelationDocumentPreparedContract
  extent : @local_host.ClientInstalledEffectOperationExtent
}

///|
fn retain_mock_project_write_target(
  value : Instance,
  held : StoredMockProjectCheck,
  source : StoredMockProjectSource,
  write : @row_host.ProjectMockWriteDeclaration,
  target : String,
  binding_cid : String,
  owner_cid : String,
) -> Bool {
  let targets = held.write_targets
  // Keep the projected target/CIDs after the alias constructor discards its
  // JSON. Include both backings during growth of the fixed owner's array.
  let units : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 10L,
    scalar_words: 0L,
    owned_utf16_units: target.length().to_int64() +
    binding_cid.length().to_int64() +
    owner_cid.length().to_int64(),
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(units) is Some(bytes) &&
    @execution.checked_preparation_add_product(
      held.write_target_bytes,
      1L,
      bytes,
    )
    is Some(retained) &&
    grow_mock_project_check(value, held, units) else {
    return false
  }
  held.write_target_bytes = retained
  targets.push({
    source,
    write,
    target,
    binding_cid,
    owner_cid,
    preparation: None,
  })
  true
}

///|
// Check and update publication must disclose the same admitted Mapping. An
// alias does not grant an Effect, approve it or supply a physical writer.
fn mock_project_write_visible(
  account : @authorization.AdmittedAccountConfiguration,
  principal : String,
  source : StoredMockProjectSource,
  write : @row_host.ProjectMockWriteDeclaration,
) -> Bool {
  @authorization.evaluate_account(account, {
    principal,
    connection: source.connection,
    resource: write.mapping.resource,
    operation: "effect",
  })
  is Delegate(_)
}

///|
fn project_mock_update_aliases(
  value : Instance,
  held : StoredMockProjectCheck,
  current : StoredRunConfiguration,
  account : @authorization.AdmittedAccountConfiguration,
  inputs : StoredMockProjectInputs,
  installation : (String, String),
) -> Result[Array[Json], Int] {
  let (runtime, data_path) = installation
  guard current.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(original) &&
    original.material is Some(material) else {
    return Err(-2)
  }
  let result : Array[Json] = []
  let catalog = inputs.catalog.original_wire()
  let principal = current.tuple.principal
  for source in inputs.sources {
    if !source.writes.any(write => {
        mock_project_write_visible(account, principal, source, write)
      }) {
      continue
    }
    guard @host.mock_project_check_update_alias_inventory(
        catalog,
        data_path,
        source.connection,
        source.provider,
        source.relation,
        source.writes,
      )
      is Some(quote) &&
      grow_mock_project_check(value, held, quote) else {
      return Err(-4)
    }
    let scope = match
      @host.client_local_adopted_authority_scope_body(
        material,
        original.store,
        principal,
        source.connection,
        retain=false,
      ) {
      Ok(scope) => "sha256:" + @sha.hex(scope)
      Err(issue) => return Err(host_current_issue(issue))
    }
    guard @host.client_project_mock_declared_file_scope(
        source.connection,
        source.provider,
        data_path,
        catalog,
      )
      is Ok(source_scope) &&
      @host.client_project_mock_write_binding_cid(
        source_scope,
        scope,
        source.writes,
      )
      is Ok(binding) &&
      @host.client_project_mock_write_installation(
        source.relation,
        source.connection,
        runtime,
        binding,
      )
      is Ok((owner, _)) else {
      return Err(-20)
    }
    for write in source.writes {
      if mock_project_write_visible(account, principal, source, write) {
        guard @host.client_project_mock_write_target(write) is Some(target) else {
          return Err(-20)
        }
        if !write.aliases.is_empty() &&
          !retain_mock_project_write_target(
            value, held, source, write, target, binding, owner,
          ) {
          return Err(-4)
        }
        for name in write.aliases {
          result.push(
            @host.client_project_mock_write_alias(name, target, binding, owner),
          )
        }
      }
    }
  }
  Ok(result)
}

///|
// Read the compiler's concrete UPDATE set and relate each occurrence to the
// exact installed declaration used during publication. This does not derive
// installation CIDs again or supply an Effect grant or physical writer.
fn check_mock_project_effect_plan_targets(
  value : Instance,
  configuration : StoredRunConfiguration,
  check : StoredMockProjectCheck,
  prepared : @host.PreparedClientEffectComputation,
  selected_target : (
    @host.ClientEffectUpdateTargetSelection,
    StoredMockProjectWriteTarget,
  ) -> Int,
) -> Int {
  guard configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) &&
    current.account is Some(account) &&
    check.runtime_cid is Some(_) &&
    @host.prepared_client_effect_update_target_count(prepared) is Some(count) else {
    return -20
  }
  let mut remaining = @host.client_standard_effect_computation_limits().effects.max_work -
    count
  if remaining < 0 {
    return -10
  }
  for index in 0..<count {
    guard @host.prepared_client_effect_target_selection_at(prepared, index)
      is Some(checked_target) else {
      return -2
    }
    let mut selected : StoredMockProjectWriteTarget? = None
    for original in check.write_targets {
      if remaining == 0 {
        return -10
      }
      remaining -= 1
      if original.target == checked_target.target_ref &&
        original.write.mapping.mapping_ref == checked_target.mapping_ref &&
        original.write.mapping.mapping_cid == checked_target.mapping_cid &&
        original.binding_cid == checked_target.installation_binding_cid &&
        original.owner_cid == checked_target.installation_owner_cid {
        if selected is Some(_) {
          return -2
        }
        selected = Some(original)
      }
    }
    guard selected is Some(original) else { return -2 }
    if !mock_project_write_visible(
        account,
        configuration.tuple.principal,
        original.source,
        original.write,
      ) {
      return -20
    }
    let code = selected_target(checked_target, original)
    if code != 0 {
      return code
    }
  }
  0
}
