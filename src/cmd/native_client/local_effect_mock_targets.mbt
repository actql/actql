///|
// Original per-row caller custody. The SAME selected operation backs this
// physical child and its escaped before/version until Preview consumes them.
// A completed read is not a write claim or an approval.
priv struct LocalNativeMockEffectTarget {
  operation : @local_values.ClientInstalledEffectOperationBorrow
  mut child : @row_file.NativeRelationFileTargetIO?
  mut observed : (String, String)?
  mut request_operation : @local_values.ClientInstalledEffectOperationBorrow?
  mut _retained_request : (String, String)?
  mut charged : Int64
  mut received : Int64
  mut _retained_account_issue : @local_values.ClientInstalledManagedRunIssue?
}

///|
fn LocalNativeMockEffectTarget::account_bytes(
  self : Self,
) -> Result[Unit, @local_values.ClientInstalledManagedRunIssue] {
  if self.child is Some(child) {
    let (received, submitted) = child.byte_counts()
    if received < self.received || submitted != 0L {
      if self._retained_account_issue is None {
        self._retained_account_issue = Some(ForeignOriginal)
      }
      return Err(ForeignOriginal)
    }
    // Keep the actual receive observation even if charging or a subsequent
    // physical close fails. The child may acknowledge close before this debt
    // can be reconciled; no further file read supplies replacement evidence.
    self.received = received
  }
  let delta = self.received - self.charged
  if delta > 0L {
    match
      @local_values.charge_installed_effect_operation(self.operation, delta) {
      Err(issue) => {
        if self._retained_account_issue is None {
          self._retained_account_issue = Some(issue)
        }
        return Err(issue)
      }
      Ok(_) => self.charged = self.received
    }
  }
  Ok(())
}

///|
fn LocalNativeMockEffectTarget::close(
  self : Self,
) -> Result[Bool, LocalCommandPreparationIssue] {
  let accounted = self.account_bytes()
  // Accounting refusal must not block the same physical child's close. Keep
  // its actual pending/ACK independent from the still-unsettled byte debt.
  if self.child is Some(child) {
    match child.close() {
      Err(issue) => return Err(CommandBusinessSource(issue))
      Ok(false) => return Ok(false)
      Ok(true) => self.child = None
    }
  }
  match accounted {
    Err(issue) => return Err(CommandBusinessEffectProposals(Managed(issue)))
    Ok(_) => ()
  }
  // Drop this caller's escaped DATA before settling its actual backing. The
  // physical child above, not a successful logical result, supplies the ACK.
  self.observed = None
  self._retained_request = None
  if self.request_operation is Some(operation) {
    match @local_values.retire_installed_effect_operation(operation, true) {
      Err(issue) => return Err(CommandBusinessEffectProposals(Managed(issue)))
      Ok(false) => return Ok(false)
      Ok(true) => self.request_operation = None
    }
  }
  @local_values.retire_installed_effect_operation(self.operation, true).map_err(issue => {
      CommandBusinessEffectProposals(Managed(issue))
    },
  )
}

///|
fn LocalCommandBusinessPreparation::observe_mock_effect_targets(
  self : Self,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    state.proposals is Some(proposals) &&
    business.request_run is Some(run) &&
    business.model_work.length() == 1 &&
    self.original.project is Some(project) &&
    project.mock_declarations is Some(mock) &&
    mock.write_installations is Some(installations) &&
    state.targets.is_empty() else {
    stop("LocalOriginalEffectTargetsUnavailable")
  }
  let work = business.model_work[0]
  let headers = @checked.effect_program_static_headers(
    @run_host.prepared_client_effect_computation_candidate(
      state._retained_prepared,
    ),
  )
  if @syntax.effect_header_count(headers) != proposals.members.length() {
    stop("LocalOriginalEffectTargetsUnavailable")
  }
  let policy = @run_host.client_standard_effect_computation_limits()
  for index, entry in proposals.members {
    let header = @syntax.effect_header_at(headers, index).unwrap()
    let input = @strategy.captured_effect_input_at(proposals.inputs, index).unwrap_or_else(() => {
        stop("LocalOriginalEffectTargetsUnavailable")
      },
    )
    if @strategy.captured_effect_input_member_index(input) != index ||
      @strategy.captured_effect_input_stage(input) !=
      @syntax.effect_header_stage(header) {
      stop("LocalOriginalEffectTargetsUnavailable")
    }
    let descriptor = @run_host.client_effect_member_descriptor(
      state._retained_prepared,
      @syntax.effect_header_stage(header),
      @syntax.effect_header_id(header),
      policy.effects.max_work,
    ).unwrap_or_else(() => stop("LocalOriginalEffectTargetsUnavailable"))
    guard descriptor.2 == "update" &&
      installations
      .iter()
      .find_first(value => {
        value.target == descriptor.3 &&
        value.write.mapping.mapping_ref == descriptor.4 &&
        value.write.mapping.mapping_cid == descriptor.5
      })
      is Some(installation) &&
      installation._retained_source._retained_rows
      .iter()
      .find_first(value => {
        value.view.resource == installation.write.mapping.resource
      })
      is Some(binding) else {
      stop("LocalOriginalEffectTargetsUnavailable")
    }
    let authorize = () => {
      match
        work.require_source_in_original_read(
          self.connection,
          installation._retained_source._retained_connection,
          binding.view.resource,
        ) {
        Err(issue) => {
          self.original.retain_primary(CommandBusinessModel(issue))
          stop("LocalEffectTargetObservationDenied")
        }
        Ok(_) => ()
      }
    }
    for row_index, proposal in entry.rows {
      authorize()
      let held = self.original.with_business_request(self.capture, () => {
        let operation = @local_values.borrow_installed_effect_operation(
            run,
            state._retained_prepared,
            state.first.request,
            state._retained_plan,
            index,
            true,
            2,
            row_index,
            "native.mock.file.capture-target",
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
          .native_effect_proposal(self.original)
        let held : LocalNativeMockEffectTarget = {
          operation,
          child: None,
          observed: None,
          request_operation: None,
          _retained_request: None,
          charged: 0L,
          received: 0L,
          _retained_account_issue: None,
        }
        // The original operation and partial child survive every fallible
        // constructor/return. No coordinate or attempt is reissued on error.
        state.targets.push(held)
        let selector = @json.parse(proposal.0) catch {
          _ => stop("LocalOriginalEffectSelectorUnavailable")
        }
        guard selector is String(identity) else {
          stop("LocalOriginalEffectSelectorUnavailable")
        }
        let child = match
          @row_file.prepare_native_relation_file_target_io(
            binding.provider,
            installation.write.mapping.write_fields,
            identity,
          ) {
          Err(issue) => {
            self.original.retain_primary(CommandBusinessSource(issue))
            stop("LocalOriginalEffectTargetUnavailable")
          }
          Ok(value) => value
        }
        held.child = Some(child)
        @local_values.start_installed_effect_operation(operation)
        .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
        .native_effect_proposal(self.original)
        held
      })
      let mut complete = false
      while !complete {
        authorize()
        complete = self.original.with_business_request(self.capture, () => {
          let result = held.child.unwrap().advance()
          // Actual receive bytes are charged even when the next projection
          // refuses. TargetIO projects only on a subsequent advance.
          held
          .account_bytes()
          .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
          .native_effect_proposal(self.original)
          match result {
            Err(issue) => {
              self.original.retain_primary(CommandBusinessSource(issue))
              stop("LocalOriginalEffectTargetUnavailable")
            }
            Ok(value) => {
              if value {
                held.observed = Some(
                  held.child
                  .unwrap()
                  .snapshot()
                  .unwrap_or_else(() => {
                    stop("LocalOriginalEffectTargetUnavailable")
                  }),
                )
              }
              value
            }
          }
        })
      }
      authorize()
      self.original.with_business_request(self.capture, () => {
        let request = @local_values.borrow_installed_effect_operation(
            run,
            state._retained_prepared,
            state.first.request,
            state._retained_plan,
            index,
            true,
            0,
            row_index,
            "native.mock.file.request",
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
          .native_effect_proposal(self.original)
        held.request_operation = Some(request)
        guard held.observed is Some((before, version)) &&
          held.child is Some(child) else {
          stop("LocalOriginalEffectTargetUnavailable")
        }
        let changes = @json.parse(proposal.1) catch {
          _ => stop("LocalOriginalEffectChangesUnavailable")
        }
        guard changes is Object(fields) &&
          fields.length() == 2 &&
          fields.get("state") == Some(Json::string("present")) &&
          fields.get("value") is Some(Object(value)) else {
          stop("LocalOriginalEffectChangesUnavailable")
        }
        let value = Json::object(value)
        let changes_wire = local_project_mock_relation_wire(value).unwrap_or_else(() => {
            stop("LocalOriginalEffectChangesUnavailable")
          },
        )
        match child.check_update(changes_wire) {
          Err(issue) => {
            self.original.retain_primary(CommandBusinessSource(issue))
            stop("LocalOriginalEffectChangesUnavailable")
          }
          Ok(_) => ()
        }
        let target = @json.parse(proposal.0) catch {
          _ => stop("LocalOriginalEffectSelectorUnavailable")
        }
        let before = @json.parse(before) catch {
          _ => stop("LocalOriginalEffectTargetUnavailable")
        }
        // SAME canonical request contract as the existing Mock UPDATE Owner.
        // Its full original before/version reaches Preview and cold recovery;
        // neither this DATA nor its digest is a durable write claim.
        let wire = local_project_mock_relation_wire({
          "binding": Json::string(installation.binding),
          "mapping": Json::string(installation.write.mapping.mapping_cid),
          "target": target,
          "value": value,
          "version": Json::string(version),
          "before": before,
        }).unwrap_or_else(() => stop("LocalOriginalEffectRequestUnavailable"))
        if @utf8.encode(wire).length() >
          policy.program.checking.compilation.artifacts.bytes {
          stop("LocalOriginalEffectRequestUnavailable")
        }
        let cid = "sha256:" +
          @sha.text_hex(wire).unwrap_or_else(() => {
            stop("LocalOriginalEffectRequestUnavailable")
          })
        held._retained_request = Some((wire, cid))
        @local_values.complete_installed_effect_operation_construction(request)
        .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
        .native_effect_proposal(self.original)
        match child.close() {
          Err(issue) => {
            self.original.retain_primary(CommandBusinessSource(issue))
            stop("LocalOriginalEffectTargetCleanupPending")
          }
          Ok(false) => stop("LocalOriginalEffectTargetCleanupPending")
          Ok(true) => held.child = None
        }
        // The detached canonical request has its OWN same-Plan pure backing.
        // Release the completed read's live holdings now; its occurrence and
        // consumed physical attempt/bytes remain spent on the original Run.
        held.observed = None
        if !@local_values.retire_installed_effect_operation(
            held.operation,
            true,
          )
          .map_err(issue => LocalNativeMockEffectProposalIssue::Managed(issue))
          .native_effect_proposal(self.original) {
          stop("LocalOriginalEffectTargetCleanupPending")
        }
      })
    }
  }
}
