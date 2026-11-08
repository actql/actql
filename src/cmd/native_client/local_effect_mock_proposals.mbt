///|
// Original typed failures stay private on this command through diagnosis and
// cleanup. A generic public stop code never substitutes for the original cause.
priv enum LocalNativeMockEffectProposalIssue {
  Managed(@local_values.ClientInstalledManagedRunIssue)
  Capture(@strategy.RunIssue)
  Proposal(@strategy.CapturedEffectProposalIssue)
  Export(@strategy.CapturedEffectLocalResultExportIssue)
  Completed(@execution.CompletedExportIssue)
}

///|
fn[T] Result::native_effect_proposal(
  self : Result[T, LocalNativeMockEffectProposalIssue],
  original : LocalCommandPreparationOriginal,
) -> T raise ClientStop {
  match self {
    Ok(value) => value
    Err(issue) => {
      original.retain_primary(CommandBusinessEffectProposals(issue))
      stop("LocalOriginalEffectProposalsUnavailable")
    }
  }
}

///|
// Caller retention of the original Effect pins/export/projection continuations.
// These carry DATA only. Target observations, Preview, approval and physical
// writes retain their separate original Owners and authorizations.
priv struct LocalNativeMockEffectProposals {
  inputs : @strategy.CapturedEffectInputs
  members : Array[LocalNativeMockEffectProposalMember]
}

///|
priv struct LocalNativeMockEffectProposalMember {
  plan : @strategy.CapturedEffectProposalPlan
  mut capture_operation : @local_values.ClientInstalledEffectOperationBorrow?
  mut _retained_invocation : @run_host.ClientEffectLocalInvocation?
  mut _retained_capture_issue : @local_values.ClientInstalledManagedRunIssue?
  mut exported : @strategy.CapturedEffectLocalResultExport?
  mut stream : @execution.CompletedOutputExport?
  mut receipt : @execution.CompletedRelationExportReceipt?
  rows : Array[(String, String)]
}

///|
fn LocalCommandBusinessPreparation::prepare_mock_effect_proposals(
  self : LocalCommandBusinessPreparation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    state.effect_capture is Some(captured) &&
    business.request_run is Some(run) &&
    business.model_work.length() == 1 &&
    state.model_use is Some(_) &&
    state.proposals is None else {
    stop("LocalOriginalEffectProposalsUnavailable")
  }
  self.original.with_business_request(self.capture, () => {
    // The SAME installed parent admits the actual completed entry/row controls
    // before its new callback/index/row holders are constructed.
    @local_values.begin_installed_effect_operation_controls(
      run,
      state._retained_prepared,
      state.first.request,
      state._retained_plan,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
    .native_effect_proposal(self.original)
    |> ignore
    let limits = state.first._retained_models[0]._retained_limits
    let wire = limits.identity.wire
    let inputs = @strategy.pin_captured_effect_sources(
        captured,
        limits.input.rows.metadata_entries,
        max_dependency_work=limits.output_work,
        max_dependency_depth=wire.max_depth,
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Capture(issue))
      .native_effect_proposal(self.original)
    let held : LocalNativeMockEffectProposals = { inputs, members: [], }
    state.proposals = Some(held)
    @local_values.retain_installed_effect_captured_input_inventory(
      run,
      state._retained_prepared,
      state.first.request,
      state._retained_plan,
      inputs,
    )
    .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
    .native_effect_proposal(self.original)
    for entry in 0..<@strategy.captured_effect_inputs_count(inputs) {
      let plan = @strategy.prepare_captured_effect_proposal_plan(
          inputs,
          entry,
          wire.max_columns,
          limits.output_work,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Proposal(issue))
        .native_effect_proposal(self.original)
      let current : LocalNativeMockEffectProposalMember = {
        plan,
        capture_operation: None,
        _retained_invocation: None,
        _retained_capture_issue: None,
        exported: None,
        stream: None,
        receipt: None,
        rows: [],
      }
      held.members.push(current)
      // Retain the original member capture before its fallible semantic
      // constructors. The existing capture recipe backs Artifact/Preview
      // metadata; this does not consume another Model or Source allowance.
      let capture_operation = @local_values.borrow_installed_effect_operation(
          run,
          state._retained_prepared,
          state.first.request,
          state._retained_plan,
          entry,
          false,
          0,
          0,
          "native.mock.file.capture",
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
        .native_effect_proposal(self.original)
      current.capture_operation = Some(capture_operation)
      let invocation = business.model_work[0]
        .local_effect_invocation(16384, 1024, 20)
        .unwrap_or_else(() => stop("LocalOriginalEffectInvocationUnavailable"))
      guard @strategy.captured_effect_input_at(inputs, entry) is Some(input) &&
        @run_host.client_effect_local_invocation_matches(
          invocation,
          state._retained_prepared,
          @strategy.captured_effect_input_stage(input),
        ) else {
        stop("LocalOriginalEffectInvocationUnavailable")
      }
      current._retained_invocation = Some(invocation)
      let mut selected = None
      for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
        if @strategy.captured_effect_local_result_matches_member(
            inputs, index, entry,
          ) {
          if selected is Some(_) {
            stop("LocalOriginalEffectResultUnavailable")
          }
          selected = Some(index)
        }
      }
      let index = selected.unwrap_or_else(() => {
        stop("LocalOriginalEffectResultUnavailable")
      })
      let exported = @strategy.start_captured_effect_local_result_export(
          inputs,
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
        .map_err(issue => LocalNativeMockEffectProposalIssue::Export(issue))
        .native_effect_proposal(self.original)
      current.exported = Some(exported)
      let preparation = @strategy.captured_effect_local_result_export_preparation(
        exported,
      )
      while !@execution.advance_completed_result_relation_export(
              preparation, 31,
            )
            .map_err(issue => {
              LocalNativeMockEffectProposalIssue::Completed(issue)
            })
            .native_effect_proposal(self.original).0 {
        continue
      }
      let stream = @execution.finish_completed_result_relation_export_preparation(
          preparation,
        )
        .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
        .native_effect_proposal(self.original)
      current.stream = Some(stream)
      while @execution.next_completed_output_export_canonical_row(
              stream,
              wire.max_nodes,
              wire.max_depth,
              limits.output_work,
            )
            .map_err(issue => {
              LocalNativeMockEffectProposalIssue::Completed(issue)
            })
            .native_effect_proposal(self.original)
            is Some((row_index, _, row)) {
        let proposal = @strategy.project_captured_effect_proposal_row(
            plan,
            row,
            row_index,
            wire.max_columns,
            limits.output_work,
            wire.max_bytes,
            wire.max_nodes,
            wire.max_depth,
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Proposal(issue))
          .native_effect_proposal(self.original)
        current.rows.push(proposal)
      }
      let (receipt, _) = @execution.finish_completed_relation_export(stream)
        .map_err(issue => LocalNativeMockEffectProposalIssue::Completed(issue))
        .native_effect_proposal(self.original)
      current.receipt = Some(receipt)
      if !@strategy.captured_effect_local_result_export_matches_receipt(
          inputs, exported, receipt,
        ) {
        stop("LocalOriginalEffectResultUnavailable")
      }
      @strategy.finish_captured_effect_proposal_plan(
        plan,
        current.rows.length(),
      )
      .map_err(issue => LocalNativeMockEffectProposalIssue::Proposal(issue))
      .native_effect_proposal(self.original)
    }
  })
}

///|
// Retire pure Core child continuations before returning their actual Result
// pins. No file, pending write, Store or physical owner is acknowledged here.
fn LocalNativeMockEffectProposals::close(self : Self) -> Bool {
  for entry in self.members {
    @strategy.cancel_captured_effect_proposal_plan(entry.plan)
    if entry.receipt is Some(receipt) {
      @execution.cancel_completed_relation_export_receipt(receipt)
      entry.receipt = None
    }
    if entry.stream is Some(stream) {
      @execution.cancel_completed_output_export(stream)
      entry.stream = None
    }
    if entry.exported is Some(exported) {
      @execution.cancel_completed_result_relation_export(
        @strategy.captured_effect_local_result_export_preparation(exported),
      )
      |> ignore
      entry.exported = None
    }
    entry.rows.clear()
    entry._retained_invocation = None
    if entry.capture_operation is Some(operation) {
      match @local_values.retire_installed_effect_operation(operation, true) {
        Err(issue) => {
          entry._retained_capture_issue = Some(issue)
          return false
        }
        Ok(false) => return false
        Ok(true) => {
          entry.capture_operation = None
          entry._retained_capture_issue = None
        }
      }
    }
  }
  @strategy.release_captured_effect_inputs(self.inputs)
}
