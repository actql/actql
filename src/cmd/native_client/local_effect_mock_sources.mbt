///|
// The actual command crosses Journal/Account boundaries in its captured Read,
// and physical file/Core boundaries in its SAME adopted Request execution.
// Each partial capture is retained before its first advance or scope return.
fn LocalCommandBusinessPreparation::capture_mock_effect_sources(
  self : LocalCommandBusinessPreparation,
  reference : @local_host.NativeClientSubmissionReference,
  policy : @local_host.NativeLocalRunPolicyBinding,
  retention : @publication.PublicationContract,
  bound : @run_host.PreparedClientEffectRun,
  issued_at : String,
  now : Double,
  installation : LocalRunInstallation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    business.request_run is Some(run) &&
    self.original.host is Some(arena) &&
    business.execution is Some(execution) &&
    business.model_work.length() == state.first._retained_models.length() &&
    business.model_work.length() <= 1 &&
    state.source_started_at is None &&
    state.source_start is None &&
    state.sources.is_empty() else {
    stop("LocalOriginalEffectPlanUnavailable")
  }
  let first = state.first
  let values_create = first.is_mock_values_create()
  match
    self.capture.accept_issued_effect_policy_run_in_original_read(
      policy,
      reference,
      self.preparation,
      first.request,
      first.allowed,
      first.definition,
      first.issued,
      retention,
      issued_at,
      now,
      source_free=values_create,
    ) {
    Err(issue) => {
      self.original.retain_primary(CommandAdoption(issue))
      stop("LocalEffectOriginalAcceptanceUnavailable")
    }
    Ok(Err(issue)) => {
      self.original.retain_primary(CommandBusinessEffectAcceptance(issue))
      stop("LocalEffectOriginalAcceptanceUnavailable")
    }
    Ok(Ok(_)) => ()
  }
  self.prepare_mock_effect_store(installation)
  if business.model_work.get(0) is Some(work) {
    match work.claim_start_in_original_read(self.connection) {
      Err(issue) => {
        self.original.retain_primary(CommandBusinessModel(issue))
        stop("LocalOriginalEffectStartUnavailable")
      }
      Ok(_) => ()
    }
  } else {
    match
      self.capture.claim_effect_start_in_original_read(
        first.request,
        self.principal,
        self.connection,
        () => self.mock_effect_source_current(state, run),
        token => state.source_start = Some(token),
      ) {
      Err(issue) => {
        self.original.retain_primary(CommandAdoption(issue))
        stop("LocalOriginalEffectStartUnavailable")
      }
      Ok(Err(issue)) => {
        self.original.retain_primary(CommandBusinessEffectStart(issue))
        stop("LocalOriginalEffectStartUnavailable")
      }
      Ok(Ok(_)) => ()
    }
  }
  state.source_started_at = Some(local_utc_now())
  for index, selected in first._retained_sources {
    let resource = match selected._retained_reader {
      Rows(binding) => binding.view.resource
      Files(file, listing) =>
        file._retained_listings
        .iter()
        .find_first(pair => physical_equal(pair.0, listing))
        .unwrap_or_else(() => stop("LocalOriginalSourceUnavailable")).1.listing.resource
    }
    let authorize = () => {
      self.require_mock_effect_source(
        state,
        run,
        business.model_work.get(0),
        selected._retained_source._retained_connection,
        resource,
        "LocalSourceAuthorizationUnavailable",
      )
    }
    authorize()
    let capture = self.original.with_business_request(self.capture, () => {
      match
        state.prepare_mock_effect_source_capture(run, arena, execution, index) {
        Ok(capture) => capture
        Err(Route) => stop("LocalOriginalSourceRouteUnavailable")
        Err(Read(cause)) => {
          self.original.retain_primary(
            CommandBusinessEffectProposals(Managed(cause)),
          )
          stop("LocalOriginalSourceReadUnavailable")
        }
        Err(Physical(cause)) => {
          self.original.retain_primary(CommandBusinessSource(cause))
          stop("LocalOriginalSourceCaptureUnavailable")
        }
      }
    })
    // A bounded Core quantum never nests filesystem/SQLite Account callbacks.
    // Observe current authority outside that frame before EVERY actual step.
    let mut done = false
    while !done {
      authorize()
      done = self.original.with_business_request(self.capture, () => {
        match state.advance_mock_effect_source_capture(capture) {
          Err(issue) => {
            self.original.retain_primary(CommandBusinessSource(issue))
            stop("LocalOriginalSourceAdvanceUnavailable")
          }
          Ok(value) => value
        }
      })
    }
    authorize()
    self.original.with_business_request(self.capture, () => {
      state
      .retain_mock_effect_source_input(capture)
      .unwrap_or_else(() => stop("LocalOriginalSourceCaptureUnavailable"))
    })
  }
  state.source_completed_at = Some(local_utc_now())
  if state.source_start is Some(_) {
    self.original.with_business_request(self.capture, () => {
      match state.open_mock_effect_source_host(run, bound) {
        Ok(_) => ()
        Err(issue) => {
          self.original.retain_primary(
            CommandBusinessEffectProposals(Managed(issue)),
          )
          stop("LocalOriginalEffectHostUnavailable")
        }
      }
      let issue = if values_create {
        state.issue_mock_effect_values_publication(run, bound, installation)
      } else {
        state.issue_mock_effect_direct_sources(run, bound)
      }
      match issue {
        Ok(_) => ()
        Err(issue) => {
          self.original.retain_primary(CommandBusinessSourceIdentity(issue))
          stop("LocalOriginalEffectSourceEvidenceUnavailable")
        }
      }
    })
  }
}

///|
fn LocalNativeMockEffectPlan::open_mock_effect_source_host(
  self : Self,
  run : @local_values.ClientInstalledManagedRun,
  bound : @run_host.PreparedClientEffectRun,
) -> Result[Unit, @local_values.ClientInstalledManagedRunIssue] {
  guard self.first._retained_models.is_empty() &&
    self.captured_inputs.length() == self.first._retained_sources.length() &&
    (!self.captured_inputs.is_empty() || self.first.is_mock_values_create()) &&
    self.effect_host is None &&
    self.effect_capture is None else {
    return Err(ForeignOriginal)
  }
  let sources = []
  for input in self.captured_inputs {
    guard @row_host.row_captured_input_source(input) is Some(source) else {
      return Err(ForeignOriginal)
    }
    sources.push(source)
  }
  match @local_values.open_installed_effect_managed_host(run, bound, sources) {
    Err(issue) => Err(issue)
    Ok(None) => Err(Unsupported)
    Ok(Some((host, captured, _))) => {
      self.effect_host = Some(host)
      self.effect_capture = Some(captured)
      Ok(())
    }
  }
}

///|
fn LocalCommandBusinessPreparation::mock_effect_source_current(
  self : Self,
  state : LocalNativeMockEffectPlan,
  run : @local_values.ClientInstalledManagedRun,
) -> Bool {
  !self.original.closing &&
  !self.original.closed &&
  self.original.journal is Some(capture) &&
  physical_equal(capture, self.capture) &&
  self.original.business is Some(business) &&
  !business.request_retiring &&
  !business.active &&
  business.effect_model is Some(current) &&
  physical_equal(current, state) &&
  business.request_run is Some(active) &&
  physical_equal(active, run) &&
  @run_host.client_effect_run_start_current(
    state.first.allowed,
    state.first.definition,
    local_utc_now(),
  )
}

///|
fn LocalCommandBusinessPreparation::require_mock_effect_source(
  self : Self,
  state : LocalNativeMockEffectPlan,
  run : @local_values.ClientInstalledManagedRun,
  model : @local_host.NativeClientMockModelWork?,
  connection : String,
  resource : String,
  reason : String,
) -> Unit raise ClientStop {
  if model is Some(work) {
    match
      work.require_source_in_original_read(
        self.connection,
        connection,
        resource,
      ) {
      Err(issue) => {
        self.original.retain_primary(CommandBusinessModel(issue))
        stop(reason)
      }
      Ok(_) => ()
    }
  } else {
    guard state.source_start is Some(first) else { stop(reason) }
    match
      self.capture.require_effect_source_in_original_read(
        first,
        state.first.request,
        self.principal,
        self.connection,
        connection,
        resource,
        () => self.mock_effect_source_current(state, run),
      ) {
      Err(issue) => {
        self.original.retain_primary(CommandAdoption(issue))
        stop(reason)
      }
      Ok(Err(issue)) => {
        self.original.retain_primary(CommandBusinessEffectStart(issue))
        stop(reason)
      }
      Ok(Ok(_)) => ()
    }
  }
}

///|
priv enum LocalNativeMockEffectSourceIssue {
  Route
  Read(@local_values.ClientInstalledManagedRunIssue)
  Physical(@row_file.NativeRelationFileIssue)
}

///|
priv enum LocalNativeMockEffectSourceOriginal {
  WholeEffectInput(
    @sourceviews.SourceAcquisition,
    @row_host.RowInputAcquisition
  )
  QueryEffectInput(@row_host.RowAcquisition)
}

///|
// Hold the original managed Read and both physical outcomes before advancing
// or returning to the Journal. The caller checks authority outside this scope.
fn LocalNativeMockEffectPlan::prepare_mock_effect_source_capture(
  self : Self,
  run : @local_values.ClientInstalledManagedRun,
  arena : @initial_arena.InstalledArenaHost,
  execution : @initial_arena.InstalledArenaRetainedExecution,
  index : Int,
) -> Result[
  @row_file.NativeRelationFileCapture,
  LocalNativeMockEffectSourceIssue,
] {
  guard self.first._retained_sources.get(index) is Some(selected) else {
    return Err(Route)
  }
  let declaration = selected._retained_source._retained_declaration
  let prepared = match
    @local_values.installed_effect_managed_source_input_kind(
      run,
      self._retained_prepared,
      self.first.request,
      index,
    ) {
    Ok("whole-input") => {
      let (read, original, acquisition, capacity) = match
        @local_values.begin_installed_effect_managed_whole_source_read(
          run,
          self._retained_prepared,
          self.first.request,
          declaration,
          index,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Read(issue))
      }
      self.source_reads.push(read)
      self.input_originals.push(WholeEffectInput(original, acquisition))
      match selected._retained_reader {
        Rows(binding) =>
          @row_file.prepare_native_managed_relation_file_input_capture(
            arena,
            execution,
            declaration,
            read,
            capacity,
            binding.provider.capacity(),
            "native-mock-records",
            binding._retained_selection,
            binding.limits,
            prepared_provider=Some(binding.provider),
          )
        Files(_, listing) =>
          @row_file.prepare_native_managed_relation_file_listing_capture(
            arena, execution, read, capacity, listing, "native-mock-files",
          )
      }
    }
    Ok("query") => {
      guard self.first._retained_models.is_empty() &&
        selected._retained_reader is Rows(binding) else {
        return Err(Route)
      }
      let (read, _, acquisition, _) = match
        @local_values.begin_installed_effect_managed_source_read(
          run, declaration, index,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Read(issue))
      }
      self.source_reads.push(read)
      self.input_originals.push(QueryEffectInput(acquisition))
      @row_file.prepare_native_managed_relation_file_query_capture(
        arena,
        execution,
        declaration,
        read,
        acquisition,
        binding.provider.capacity(),
        "native-mock-records",
        binding._retained_selection,
        binding.limits,
        prepared_provider=Some(binding.provider),
      )
    }
    Ok(_) => return Err(Route)
    Err(issue) => return Err(Read(issue))
  }
  match prepared {
    Err(issue) => {
      self.source_failures.push(issue)
      Err(Physical(issue.issue()))
    }
    Ok(capture) => {
      self.sources.push(capture)
      Ok(capture)
    }
  }
}

///|
fn LocalNativeMockEffectPlan::advance_mock_effect_source_capture(
  self : Self,
  capture : @row_file.NativeRelationFileCapture,
) -> Result[Bool, @row_file.NativeRelationFileIssue] {
  match capture.advance(31) {
    Err(issue) => {
      self.source_failures.push(issue)
      Err(issue.issue())
    }
    Ok(done) => Ok(done)
  }
}

///|
fn LocalNativeMockEffectPlan::retain_mock_effect_source_input(
  self : Self,
  capture : @row_file.NativeRelationFileCapture,
) -> Unit? {
  guard capture.capture() is Ok(original) &&
    @row_host.row_capture_input(original) is Some(input) else {
    return None
  }
  self.captured_inputs.push(input)
  Some(())
}
