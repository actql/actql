///|
// The installing command preserves the exact selected Graph, Scope and Run.
// Core alone identifies the captured relations and admits their whole-input
// and keyed evidence. No prepared Program, Source or Model is reconstructed.
fn LocalCommandBusinessPreparation::execute_mock_effect_model(
  self : LocalCommandBusinessPreparation,
  installation : LocalRunInstallation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    business.request_run is Some(run) &&
    business.store is Some(store) &&
    business.model_work.length() == 1 &&
    state.scope is Some(scope) &&
    state.lookup is Some(lookup) &&
    state.source_started_at is Some(started_at) &&
    state.source_completed_at is Some(source_completed_at) &&
    state.captured_inputs.length() == state.first._retained_sources.length() &&
    state.input_originals.length() == state.captured_inputs.length() &&
    state.model_read is None &&
    state.model_output is None else {
    stop("LocalOriginalModelInvocationUnavailable")
  }
  let first = state.first
  let selected = first._retained_models[0]
  let limits = selected._retained_limits
  let compiled = first.model_compiled.unwrap_or_else(() => {
    stop("LocalOriginalModelInvocationUnavailable")
  })
  let work = business.model_work[0]
  let completed_at = local_utc_now()
  if completed_at < source_completed_at {
    stop("LocalOriginalModelCaptureClockUnavailable")
  }
  state.source_completed_at = Some(completed_at)
  let (sequence, sources, consumer, read_retained, read_execution) = self.original.with_business_request(
    self.capture,
    () => {
      let dag = @strategy.checked_effect_computation_graph(
        @run_host.prepared_client_effect_computation_graph(
          state._retained_prepared,
        ),
      )
      let captured_sources = []
      let identities = []
      let logicals = []
      let observations = []
      let authority = @run_host.client_request_authority_scope_cid(
        first.request,
      )
      for index, input in state.captured_inputs {
        let source = @row_host.row_captured_input_source(input).unwrap_or_else(() => {
          stop("LocalOriginalModelSourceUnavailable")
        })
        let captured = state.sources[index]
          .capture()
          .unwrap_or_else(() => stop("LocalOriginalModelSourceUnavailable"))
        let identity = @query.identify_captured_source_relation(
          source,
          limits.identity.rows,
          limits.output_values,
          limits.identity.wire,
          limits.identity.logical_wire,
          limits.identity.schema,
          limits.identity.wire.max_bytes,
        ).unwrap_or_else(() => {
          stop("LocalOriginalModelSourceIdentityUnavailable")
        })
        let original = state.input_originals[index]
        let logical = @run_host.issue_captured_whole_source_input_logical(
          dag,
          source,
          identity,
          original.0,
          task=first._retained_sources[index]._retained_coordinates.2,
        ).unwrap_or_else(() => {
          stop("LocalOriginalModelSourceLogicalUnavailable")
        })
        let facts = @row_host.row_input_acquisition_facts(original.1)
        let observation = @row_host.issue_row_input_source_evidence(
          original.1,
          captured,
          identity,
          logical,
          authority,
          facts.source_data_policy_cid,
          completed_at,
        ).unwrap_or_else(() => {
          stop("LocalOriginalModelSourceObservationUnavailable")
        })
        captured_sources.push(source)
        identities.push(identity)
        logicals.push(logical)
        observations.push(observation)
      }
      let keyed = @run_host.issue_client_keyed_lookup_observation(
        lookup, authority, completed_at,
      ).unwrap_or_else(() => {
        stop("LocalOriginalModelKeyedObservationUnavailable")
      })
      let sources = @run_host.admit_client_infer_composed_whole_sources(
        state.graph.occurrence,
        captured_sources,
        identities,
        state.input_originals.map(pair => pair.0),
        logicals,
        observations,
        authority,
        started_at,
        completed_at,
        keyed=Some(keyed),
      ).unwrap_or_else(() => stop("LocalOriginalModelSourcesUnavailable"))
      let plan = @local_values.installed_effect_managed_operation_plan(
        run,
        state._retained_prepared,
        first.request,
      ).unwrap_or_else(() => stop("LocalOriginalModelSequenceUnavailable"))
      let sequence = @local_values.prepared_installed_effect_model_sequence(
        plan,
        state.graph,
      ).unwrap_or_else(() => stop("LocalOriginalModelSequenceUnavailable"))
      // These are the SAME already selected bounds used by this Plan's original
      // read/model window. No separate Ledger, preset or later quote is issued.
      let retained = limits.mapping.logical.max_live_value_bytes
      let execution = limits.identity.wire.max_bytes.to_int64()
      let read = @run_host.prepare_client_model_read(scope, retained, execution).unwrap_or_else(() => {
          stop("LocalOriginalModelReadUnavailable")
        },
      )
      state.model_read = Some(read)
      let consumer = @run_host.claim_client_model_read_preparation(
        read,
        compiled,
        first.definition,
        state.graph,
        retained,
        execution,
      ).unwrap_or_else(() => stop("LocalOriginalModelReadUnavailable"))
      (sequence, sources, consumer, retained, execution)
    },
  )
  let require_model = (
    result : Result[Unit, @local_host.NativeClientMockModelIssue],
  ) => {
    match result {
      Ok(_) => ()
      Err(issue) => {
        self.original.retain_primary(CommandBusinessModel(issue))
        stop("LocalOriginalModelExecutionUnavailable")
      }
    }
  }
  require_model(work.observe_step_in_original_read())
  self.original.with_business_request(self.capture, () => {
    require_model(
      work.open(
        sequence, sources, consumer, read_retained, read_execution, read_retained,
        read_execution,
      ),
    )
  })
  let mut complete = false
  while !complete {
    require_model(work.observe_step_in_original_read())
    let poll = self.original.with_business_request(self.capture, () => {
      match work.advance() {
        Ok(value) => {
          // Keep the SAME output and original work observation before a
          // return/current presentation can fail. No poll is reissued.
          if value is @infer.Complete(output, ..) {
            state.model_output = Some(output)
          }
          value
        }
        Err(issue) => {
          self.original.retain_primary(CommandBusinessModel(issue))
          stop("LocalOriginalModelExecutionUnavailable")
        }
      }
    })
    if work.needs_entry_persistence() {
      // The actual outer Read/Journal COMMIT precedes the NEXT Model step.
      // A failed/ambiguous original entry is never retried or inferred saved.
      require_model(work.persist_entry_in_original_read())
    }
    match poll {
      @infer.Settling(_, ..) => {
        self.original.with_business_request(self.capture, () => {
          require_model(
            work.prepare_settlement_export(
              @model.model_call_settlement_export_limits(
                native_mock_effect_record_bytes(installation),
                limits.model.max_work,
              ),
            ),
          )
        })
        let mut exported = false
        while !exported {
          exported = self.original.with_business_request(self.capture, () => {
            match work.advance_settlement_export() {
              Ok(value) => value
              Err(issue) => {
                self.original.retain_primary(CommandBusinessModel(issue))
                stop("LocalOriginalModelSettlementExportUnavailable")
              }
            }
          })
        }
        require_model(work.persist_settlement_evidence_in_original_read(store))
        require_model(work.commit_settlement_in_original_read())
        self.original.with_business_request(self.capture, () => {
          require_model(work.acknowledge_saved_settlement())
        })
      }
      @infer.Complete(_, ..) => complete = true
      @infer.Continue(..) | @infer.AwaitIo(..) | @infer.Waiting(..) => ()
      @infer.Failed(issue, ..) => {
        self.original.retain_primary(
          CommandBusinessModel(@local_host.Model(issue)),
        )
        stop("LocalOriginalModelExecutionUnavailable")
      }
      @infer.Stopped(..) => stop("LocalOriginalModelExecutionStopped")
    }
  }
}

///|
// Continue from the SAME completed physical Model. The original output use
// outlives all captured Effect consumers; neither Saved restoration nor the
// fresh-provider entrance can substitute for this already completed Work.
fn LocalCommandBusinessPreparation::retain_mock_effect_host(
  self : LocalCommandBusinessPreparation,
  bound : @run_host.PreparedClientEffectRun,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    business.request_run is Some(run) &&
    business.model_work.length() == 1 &&
    state.model_output is Some(_) &&
    state.model_use is None &&
    state.effect_host is None &&
    state.effect_capture is None else {
    stop("LocalOriginalEffectContinuationUnavailable")
  }
  self.original.with_business_request(self.capture, () => {
    let active = business.model_work[0]
      .borrow_opened_original_model()
      .unwrap_or_else(() => stop("LocalOriginalEffectContinuationUnavailable"))
    let held = @infer.acquire_output(active).unwrap_or_else(() => {
      stop("LocalOriginalEffectContinuationUnavailable")
    })
    // Retain BEFORE any input currentness/configuration callback can fail.
    state.model_use = Some(held)
    let (output, completed) = @infer.borrow_original_live_host_output(
      held,
      state.first.model_compiled.unwrap(),
      state.first.definition,
      state.graph,
    ).unwrap_or_else(() => stop("LocalOriginalEffectContinuationUnavailable"))
    state.model_output = Some(output)
    let sources = state.captured_inputs.map(input => {
      @row_host.row_captured_input_source(input).unwrap_or_else(() => {
        stop("LocalOriginalEffectContinuationUnavailable")
      })
    })
    let (host, captured, _) = @local_values.open_installed_effect_retained_model_host(
        run,
        bound,
        sources,
        state.first.model_compiled.unwrap(),
        state.first.definition,
        state.graph,
        output,
        completed,
      )
      .unwrap_or_else(() => stop("LocalOriginalEffectContinuationUnavailable"))
      .unwrap_or_else(() => stop("LocalOriginalEffectContinuationUnavailable"))
    // The installed parent also retains partially constructed captured tasks.
    // These are borrowed aliases, not another execution/cleanup Owner.
    state.effect_capture = Some(captured)
    state.effect_host = Some(host)
  })
}

///|
fn LocalCommandBusinessPreparation::prepare_mock_effect_observation(
  self : Self,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    state.model_output is Some(_) &&
    business.model_work.length() == 1 else {
    stop("LocalOriginalModelObservationUnavailable")
  }
  let work = business.model_work[0]
  self.original.with_business_request(self.capture, () => {
    match work.prepare_observation() {
      Err(issue) => {
        self.original.retain_primary(CommandBusinessModel(issue))
        stop("LocalOriginalModelObservationUnavailable")
      }
      Ok(_) => ()
    }
  })
  let mut complete = false
  while !complete {
    complete = self.original.with_business_request(self.capture, () => {
      match work.advance_observation() {
        Err(issue) => {
          self.original.retain_primary(CommandBusinessModel(issue))
          stop("LocalOriginalModelObservationUnavailable")
        }
        Ok(value) => {
          if value {
            state._retained_model_observation = Some(
              work
              .observation_original()
              .unwrap_or_else(() => {
                stop("LocalOriginalModelObservationUnavailable")
              }),
            )
          }
          value
        }
      }
    })
  }
}

///|
/// The same Native Work converts its complete raw outcomes after durable
/// Model settlement and retains the original issuer. The final Result/suffix
/// cannot stand in for this observation; no Model or Source is redispatched.
fn LocalCommandBusinessPreparation::prepare_mock_effect_local_observation(
  self : Self,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.effect_model is Some(state) &&
    state._retained_model_observation is Some(_) &&
    state.effect_capture is Some(_) &&
    state._retained_local_model_observation is None &&
    business.model_work.length() == 1 else {
    stop("LocalOriginalModelLocalObservationUnavailable")
  }
  let work = business.model_work[0]
  self.original.with_business_request(self.capture, () => {
    match work.prepare_local_observation() {
      Err(issue) => {
        self.original.retain_primary(CommandBusinessModel(issue))
        stop("LocalOriginalModelLocalObservationUnavailable")
      }
      Ok(_) => ()
    }
  })
  let mut complete = false
  while !complete {
    complete = self.original.with_business_request(self.capture, () => {
      match work.advance_local_observation() {
        Err(issue) => {
          self.original.retain_primary(CommandBusinessModel(issue))
          stop("LocalOriginalModelLocalObservationUnavailable")
        }
        Ok(done) => {
          if done {
            state._retained_local_model_observation = Some(
              work
              .local_observation_original()
              .unwrap_or_else(() => {
                stop("LocalOriginalModelLocalObservationUnavailable")
              }),
            )
          }
          done
        }
      }
    })
  }
}
