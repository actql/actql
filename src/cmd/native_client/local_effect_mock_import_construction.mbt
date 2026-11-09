///|
// A continuation of the SAME member's construction reservation. The recipe
// contains the original checked-row/id terms; this record never supplies rows,
// selects another occurrence, grants an attempt or refunds failed work.
priv struct LocalNativeMockEffectImportConstruction {
  operation : @local_values.ClientInstalledEffectOperationBorrow
  recipe : Array[@execution.ExecutionCapacity]
  mut retained : Int64
  mut workspace : Int64
}

///|
fn native_mock_effect_capture_operation(
  run : @local_values.ClientInstalledManagedRun,
  prepared : @run_host.PreparedClientEffectComputation,
  request : @run_host.ClientRequestIdentity,
  plan : @local_values.ClientInstalledEffectManagedPlan,
  entry : Int,
) -> Result[
  @local_values.ClientInstalledEffectOperationBorrow,
  @local_values.ClientInstalledManagedRunIssue,
] {
  if entry == 0 {
    @local_values.retain_installed_effect_operation_construction(
      run, prepared, request, plan, entry, false, 0, 0, "native.mock.file.capture",
    )
  } else {
    @local_values.borrow_installed_effect_operation(
      run, prepared, request, plan, entry, false, 0, 0, "native.mock.file.capture",
    )
  }
}

///|
// The initial recipe holds the largest single issuer's simultaneous bounded
// documents. After it returns, retain the exact returned wire envelope before
// reusing that constructor margin. Immutable getters do not parse/hash again.
fn LocalNativeMockEffectImportConstruction::retain_wire(
  self : Self,
  original : LocalCommandPreparationOriginal,
  wire : String,
) -> Unit raise ClientStop {
  let bytes = @scalar.admit_utf8_length(wire, 16384).unwrap_or_else(() => {
    original.retain_primary(
      CommandBusinessEffectProposals(Managed(InsufficientCapacity)),
    )
    stop("LocalOriginalEffectProposalsUnavailable")
  })
  if !self.prepare(
      original,
      Int::max(1, bytes),
      Int::min(1024, Int::max(1, bytes)),
      Int::min(20, Int::max(1, bytes)),
    ) {
    stop("LocalOriginalEffectProposalsUnavailable")
  }
}

///|
// The dependency parser actually normalizes keys. Preserve that constructor's
// complete inventory, plus its owned wire/UTF8 conversion and body carriers.
// Dimensions come from an original immutable wire, not business policy.
fn native_mock_effect_dependency_body_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  guard @execution.execution_capacity(0L, 0L) is Some(empty) &&
    @local_values.installed_json_effect_response_construction_capacity(
      empty, bytes, nodes, depth,
    )
    is Some(decoded) &&
    @execution.preparation_representation_cost({
      record_headers: 4L,
      reference_slots: 6L + nodes.to_int64(),
      scalar_words: 2L,
      owned_utf16_units: bytes.to_int64(),
      owned_wire_bytes: bytes.to_int64(),
    })
    is Some(wire) &&
    @execution.execution_capacity(wire, wire) is Some(encoded) else {
    return None
  }
  @execution.add_execution_capacity(decoded, encoded)
}

///|
fn LocalNativeMockEffectImportConstruction::prepare(
  self : Self,
  original : LocalCommandPreparationOriginal,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Bool {
  guard native_mock_effect_dependency_body_capacity(bytes, nodes, depth)
    is Some(body) &&
    @execution.checked_preparation_add_product(
      self.retained,
      @execution.execution_capacity_retained_bytes(body),
      1L,
    )
    is Some(retained) else {
    original.retain_primary(
      CommandBusinessEffectProposals(Managed(InsufficientCapacity)),
    )
    return false
  }
  let workspace = Int64::max(
    self.workspace,
    @execution.execution_capacity_execution_bytes(body) -
    @execution.execution_capacity_retained_bytes(body),
  )
  self.resize(original, self.recipe, retained, workspace)
}

///|
fn LocalNativeMockEffectImportConstruction::finish(
  self : Self,
  original : LocalCommandPreparationOriginal,
  capture : Array[@execution.ExecutionCapacity],
) -> Bool {
  self.resize(original, capture, self.retained, self.workspace)
}

///|
// Absolute same-operation growth. Keep all returned originals summed, while
// these synchronous phases reuse only their private construction workspace.
fn LocalNativeMockEffectImportConstruction::resize(
  self : Self,
  original : LocalCommandPreparationOriginal,
  basis : Array[@execution.ExecutionCapacity],
  retained : Int64,
  workspace : Int64,
) -> Bool {
  let original_r = @execution.execution_capacity_retained_bytes(basis[0])
  let original_e = @execution.execution_capacity_execution_bytes(basis[0])
  guard @execution.checked_preparation_add_product(original_r, retained, 1L)
    is Some(total_r) &&
    @execution.checked_preparation_add_product(
      total_r,
      Int64::max(original_e - original_r, workspace),
      1L,
    )
    is Some(total_e) &&
    @execution.execution_capacity(total_r, total_e) is Some(fixed) else {
    original.retain_primary(
      CommandBusinessEffectProposals(Managed(InsufficientCapacity)),
    )
    return false
  }
  let recipe = basis.copy()
  recipe[0] = fixed
  let result = @local_values.prepare_installed_effect_capture_recipe_extent(
    "native.mock.file.capture", recipe,
  ).bind(input => {
    @local_values.grow_installed_effect_operation_input(self.operation, input)
  })
  match result {
    Err(issue) => {
      original.retain_primary(CommandBusinessEffectProposals(Managed(issue)))
      false
    }
    Ok(_) => {
      self.retained = retained
      self.workspace = workspace
      true
    }
  }
}
