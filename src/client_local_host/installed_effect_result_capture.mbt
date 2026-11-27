///|
// Private continuation of one checked Result. The captured input pins and
// physical Compute still belong to their original installed Run.
struct InstalledEffectResultCapture {
  execution : LocalValuesExecution
  captured : @strategy.CapturedEffectRunDAG
  inputs : @strategy.CapturedEffectInputs
  index : Int
  limits : @publication_host.PublicationOutputExportLimits
  workspace : Int
  reserve : (@execution.ExecutionCapacity) -> Bool
  refusal : Ref[ClientInstalledManagedRunIssue?]
  schema_workspace : Int64
  mut export_metadata : Int64?
  mut proposals : InstalledEffectResultProposals?
  mut importing : InstalledEffectResultImport?
  mut managed : LocalValuesEffectResultExport?
  mut exported : @strategy.CapturedEffectLocalResultExport?
  mut stream : @execution.CompletedOutputExport?
  mut receipt : @execution.CompletedRelationExportReceipt?
  mut failed : Bool
  mut closed : Bool
}

///|
priv struct InstalledEffectResultImport {
  result : @strategy.CapturedEffectLocalResult
  operations : @local_driver.LocalManagedDispatchOperations[Int]
  completed : @execution.ManagedCompletedOutput[Int]
  bridge : @execution.ManagedPublicationBridge[Int]
  geometry : @execution.ManagedPublicationBridgeLimits
  funding : LocalPublicationBridgeCopyFunding
  refusal : Ref[ClientInstalledManagedRunIssue?]
  mut row : Int
}

///|
pub(all) enum InstalledEffectResultCaptureIssue {
  Unit(ClientEffectUnitPreparationIssue)
  Managed(LocalValuesEffectResultExportIssue)
  Stream(@execution.CompletedExportIssue)
  ProposalPlan(@strategy.CapturedEffectProposalIssue)
  ProposalRow(@strategy.CapturedEffectCheckedProposalIssue)
}

///|
/// Fund an exact captured Result before starting its bridge or view. The
/// same installed Plan quotes the import from the actual managed completion,
/// and the same existing quote backs the Result projection and codec.
pub fn begin_installed_effect_result_capture(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  request : @publication_host.ClientRequestIdentity,
  execution : LocalValuesExecution,
  captured : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectInputs,
  index : Int,
) -> Result[InstalledEffectResultCapture, InstalledEffectResultCaptureIssue] {
  guard !owner.effect_operation_opening &&
    effect_unit_publication_body(owner, plan, request) is Ok(_) &&
    owner.source_free_captured is Some(original) &&
    physical_equal(execution.run, original) &&
    physical_equal(original, @strategy.captured_effect_run_dag(captured)) &&
    owner.effect_operation_controls is Some(control) &&
    control.dependency_inputs is Some(selected) &&
    physical_equal(selected, inputs) &&
    @strategy.captured_effect_inputs_match_run(inputs, captured) &&
    @strategy.captured_effect_local_result_at(inputs, index) is Some(result) else {
    return Err(Unit(Run(ForeignOriginal)))
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  // The cursor, optional single managed importer, exact geometry projection,
  // and the simultaneous success/refusal carriers remain within this prefix.
  guard @execution.preparation_representation_cost({
      // The stepped row visitor also owns one exact original-row token
      // and its typed projection carriers before the retained member copy.
      record_headers: 41L,
      reference_slots: 101L,
      scalar_words: 45L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) &&
    @execution.execution_capacity(bytes, bytes) is Some(fixed) else {
    return Err(Unit(Run(InsufficientCapacity)))
  }
  match reserve_effect_unit_publication_capacity(owner, plan, request, fixed) {
    Err(issue) => return Err(Unit(Run(issue)))
    Ok(_) => ()
  }
  let borrow = @strategy.captured_effect_local_result_borrow(result)
  let managed = if @strategy.captured_any_result_borrow_requires_managed_export(
      borrow,
    ) {
    let (operations, completed, _) = match
      execution.effect_result_export_original(captured, inputs, index) {
      Ok(original) => original
      Err(issue) => return Err(Managed(issue))
    }
    guard (operations.material)() is Some(material) &&
      @execution.managed_publication_bridge_import_geometry(
        completed,
        material,
        plan.capacity_plan.imports.wire.max_columns,
        plan.capacity_plan.imports.wire.max_bytes,
      )
      is Some(geometry) else {
      return Err(Managed(MissingOutput))
    }
    // The measured value depth carries the producer's existing envelope.
    // Its row wrappers do not extend the installed structured decoder limit.
    let row = {
      ..geometry.row,
      max_depth: Int::min(
        geometry.row.max_depth,
        Int::min(plan.capacity_plan.imports.row.max_depth, 64),
      ),
    }
    Some((operations, completed, material, { ..geometry, row, }))
  } else {
    None
  }
  let limits = match
    reserve_installed_effect_result_view(
      owner,
      plan,
      request,
      borrow,
      None,
      measured_codec=true,
    ) {
    Ok(limits) => limits
    Err(issue) => return Err(Unit(issue))
  }
  guard @execution.completed_output_export_workspace_slots(
      limits.values,
      limits.logical_wire,
    )
    is Some(workspace) &&
    @strategy.captured_effect_inputs_match_run(inputs, captured) &&
    execution.available.val else {
    return Err(Unit(Run(Retired)))
  }
  let refusal : Ref[ClientInstalledManagedRunIssue?] = Ref(None)
  let reserve = capacity => {
    match
      reserve_effect_unit_publication_capacity(owner, plan, request, capacity) {
      Ok(_) => true
      Err(issue) => {
        refusal.val = Some(issue)
        false
      }
    }
  }
  let port = @execution.managed_result_occurrence_port(
    @strategy.captured_any_result_borrow_occurrence(borrow),
  )
  guard @strategy.captured_any_result_borrow_row_count(borrow) is Some(rows) else {
    return Err(Unit(Run(ForeignOriginal)))
  }
  let schema_workspace = Ref(0L)
  let reference = @execution.completed_export_reference_capacity(
    @results.port_schema(port),
    Int::min(rows, limits.max_rows),
    limits.payload_wire.max_nodes,
    limits.values,
    count => {
      guard @execution.preparation_array_representation(
          1L,
          count.to_int64(),
          true,
        )
        is Some(array) &&
        @execution.preparation_representation_cost({
          record_headers: array.record_headers,
          reference_slots: array.reference_slots,
          scalar_words: array.scalar_words,
          owned_utf16_units: 0L,
          owned_wire_bytes: 0L,
        })
        is Some(bytes) else {
        return false
      }
      if bytes <= schema_workspace.val {
        return true
      }
      guard @execution.execution_capacity(0L, bytes) is Some(quote) &&
        reserve(quote) else {
        return false
      }
      schema_workspace.val = bytes
      true
    },
  )
  guard reference is Some(reference) && reserve(reference) else {
    return Err(Unit(Run(refusal.val.unwrap_or(InsufficientCapacity))))
  }
  let capture : InstalledEffectResultCapture = {
    execution,
    captured,
    inputs,
    index,
    limits,
    workspace,
    reserve,
    refusal,
    schema_workspace: schema_workspace.val,
    export_metadata: None,
    proposals: None,
    importing: None,
    managed: None,
    exported: None,
    stream: None,
    receipt: None,
    failed: false,
    closed: false,
  }
  match
    prepare_installed_effect_result_proposals(
      owner,
      plan,
      inputs,
      index,
      borrow,
      limits.logical_wire.max_columns,
    ) {
    Ok(proposals) => capture.proposals = proposals
    Err(issue) => return Err(issue)
  }
  if managed is Some((operations, completed, material, geometry)) {
    let imports : @local.LocalImportLimits = {
      max_rows: geometry.max_rows,
      values: geometry.values,
      wire: {
        max_columns: geometry.entries,
        max_order_work: 0,
        max_bytes: geometry.row.max_bytes,
        max_nodes: geometry.row.max_nodes,
        max_depth: geometry.row.max_depth,
      },
      row: geometry.row,
      max_batch_bytes: Int::max(1, geometry.row.max_bytes),
    }
    guard @local.local_materializing_import_start_capacity(imports)
      is Some(start) &&
      @execution.checked_preparation_add_product(
        start, publication_bridge_row_quote_controls, 1L,
      )
      is Some(start) &&
      @execution.execution_capacity(start, start) is Some(fixed) else {
      return Err(Unit(Run(InsufficientCapacity)))
    }
    match
      reserve_effect_unit_publication_capacity(owner, plan, request, fixed) {
      Err(issue) => return Err(Unit(Run(issue)))
      Ok(_) => ()
    }
    let refusal : Ref[ClientInstalledManagedRunIssue?] = Ref(None)
    let reserve = (retained, workspace) => {
      guard @execution.checked_preparation_add_product(retained, workspace, 1L)
        is Some(executing) &&
        @execution.execution_capacity(retained, executing) is Some(capacity) else {
        refusal.val = Some(InsufficientCapacity)
        return false
      }
      match
        reserve_effect_unit_publication_capacity(owner, plan, request, capacity) {
        Ok(_) => true
        Err(issue) => {
          refusal.val = Some(issue)
          false
        }
      }
    }
    let bridge = match
      @execution.prepare_managed_publication_bridge(
        completed,
        material,
        geometry.max_rows,
        geometry.values,
        geometry.entries,
        geometry.name_bytes,
      ) {
      Ok(bridge) => bridge
      Err(issue) => return Err(Managed(Bridge(issue)))
    }
    capture.importing = Some({
      result,
      operations,
      completed,
      bridge,
      geometry,
      funding: { imports, reserve, retained: 0L, decoder: 0L, },
      refusal,
      row: 0,
    })
  } else {
    match
      @strategy.start_captured_effect_local_result_export(
        inputs,
        index,
        {
          max_fields: limits.max_result_fields,
          max_mapping_work: limits.max_result_mapping_work,
          max_order_work: limits.max_result_order_work,
          max_workspace_entries: limits.max_result_workspace_entries,
        },
        limits.max_rows,
        limits.values,
        limits.payload_wire,
        limits.logical_wire,
        limits.schema,
        limits.max_batch_bytes,
      ) {
      Ok(exported) => capture.exported = Some(exported)
      Err(issue) => return Err(Unit(Export(issue)))
    }
  }
  Ok(capture)
}

///|
fn InstalledEffectResultCapture::advance_import(
  self : InstalledEffectResultCapture,
  original : InstalledEffectResultImport,
) -> Result[Bool, InstalledEffectResultCaptureIssue] {
  if original.row < original.geometry.max_rows {
    let wire = match (original.operations.output_row)(original.row) {
      Ok(wire) => wire
      Err(_) => return Err(Managed(MissingOutput))
    }
    if !self.execution.available.val ||
      !@strategy.captured_effect_inputs_match_run(self.inputs, self.captured) {
      return Err(Managed(ForeignInput))
    }
    match
      append_local_publication_bridge_row(
        self.execution.available,
        original.bridge,
        wire,
        original.geometry.row,
        original.row,
        Some(original.funding),
      ) {
      Err(MissingOutput) =>
        return match original.refusal.val {
          Some(issue) => Err(Unit(Run(issue)))
          None => Err(Managed(MissingOutput))
        }
      Err(Bridge(issue)) => return Err(Managed(Bridge(issue)))
      Ok(_) => original.row += 1
    }
    return Ok(false)
  }
  let output = match
    @execution.finish_managed_publication_bridge(original.bridge) {
    Ok(output) => output
    Err(issue) => return Err(Managed(Bridge(issue)))
  }
  let managed = match
    self.execution.bind_effect_result_export(
      self.captured,
      self.inputs,
      self.index,
      original.result,
      original.completed,
      original.bridge,
      output,
      self.limits,
    ) {
    Ok(managed) => managed
    Err(issue) => return Err(Managed(issue))
  }
  self.managed = Some(managed)
  self.importing = None
  guard managed.captured_export() is Some(exported) else {
    return Err(Managed(ForeignInput))
  }
  self.exported = Some(exported)
  Ok(false)
}

///|
// At most one managed row transfer or one bounded view/hash poll. A failed
// step may only be closed. No second Result or full output is materialized.
pub fn InstalledEffectResultCapture::advance(
  self : InstalledEffectResultCapture,
) -> Result[Bool, InstalledEffectResultCaptureIssue] {
  if self.closed || self.failed || self.receipt is Some(_) {
    return Err(Stream(Closed))
  }
  // The caller closes only after its synchronous export has unwound. A trap
  // must leave a refused continuation, rather than a latch blocking cleanup.
  self.failed = true
  let result = self.advance_original()
  if result is Err(_) && self.refusal.val is Some(issue) {
    return Err(Unit(Run(issue)))
  }
  if result is Ok(_) {
    self.failed = false
  }
  result
}

///|
fn InstalledEffectResultCapture::advance_original(
  self : InstalledEffectResultCapture,
) -> Result[Bool, InstalledEffectResultCaptureIssue] {
  if !self.execution.available.val ||
    !@strategy.captured_effect_inputs_match_run(self.inputs, self.captured) {
    return Err(Managed(ForeignInput))
  }
  if self.importing is Some(importing) {
    return self.advance_import(importing)
  }
  guard self.exported is Some(exported) &&
    @strategy.captured_effect_local_result_export_retained(
      self.inputs,
      exported,
    ) else {
    return Err(Managed(ForeignInput))
  }
  if self.stream is Some(stream) {
    guard self.export_metadata is Some(overlap) else {
      return Err(Unit(Run(ForeignOriginal)))
    }
    let fund = capacity => self.reserve_codec_workspace(capacity, overlap)
    let complete = if self.proposals is Some(proposals) {
      match
        self.collect_original_proposal_row(stream, exported, proposals, fund) {
        Ok(complete) => complete
        Err(issue) => return Err(issue)
      }
    } else {
      match
        @execution.advance_completed_output_export_measured(
          stream,
          64,
          self.workspace,
          fund,
        ) {
        Ok(progress) => progress.complete
        Err(issue) => return Err(Stream(issue))
      }
    }
    if !complete {
      return Ok(false)
    }
    match
      @execution.finish_completed_relation_export(
        stream,
        before_finish=Some(fund),
      ) {
      Ok((receipt, _)) => {
        // Own the receipt before any later Resource callback can refuse.
        // The exact survivors exclude the reference index, which was
        // funded separately before opening the export.
        self.receipt = Some(receipt)
        guard @execution.completed_result_export_retained_metadata_capacity(
            @strategy.captured_effect_local_result_export_preparation(exported),
            receipt,
          )
          is Some(retained) &&
          (self.reserve)(retained) else {
          return Err(
            Unit(Run(self.refusal.val.unwrap_or(InsufficientCapacity))),
          )
        }
      }
      Err(issue) => return Err(Stream(issue))
    }
    if self.proposals is Some(proposals) {
      let rows = @execution.completed_relation_export_measurement(
          self.receipt.unwrap(),
        ).row_count
      match proposals.finish(rows) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    return Ok(true)
  }
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  let (ready, _) = match
    @execution.advance_completed_result_relation_export(
      preparation,
      64,
      before_metadata=Some(capacity => {
        self.reserve_codec_workspace(capacity, self.schema_workspace)
      }),
    ) {
    Ok(progress) => progress
    Err(issue) => return Err(Stream(issue))
  }
  if ready {
    match
      @execution.finish_completed_result_relation_export_preparation(
        preparation,
      ) {
      Ok(stream) => {
        self.stream = Some(stream)
        guard @execution.completed_result_export_open_metadata_capacity(
            preparation, stream,
          )
          is Some(open) else {
          return Err(Unit(Run(InsufficientCapacity)))
        }
        self.export_metadata = Some(open.execution_bytes)
      }
      Err(issue) => return Err(Stream(issue))
    }
  }
  Ok(false)
}

///|
fn InstalledEffectResultCapture::collect_original_proposal_row(
  self : InstalledEffectResultCapture,
  stream : @execution.CompletedOutputExport,
  exported : @strategy.CapturedEffectLocalResultExport,
  proposals : InstalledEffectResultProposals,
  fund : (@execution.ExecutionCapacity) -> Bool,
) -> Result[Bool, InstalledEffectResultCaptureIssue] {
  let (complete, next) = match
    @execution.advance_completed_output_export_original_row_measured(
      stream,
      64,
      self.workspace,
      fund,
    ) {
    Ok(progress) => progress
    Err(issue) => return Err(Stream(issue))
  }
  if next is Some(row) {
    defer @execution.retire_completed_output_export_original_row(row)
    if !@strategy.captured_effect_local_result_original_row_available(
        self.inputs,
        exported,
        row,
      ) {
      return Err(Managed(ForeignInput))
    }
    match proposals.collect(exported, row) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if self.closed ||
      !self.execution.available.val ||
      !@strategy.captured_effect_local_result_original_row_available(
        self.inputs,
        exported,
        row,
      ) {
      return Err(Managed(ForeignInput))
    }
  }
  Ok(complete)
}

///|
fn InstalledEffectResultCapture::reserve_codec_workspace(
  self : InstalledEffectResultCapture,
  capacity : @execution.ExecutionCapacity,
  overlap : Int64,
) -> Bool {
  guard @execution.checked_preparation_add_product(
      overlap,
      capacity.execution_bytes,
      1L,
    )
    is Some(bytes) &&
    @execution.execution_capacity(0L, bytes) is Some(quote) else {
    self.refusal.val = Some(InsufficientCapacity)
    return false
  }
  (self.reserve)(quote)
}

///|
/// A receipt and view can only come from the same finished capture.
pub fn InstalledEffectResultCapture::original(
  self : InstalledEffectResultCapture,
) -> (
  @strategy.CapturedEffectLocalResultExport,
  @execution.CompletedOutputExport,
  @execution.CompletedRelationExportReceipt,
)? {
  guard !self.closed &&
    !self.failed &&
    self.exported is Some(exported) &&
    self.stream is Some(stream) &&
    self.receipt is Some(receipt) &&
    @strategy.captured_effect_local_result_export_matches_receipt(
      self.inputs,
      exported,
      receipt,
    ) else {
    return None
  }
  Some((exported, stream, receipt))
}

///|
/// Reuse the completed capture's own Run, Result view and installed limits.
/// The private capture still owns its export and the physical Result pin.
pub fn InstalledEffectResultCapture::borrow_publication_output(
  self : InstalledEffectResultCapture,
  result : Int,
) -> Result[
  @publication_host.PublicationOutputExport,
  @publication_host.PublicationOutputExportIssue,
] {
  guard self.original() is Some((exported, stream, receipt)) else {
    return Err(InvalidState)
  }
  @publication_host.borrow_captured_effect_result_publication_export(
    self.captured,
    self.inputs,
    result,
    exported,
    stream,
    receipt,
    self.limits,
  )
}

///|
/// Retire the exact receipt/stream/bridge before the outer owner returns the
/// input pins. The physical caller must have unwound its synchronous poll.
pub fn InstalledEffectResultCapture::close(
  self : InstalledEffectResultCapture,
) -> Unit {
  self.closed = true
  if self.proposals is Some(proposals) {
    proposals.retire()
    self.proposals = None
  }
  if self.receipt is Some(receipt) {
    @execution.cancel_completed_relation_export_receipt(receipt)
  }
  self.receipt = None
  if self.stream is Some(stream) {
    @execution.cancel_completed_output_export(stream)
  }
  self.stream = None
  if self.managed is Some(managed) {
    managed.close()
    self.importing = None
    self.managed = None
  } else {
    if self.exported is Some(exported) {
      @execution.cancel_completed_result_relation_export(
        @strategy.captured_effect_local_result_export_preparation(exported),
      )
      |> ignore
    }
    if self.importing is Some(importing) {
      @execution.close_managed_publication_bridge(importing.bridge)
      self.importing = None
    }
  }
  self.exported = None
}
