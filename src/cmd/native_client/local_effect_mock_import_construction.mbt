///|
// A continuation of the SAME member's construction reservation. The recipe
// contains the original checked-row/id terms; this record never supplies rows,
// selects another occurrence, grants an attempt or refunds failed work.
priv struct LocalNativeMockEffectImportConstruction {
  operation : @local_values.ClientInstalledEffectOperationBorrow
  mut recipe : Array[@execution.ExecutionCapacity]
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
  if !self.prepare_canonical(
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
// PublicationContract/RunEvidenceValue and CapturedEffectDependencyBody return
// immutable span-free canonical values, original wire and typed edge records.
// Their Source parser/index/NFC controls cannot escape. Keep the COMPLETE old
// construction/failure peak, but only these actual returned families accumulate
// beside later constructors. The row decoder below keeps its separate recipe.
fn native_mock_effect_canonical_body_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  guard native_mock_effect_dependency_body_capacity(bytes, nodes, depth)
    is Some(peak) &&
    @source.json_tree_retained_construction_extent(
      nodes,
      nodes - 1,
      nodes,
      0,
      bytes.to_int64(),
      keep_spans=false,
    )
    is Some(tree) &&
    @execution.preparation_representation_cost({
      // One body/node/wire/contract wrapper family and at most one typed
      // dependency-reference record per original JSON node. Reference strings
      // borrow the SAME canonical tree; the original wire remains alongside it.
      record_headers: tree.record_headers + 8L + nodes.to_int64(),
      reference_slots: tree.reference_slots + 32L + 4L * nodes.to_int64(),
      scalar_words: tree.scalar_words + 8L,
      owned_utf16_units: tree.owned_utf16_units + bytes.to_int64() + 71L,
      owned_wire_bytes: bytes.to_int64(),
    })
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      retained,
      @execution.execution_capacity_execution_bytes(peak) -
      @execution.execution_capacity_retained_bytes(peak),
      1L,
    )
    is Some(complete) else {
    return None
  }
  @execution.execution_capacity(
    retained,
    Int64::max(complete, @execution.execution_capacity_execution_bytes(peak)),
  )
}

///|
fn LocalNativeMockEffectImportConstruction::prepare_canonical(
  self : Self,
  original : LocalCommandPreparationOriginal,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Bool {
  self.prepare_body(
    original,
    native_mock_effect_canonical_body_capacity(bytes, nodes, depth),
  )
}

///|
fn LocalNativeMockEffectImportConstruction::prepare(
  self : Self,
  original : LocalCommandPreparationOriginal,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Bool {
  self.prepare_body(
    original,
    native_mock_effect_dependency_body_capacity(bytes, nodes, depth),
  )
}

///|
fn LocalNativeMockEffectImportConstruction::prepare_body(
  self : Self,
  original : LocalCommandPreparationOriginal,
  capacity : @execution.ExecutionCapacity?,
) -> Bool {
  guard capacity is Some(body) &&
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
  if !self.resize(original, capture, self.retained, self.workspace) {
    return false
  }
  self.recipe = capture
  true
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

///|
// The original producer wire is borrowed. Fund its preserving row decoder and
// retained cells on the SAME capture before the bridge allocates them. The
// existing normalizing body recipe conservatively covers this decoder too.
fn LocalNativeMockEffectImportConstruction::prepare_row(
  self : Self,
  original : LocalCommandPreparationOriginal,
  wire : String,
  limits : @execution.RetainedRowDecodeLimits,
) -> Bool {
  guard @scalar.admit_utf8_length(wire, limits.max_bytes) is Ok(bytes) else {
    original.retain_primary(
      CommandBusinessEffectProposals(ManagedExport(Bridge(Wire(InputLimit)))),
    )
    return false
  }
  self.prepare(
    original,
    Int::max(1, bytes),
    Int::min(limits.max_nodes, Int::max(1, bytes)),
    Int::min(limits.max_depth, Int::max(1, bytes)),
  )
}

///|
fn LocalCommandBusinessPreparation::prepare_mock_effect_local_result_export(
  self : Self,
  state : LocalNativeMockEffectPlan,
  held : LocalNativeMockEffectProposals,
  index : Int,
) -> @local_values.LocalValuesEffectResultExport raise ClientStop {
  guard state.suffix is Some(execution) &&
    state.effect_capture is Some(captured) &&
    held.construction is Some(construction) else {
    stop("LocalOriginalEffectImportsUnavailable")
  }
  let limits = state.first._retained_models[0]._retained_limits
  let wire = limits.identity.wire
  let bridge = held.bridge_limits
  let row = bridge.row
  execution
  .prepare_effect_result_export(
    captured,
    held.inputs,
    index,
    row,
    bridge.entries,
    bridge.name_bytes,
    {
      max_result_fields: wire.max_columns,
      max_result_mapping_work: wire.max_order_work,
      max_result_order_work: wire.max_order_work,
      max_result_workspace_entries: limits.output_workspace,
      max_rows: limits.output_rows,
      values: limits.output_values,
      payload_wire: wire,
      logical_wire: limits.identity.logical_wire,
      schema: limits.identity.schema,
      max_batch_bytes: Int::min(wire.max_bytes, 16384),
    },
    before_row=Some(text => construction.prepare_row(self.original, text, row)),
  )
  .map_err(issue => LocalNativeMockEffectProposalIssue::ManagedExport(issue))
  .native_effect_proposal(self.original)
}

///|
// Cells and acquired Sources retain their own original completion. The SAME
// capture construction still backs the bounded export; it does not decode a
// second managed row stream or borrow an unrelated suffix operation.
fn LocalCommandBusinessPreparation::prepare_mock_effect_direct_result_export(
  self : Self,
  state : LocalNativeMockEffectPlan,
  held : LocalNativeMockEffectProposals,
  index : Int,
) -> @strategy.CapturedEffectLocalResultExport raise ClientStop {
  guard state.suffix is Some(_) &&
    state.effect_capture is Some(_) &&
    held.construction is Some(_) else {
    stop("LocalOriginalEffectImportsUnavailable")
  }
  let limits = state.first._retained_models[0]._retained_limits
  let wire = limits.identity.wire
  @strategy.start_captured_effect_local_result_export(
    held.inputs,
    index,
    {
      max_fields: wire.max_columns,
      max_mapping_work: wire.max_order_work,
      max_order_work: wire.max_order_work,
      max_workspace_entries: limits.output_workspace,
    },
    limits.output_rows,
    limits.output_values,
    wire,
    limits.identity.logical_wire,
    limits.identity.schema,
    Int::min(wire.max_bytes, 16384),
  )
  .map_err(issue => {
    LocalNativeMockEffectProposalIssue::ManagedExport(Binding(issue))
  })
  .native_effect_proposal(self.original)
}
