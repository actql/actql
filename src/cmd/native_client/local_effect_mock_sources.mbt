///|
// The actual command crosses Journal/Account boundaries in its captured Read,
// and physical file/Core boundaries in its SAME adopted Request execution.
// Each partial capture is retained before its first advance or scope return.
fn LocalCommandBusinessPreparation::capture_mock_effect_sources(
  self : LocalCommandBusinessPreparation,
  reference : @local_host.NativeClientSubmissionReference,
  policy : @local_host.NativeLocalRunPolicyBinding,
  retention : @publication.PublicationContract,
  issued_at : String,
  now : Double,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    business.request_run is Some(run) &&
    self.original.host is Some(arena) &&
    business.execution is Some(execution) &&
    business.model_work.length() == 1 &&
    state.sources.is_empty() else {
    stop("LocalOriginalEffectPlanUnavailable")
  }
  let first = state.first
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
  let work = business.model_work[0]
  match work.claim_start_in_original_read(self.connection) {
    Err(issue) => {
      self.original.retain_primary(CommandBusinessModel(issue))
      stop("LocalOriginalEffectStartUnavailable")
    }
    Ok(_) => ()
  }
  for index, selected in first._retained_sources {
    let declaration = selected._retained_source._retained_declaration
    let source_ref = match selected._retained_reader {
      Rows(binding) => binding.view.source_ref
      Files(file, listing) =>
        file._retained_listings
        .iter()
        .find_first(pair => physical_equal(pair.0, listing))
        .unwrap_or_else(() => stop("LocalOriginalSourceUnavailable")).1.listing.source_ref
    }
    let authorize = () => {
      match work.require_source_in_original_read(self.connection, source_ref) {
        Err(issue) => {
          self.original.retain_primary(CommandBusinessModel(issue))
          stop("LocalSourceAuthorizationUnavailable")
        }
        Ok(_) => ()
      }
    }
    authorize()
    let capture = self.original.with_business_request(self.capture, () => {
      // This original unfiltered README selects WholeInputRoute. A Query is
      // not retried, normalized or disguised as a whole input on refusal.
      guard @local_values.installed_effect_managed_source_input_kind(
          run,
          state._retained_prepared,
          first.request,
          index,
        )
        is Ok("whole-input") else {
        stop("LocalOriginalSourceRouteUnavailable")
      }
      let (read, original, acquisition, capacity) = @local_values.begin_installed_effect_managed_whole_source_read(
        run,
        state._retained_prepared,
        first.request,
        declaration,
        index,
      ).unwrap_or_else(() => stop("LocalOriginalSourceReadUnavailable"))
      // Retain the original logical read even if the Native constructor
      // refuses before it can return a partial physical owner.
      state.source_reads.push(read)
      state.input_originals.push((original, acquisition))
      let prepared = match selected._retained_reader {
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
      match prepared {
        Err(issue) => {
          state.source_failures.push(issue)
          self.original.retain_primary(CommandBusinessSource(issue.issue()))
          stop("LocalOriginalSourceCaptureUnavailable")
        }
        Ok(capture) => {
          state.sources.push(capture)
          capture
        }
      }
    })
    // A bounded Core quantum never nests filesystem/SQLite Account callbacks.
    // Observe current authority outside that frame before EVERY actual step.
    let mut done = false
    while !done {
      authorize()
      done = self.original.with_business_request(self.capture, () => {
        match capture.advance(31) {
          Err(issue) => {
            state.source_failures.push(issue)
            self.original.retain_primary(CommandBusinessSource(issue.issue()))
            stop("LocalOriginalSourceAdvanceUnavailable")
          }
          Ok(value) => value
        }
      })
    }
    authorize()
    self.original.with_business_request(self.capture, () => {
      let captured = capture
        .capture()
        .unwrap_or_else(() => stop("LocalOriginalSourceCaptureUnavailable"))
      state.captured_inputs.push(
        @row_host.row_capture_input(captured).unwrap_or_else(() => {
          stop("LocalOriginalSourceCaptureUnavailable")
        }),
      )
    })
  }
}
