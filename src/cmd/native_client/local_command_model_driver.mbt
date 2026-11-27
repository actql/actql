///|
// Build only from the already selected installation, Run and Store. Each
// retained work slot is published to command cleanup before the next slot.
fn LocalCommandBusinessPreparation::prepare_configured_model_works(
  self : Self,
  business : LocalCommandBusinessOriginal,
  request : @run_host.ClientRequestIdentity,
  run : LocalRunInstallation,
  store : @local_store.Store,
) -> Unit raise ClientStop {
  guard !business.active &&
    business.operation is Some(operation) &&
    business.request_run is Some(_) &&
    business.model_run is Some(model) &&
    self.model_compilation is Some(selection) &&
    physical_equal(model.graphs, selection.graphs) &&
    business.model_work.is_empty() else {
    stop("LocalOriginalModelWorkUnavailable")
  }
  for index, graph in model.graphs {
    match
      @local_host.prepare_native_client_model_http_work(
        operation,
        request,
        model.compiled,
        model.definition,
        graph,
        selection.installations[index],
        store,
        selection.bounds[index],
        self.principal,
        self.connection,
        run.namespace_id,
        local_utc_now,
        output_receivers=Some(selection.installations),
      ) {
      Err(issue) => {
        self.original.retain_primary(CommandBusinessModel(issue))
        stop("LocalOriginalModelWorkUnavailable")
      }
      Ok(work) => business.model_work.push(work)
    }
  }
}

///|
// The existing Store receiver switches between the original Read and the
// same business execution. Restore the execution scope on a body refusal
// too, so the Local driver's failure cleanup sees the original owner.
fn[T] LocalCommandBusinessPreparation::with_model_driver_read(
  self : Self,
  business : LocalCommandBusinessOriginal,
  step : () -> T raise ClientStop,
) -> T raise ClientStop {
  guard business.active && business.operation is Some(operation) else {
    stop("LocalBusinessScopeUnavailable")
  }
  command_preparation_result(
    operation
    .return_business_to_original_read()
    .map_err(issue => CommandStoreOperation(issue)),
    stage=Some("model-step-read"),
  )
  business.active = false
  let result = Ok(step()) catch { ClientStop(message) => Err(message) }
  if result is Err(message) {
    self.original.retain_primary(CommandApplication(message))
  }
  // Retain attempted entry before the fallible operation. The receiver owns
  // an interrupted return even when no business phase was restored.
  business.active = true
  command_preparation_result(
    operation
    .enter_business_from_original_read()
    .map_err(issue => CommandStoreOperation(issue)),
    stage=Some("model-step-return"),
  )
  match result {
    Ok(value) => value
    Err(message) => stop(message)
  }
}

///|
// A dependent task's actual Readers are already staged, and its own
// compute registration and Model Read have not yet opened.
fn LocalCommandBusinessPreparation::retain_model_output_dependencies(
  self : Self,
  business : LocalCommandBusinessOriginal,
  model : LocalCommandModelRun,
  task : Int,
  inputs : @local_host.NativeWholeModelResultInputs,
) -> Bool {
  for index, graph in model.graphs {
    if @run_host.client_infer_occurrence_coordinates(graph.occurrence).0 != task {
      continue
    }
    guard business.model_work.get(index) is Some(work) else { return false }
    if !work.requires_model_output_dependencies() {
      return true
    }
    try {
      self.with_model_driver_read(business, () => {
        self.original.require_model_step(
          work.read_model_output_dependencies_in_original_read(
            business.model_work,
            model.completions,
            inputs,
          ),
        )
      })
      return true
    } catch {
      ClientStop(message) => {
        self.original.retain_primary(CommandApplication(message))
        return false
      }
    }
  }
  false
}

///|
// The Common loop still selects, starts and finalizes its task. This driver
// advances the selected Model only, between reads of the same Run, and
// services exactly the physical pauses reported by that original component.
fn LocalCommandBusinessPreparation::drive_configured_model_task(
  self : Self,
  business : LocalCommandBusinessOriginal,
  model : LocalCommandModelRun,
  run : LocalRunInstallation,
  reference : @local_host.NativeClientSubmissionReference,
  task : Int,
  operations : @local_driver.LocalManagedDispatchOperations[Int],
) -> Result[Unit, @local_values.LocalValuesExecutionIssue] {
  let mut selected = None
  for index, graph in model.graphs {
    if @run_host.client_infer_occurrence_coordinates(graph.occurrence).0 == task {
      if selected is Some(_) {
        return Err(UnsupportedGraph)
      }
      selected = Some(index)
    }
  }
  guard selected is Some(index) else {
    return (operations.execute)().map_err(issue => Driver(issue))
  }
  guard business.model_work.get(index) is Some(work) &&
    business.store is Some(store) &&
    self.model_compilation is Some(selection) &&
    physical_equal(selection.graphs, model.graphs) else {
    return Err(UnsupportedGraph)
  }
  let max_work = selection.bounds[index].model.max_work
  try {
    while true {
      self.with_model_driver_read(business, () => {
        self.original.require_model_step(work.observe_step_in_original_read())
      })
      let progress = match (operations.advance)(31) {
        Ok(value) => value
        Err(issue) => {
          let unknown = work.closed_http_unknown_observed()
          if (unknown || work.closed_http_failure_observed()) &&
            business.publication_publisher is Some(publisher) {
            if unknown {
              self.original.retain_primary(
                CommandBusinessModel(Model(@infer.Model(@model.UnknownCalls))),
              )
            }
            // A failed metadata save cannot replace the original driver
            // failure or discharge the existing scope/Journal cleanup.
            let proof = self.with_model_driver_read(business, () => {
              match
                work.retain_http_terminal_in_original_read(
                  publisher,
                  reference,
                  self.connection,
                  local_utc_now(),
                  @env.now().to_double(),
                ) {
                Ok(value) => value
                Err(_) => None
              }
            }) catch {
              ClientStop(_) => None
            }
            if proof is Some(verified) {
              command_preparation_diagnostic.val = RuntimeModelTerminalFailure(
                verified,
              )
            }
          }
          return Err(Driver(issue))
        }
      }
      if progress.complete {
        return Ok(())
      }
      if progress.waiting {
        // An unfulfilled Model decision never becomes a local approve or spin.
        stop("LocalOriginalModelDecisionUnavailable")
      }
      if work.needs_entry_persistence() {
        self.with_model_driver_read(business, () => {
          self.original.require_model_step(
            work.persist_entry_in_original_read(),
          )
        })
      } else if progress.settlement is Some(_) {
        self.with_model_driver_read(business, () => {
          self.settle_original_model_step(work, store, run, max_work)
        })
      } else if progress.await_io {
        self.with_model_driver_read(business, () => {
          self.drive_original_model_io(work, store, require_call=true)
        })
      }
    }
    Ok(())
  } catch {
    ClientStop(message) => {
      self.original.retain_primary(CommandApplication(message))
      Err(Fenced)
    }
  }
}
