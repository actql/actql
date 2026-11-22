///|
// A continuation of the SAME member's construction reservation. The recipe
// contains the original checked-row/id terms; this record never supplies rows,
// selects another occurrence, grants an attempt or refunds failed work.
priv struct LocalNativeMockEffectImportConstruction {
  operation : @local_values.ClientInstalledEffectOperationBorrow
  mut recipe : Array[@execution.ExecutionCapacity]
  mut retained : Int64
  mut workspace : Int64
  // Borrowed only by one acquired Source snapshot. Failure leaves the active
  // extent on the original operation until command cleanup.
  mut source_snapshot : Int64?
  // Live only inside one synchronous Source export, including on failure
  // until that same operation's cleanup. Other exports are retained below.
  mut source_copy : Int64?
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
// The measuring sink owns one Writer, its geometry state, and its returned
// counters. Quote the full original policy here before measuring the actual
// definition. The fixed recipe continues to fund checked name validation.
fn LocalNativeMockEffectImportConstruction::issue_result_definition(
  self : Self,
  original : LocalCommandPreparationOriginal,
  prepared : @run_host.PreparedClientEffectComputation,
  unit : Int,
  name : String,
) -> @run_host.ClientEffectLocalResultDefinition raise ClientStop {
  let max_bytes = 16384
  let max_nodes = 1024
  let max_depth = 20
  let measuring = @encode.measuring_writer_construction_extent(
      max_nodes, max_depth,
    )
    .bind(extent => {
      @execution.preparation_representation_cost({
        record_headers: extent.record_headers + 3L,
        reference_slots: extent.reference_slots + 2L,
        scalar_words: extent.scalar_words + 14L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
    })
    .bind(workspace => @execution.execution_capacity(0L, workspace))
  if !self.prepare_body(original, measuring) {
    stop("LocalOriginalEffectProposalsUnavailable")
  }
  let geometry = @run_host.client_effect_local_result_definition_construction_geometry(
      prepared, unit, name, max_bytes, max_nodes, max_depth,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Definition(issue))
    .native_effect_proposal(original)
  if !self.prepare_body(
      original,
      @run_host.client_effect_local_result_definition_issuer_capacity(geometry),
    ) {
    stop("LocalOriginalEffectProposalsUnavailable")
  }
  @run_host.issue_client_effect_local_result_definition(
    prepared, unit, name, max_bytes, max_nodes, max_depth,
  )
  .map_err(issue => LocalNativeMockEffectProposalIssue::Definition(issue))
  .native_effect_proposal(original)
}

///|
// Contracts are measured sequentially on the fixed recipe's existing
// construction reservation. Only one depth stack and extent carrier live.
fn native_mock_effect_contract_extent_walk_capacity(
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  let frames = 4L * (max_depth.to_int64() + 1L) + 16L
  @execution.preparation_representation_cost({
    record_headers: 12L + frames,
    reference_slots: 24L + 4L * frames,
    scalar_words: 16L + 4L * frames,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).bind(workspace => @execution.execution_capacity(0L, workspace))
}

///|
// Keep the fixed issuance budget and fund the bounded post-issuer walk.
fn LocalNativeMockEffectImportConstruction::retain_result_artifact(
  self : Self,
  original : LocalCommandPreparationOriginal,
  artifact : @run_host.ClientEffectLocalResultArtifact,
  max_nodes : Int,
  max_depth : Int,
) -> Unit raise ClientStop {
  if !self.prepare_body(
      original,
      native_mock_effect_contract_extent_walk_capacity(max_depth),
    ) {
    stop("LocalOriginalEffectProposalsUnavailable")
  }
  let backing = @run_host.client_effect_local_result_artifact_retained_bytes(
    artifact, max_nodes, max_depth,
  ).bind(retained => @execution.execution_capacity(retained, retained))
  if !self.prepare_body(original, backing) {
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
// Snapshot emission returns only its row text. The stepper, writer and
// discarded field vector cannot escape. Keep the entire former constructor
// peak before entry, and carry only the returned wire into later dependency
// admission. This reuses logical workspace without releasing physical backing.
fn LocalNativeMockEffectImportConstruction::prepare_snapshot(
  self : Self,
  original : LocalCommandPreparationOriginal,
  bytes : Int,
  nodes : Int,
  depth : Int,
  previous_workspace_returned? : Bool = false,
) -> Bool {
  let capacity = native_mock_effect_dependency_body_capacity(
    bytes, nodes, depth,
  ).bind(peak => {
    // The original logical wire also includes the Relation wrapper, so its
    // measured UTF-8 bytes bound every UTF-16 unit in the returned rows.
    @execution.preparation_representation_cost({
      record_headers: 2L,
      reference_slots: 2L,
      scalar_words: 2L,
      owned_utf16_units: bytes.to_int64(),
      owned_wire_bytes: 0L,
    }).bind(retained => {
      @execution.execution_capacity(
        retained,
        Int64::max(
          retained,
          @execution.execution_capacity_execution_bytes(peak),
        ),
      )
    })
  })
  if self.source_snapshot is Some(_) && capacity is Some(value) {
    return self.reserve_source_snapshot(
      original,
      @execution.execution_capacity_retained_bytes(value),
      @execution.execution_capacity_execution_bytes(value),
    )
  }
  self.prepare_body(original, capacity, previous_workspace_returned~)
}

///|
// The fixed recipe and the next synchronous constructor share a workspace,
// but either can coexist with the still-open Source snapshot. Reuse the same
// committed execution peak across successive snapshots, without a Ledger refund.
fn native_mock_effect_import_workspace(
  fixed : @execution.ExecutionCapacity,
  high_water : Int64,
  live_snapshot : Int64,
  constructor_workspace : Int64,
  source_copy? : Int64 = 0L,
) -> Int64? {
  let fixed_workspace = @execution.execution_capacity_execution_bytes(fixed) -
    @execution.execution_capacity_retained_bytes(fixed)
  guard @execution.checked_preparation_add_product(
      live_snapshot, source_copy, 1L,
    )
    is Some(live) else {
    return None
  }
  @execution.checked_preparation_add_product(
    live,
    Int64::max(fixed_workspace, constructor_workspace),
    1L,
  ).map(required => Int64::max(high_water, required))
}

///|
fn LocalNativeMockEffectImportConstruction::reserve_source_snapshot(
  self : Self,
  original : LocalCommandPreparationOriginal,
  additional : Int64,
  constructor_workspace : Int64,
) -> Bool {
  let source_copy = self.source_copy.unwrap_or(0L)
  guard self.source_snapshot == Some(0L) &&
    @execution.checked_preparation_add_product(
      source_copy, constructor_workspace, 1L,
    )
    is Some(snapshot_peak) &&
    native_mock_effect_import_workspace(
      self.recipe[0],
      Int64::max(self.workspace, snapshot_peak),
      additional,
      0L,
      source_copy~,
    )
    is Some(workspace) else {
    original.retain_primary(
      CommandBusinessEffectProposals(Managed(InsufficientCapacity)),
    )
    return false
  }
  if !self.resize(original, self.recipe, self.retained, workspace) {
    return false
  }
  self.source_snapshot = Some(additional)
  true
}

///|
fn LocalNativeMockEffectImportConstruction::prepare_body(
  self : Self,
  original : LocalCommandPreparationOriginal,
  capacity : @execution.ExecutionCapacity?,
  previous_workspace_returned? : Bool = false,
) -> Bool {
  self
  .prepare_body_result(capacity, previous_workspace_returned~)
  .retain_mock_effect_proposal_issue(issue => {
    original.retain_primary(CommandBusinessEffectProposals(issue))
  })
}

///|
fn LocalNativeMockEffectImportConstruction::prepare_body_result(
  self : Self,
  capacity : @execution.ExecutionCapacity?,
  previous_workspace_returned? : Bool = false,
) -> Result[Unit, LocalNativeMockEffectProposalIssue] {
  if previous_workspace_returned &&
    (self.source_snapshot is Some(_) || self.source_copy is Some(_)) {
    return Err(Managed(InsufficientCapacity))
  }
  // Only a synchronous caller that has returned its whole previous workspace
  // can rebase the relative peak. The installed absolute peak remains held.
  let previous_workspace = if previous_workspace_returned {
    0L
  } else {
    self.workspace
  }
  guard capacity is Some(body) &&
    @execution.checked_preparation_add_product(
      self.retained,
      @execution.execution_capacity_retained_bytes(body),
      1L,
    )
    is Some(retained) &&
    native_mock_effect_import_workspace(
      self.recipe[0],
      previous_workspace,
      self.source_snapshot.unwrap_or(0L),
      @execution.execution_capacity_execution_bytes(body) -
      @execution.execution_capacity_retained_bytes(body),
      source_copy=self.source_copy.unwrap_or(0L),
    )
    is Some(workspace) else {
    return Err(Managed(InsufficientCapacity))
  }
  self.resize_result(self.recipe, retained, workspace)
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
  self
  .resize_result(basis, retained, workspace)
  .retain_mock_effect_proposal_issue(issue => {
    original.retain_primary(CommandBusinessEffectProposals(issue))
  })
}

///|
fn LocalNativeMockEffectImportConstruction::resize_result(
  self : Self,
  basis : Array[@execution.ExecutionCapacity],
  retained : Int64,
  workspace : Int64,
) -> Result[Unit, LocalNativeMockEffectProposalIssue] {
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
    return Err(Managed(InsufficientCapacity))
  }
  let recipe = basis.copy()
  recipe[0] = fixed
  let result = @local_values.prepare_installed_effect_capture_recipe_extent(
    "native.mock.file.capture", recipe,
  ).bind(input => {
    @local_values.grow_installed_effect_operation_input(
      self.operation,
      input,
      reuse_execution_peak=true,
    )
  })
  match result {
    Err(issue) => Err(Managed(issue))
    Ok(_) => {
      self.retained = retained
      self.workspace = workspace
      Ok(())
    }
  }
}

///|
fn Result::retain_mock_effect_proposal_issue(
  self : Result[Unit, LocalNativeMockEffectProposalIssue],
  report : (LocalNativeMockEffectProposalIssue) -> Unit,
) -> Bool {
  match self {
    Ok(_) => true
    Err(issue) => {
      report(issue)
      false
    }
  }
}

///|
// Each bridge keeps its own copied prefix on the capture reservation. The
// decoder returns before the next synchronous constructor can start, so its
// workspace can reuse the same peak. Other live capture inputs stay charged.
fn LocalNativeMockEffectImportConstruction::reserve_row_copy(
  self : Self,
  additional : Int64,
  decoder : Int64,
) -> Result[Unit, LocalNativeMockEffectProposalIssue] {
  guard @execution.checked_preparation_add_product(
      self.retained,
      additional,
      1L,
    )
    is Some(retained) &&
    native_mock_effect_import_workspace(
      self.recipe[0],
      self.workspace,
      self.source_snapshot.unwrap_or(0L),
      decoder,
      source_copy=self.source_copy.unwrap_or(0L),
    )
    is Some(workspace) else {
    return Err(Managed(InsufficientCapacity))
  }
  self.resize_result(self.recipe, retained, workspace)
}

///|
// Source import closes this private copy before the enclosing constructor
// returns. Charge its whole live prefix alongside the current scratch and
// the retained artifacts, without accumulating earlier, closed copies.
fn LocalNativeMockEffectImportConstruction::reserve_source_row_copy(
  self : Self,
  additional : Int64,
  decoder : Int64,
) -> Result[Unit, LocalNativeMockEffectProposalIssue] {
  guard self.source_copy is Some(prior) &&
    @execution.checked_preparation_add_product(prior, additional, 1L)
    is Some(source_copy) &&
    native_mock_effect_import_workspace(
      self.recipe[0],
      self.workspace,
      self.source_snapshot.unwrap_or(0L),
      decoder,
      source_copy~,
    )
    is Some(workspace) else {
    return Err(Managed(InsufficientCapacity))
  }
  match self.resize_result(self.recipe, self.retained, workspace) {
    Err(issue) => Err(issue)
    Ok(_) => {
      self.source_copy = Some(source_copy)
      Ok(())
    }
  }
}

///|
fn LocalCommandBusinessPreparation::prepare_mock_effect_local_result_export(
  self : Self,
  state : LocalNativeMockEffectPlan,
  held : LocalNativeMockEffectProposals,
  index : Int,
  scoped_source_copy? : Bool = false,
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
  // The synchronous bridge first reserves its startup controls, then offers
  // copied prefixes. Startup stays on the retained lane for every export.
  let mut started = false
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
    reserve_row_copy=Some((bytes, decoder) => {
      let result = if scoped_source_copy && started {
        construction.reserve_source_row_copy(bytes, decoder)
      } else {
        construction.reserve_row_copy(bytes, decoder)
      }
      started = true
      result.retain_mock_effect_proposal_issue(issue => {
        self.original.retain_primary(CommandBusinessEffectProposals(issue))
      })
    }),
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

///|
// Only the pair and its two Strings cross the projection's synchronous return.
// The fixed member inventory already keeps the array wrapper and one backing
// header. With growth, charge the exact new spare slots before replacement;
// the old backing header and slots remain live until that replacement returns.
fn LocalNativeMockEffectImportConstruction::append_proposal_row(
  self : Self,
  rows : Array[(String, String)],
  proposal : (String, String),
) -> Result[Unit, LocalNativeMockEffectProposalIssue] {
  let previous = rows.capacity()
  guard @shape.reference_array_push_construction_extent(rows.length(), previous)
    is Some(growth) &&
    growth.reference_slots <= 2147483647L else {
    return Err(Managed(InsufficientCapacity))
  }
  let next = if growth.record_headers == 0L {
    previous
  } else {
    growth.reference_slots.to_int()
  }
  guard @execution.preparation_execution_capacity({
      retained: {
        record_headers: 3L,
        reference_slots: 2L + (next - previous).to_int64(),
        scalar_words: 2L,
        owned_utf16_units: proposal.0.length().to_int64() +
        proposal.1.length().to_int64(),
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: growth.record_headers,
        reference_slots: if next == previous {
          0L
        } else {
          previous.to_int64()
        },
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(capacity) else {
    return Err(Managed(InsufficientCapacity))
  }
  match self.prepare_body_result(Some(capacity)) {
    Err(issue) => Err(issue)
    Ok(_) => {
      rows.reserve_capacity(next)
      rows.push(proposal)
      Ok(())
    }
  }
}

///|
// The checked export can sort two growing index arrays at once. The selected
// order remains with the finished view and its snapshot; the other array and
// replacement buffers unwind during preparation. Existing fixed capture
// backing continues to fund schema/column metadata and comparison controls.
fn native_mock_effect_proposal_order_capacity(
  rows : Int,
) -> @execution.ExecutionCapacity? {
  if rows < 0 {
    return None
  }
  let count = rows.to_int64()
  let slots = if rows == 0 { 0L } else { Int64::max(8L, 2L * count) }
  guard @shape.collection_construction_extent({
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 2L,
      scalar_items: 2L * count,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(peak) &&
    @execution.preparation_representation_cost({
      record_headers: peak.record_headers,
      reference_slots: peak.reference_slots,
      scalar_words: peak.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(execution) &&
    @execution.preparation_representation_cost({
      record_headers: 2L,
      reference_slots: 1L,
      scalar_words: 2L + slots,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(retained) else {
    return None
  }
  @execution.execution_capacity(retained, execution)
}
