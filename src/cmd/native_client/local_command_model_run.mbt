///|
// Keep the exact original Scope inventory on the existing command until the
// Request and its Model reads acknowledge retirement.
priv struct LocalCommandModelRun {
  compiled : @run_host.ClientCompiledRun
  definition : @publication.PublicationContract
  graphs : Array[@run_host.ClientInferPlanGraph]
  scopes : Array[@run_host.ClientModelReadScope]
  reads : Array[@run_host.ClientModelReadPreparation?]
  completions : Array[@infer.OutputUse?]
}

///|
fn LocalCommandModelRun::finish_scopes(
  self : Self,
) -> Result[Bool, @run_host.ClientModelReadPreparationIssue] {
  for index, scope in self.scopes {
    if self.reads[index] is Some(read) {
      match
        @run_host.stop_client_model_read_checked(
          scope,
          read,
          self.compiled,
          self.definition,
          self.graphs[index],
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      match
        @run_host.settle_client_model_read_checked(
          read,
          self.compiled,
          self.definition,
          self.graphs[index],
          true,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => self.reads[index] = None
      }
    }
    match
      @run_host.finish_client_model_read_scope(
        scope,
        self.compiled,
        self.definition,
        self.graphs[index],
        true,
      ) {
      Err(issue) => return Err(issue)
      Ok(true) => return Ok(true)
      // For a group this stays false until every member has finished.
      Ok(false) => ()
    }
  }
  Ok(false)
}

///|
fn[T] LocalCommandPreparationOriginal::require_model_plan(
  self : Self,
  result : Result[T, @local_values.ClientInstalledManagedRunIssue],
) -> T raise ClientStop {
  match result {
    Ok(value) => value
    Err(issue) => {
      self.retain_primary(CommandBusinessModelPlan(issue))
      stop("LocalOriginalModelPlanUnavailable")
    }
  }
}

///|
fn LocalCommandBusinessPreparation::prepare_model_run(
  self : Self,
  model : LocalCommandModelCompilation,
  request : @run_host.ClientRequestIdentity,
  compiled : @run_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.request_parent is Some(parent) &&
    business.request_input is Some(input) &&
    business.request_body is Some(body) &&
    business.request_run is None &&
    business.model_run is None else {
    stop("LocalBusinessOriginalUnavailable")
  }
  self.original.with_business_request(self.capture, () => {
    let count = model.graphs.length()
    let selected = match
      @local_values.prepare_request_model_source_free_module(
        parent,
        input,
        request,
        compiled,
        definition,
        model.compilation,
        self.installed_contracts,
        true,
        if count == 1 {
          1
        } else {
          0
        },
        native_request_provider_factory,
        component_factory=if count == 1 {
          Some((_, prefix, suffix) => {
            self.original.configured_native_model_provider(
              business, model, 0, prefix, suffix,
            )
          })
        } else {
          None
        },
        components_factory=if count > 1 {
          Some((index, _, prefix, suffix) => {
            self.original.configured_native_model_provider(
              business, model, index, prefix, suffix,
            )
          })
        } else {
          None
        },
      ) {
      Ok(value) => value
      Err(issue) => {
        self.original.retain_primary(CommandBusinessModelGraph(issue))
        stop("LocalOriginalModelModuleUnavailable")
      }
    }
    let plan = if count == 1 {
      let limits = model.bounds[0]
      self.original.require_model_plan(
        @local_values.prepare_request_model_source_free_plan(
          parent,
          input,
          selected,
          request,
          compiled,
          definition,
          model.occurrences[0],
          model.graphs[0],
          limits.model.ledger,
          limits.mapping.logical.max_live_value_bytes,
          limits.identity.wire.max_bytes.to_int64(),
          limits.input.rows.operation_entries,
          limits.input.rows.retained_entries,
          limits.input.rows.metadata_entries,
        ),
      )
    } else {
      self.prepare_model_group_plan(
        model, parent, input, selected, request, compiled, definition,
      )
    }
    let quantities = native_model_plan_quantities(model.graphs)
    let scopes = if count == 1 {
      [
        self.original.require_model_plan(
          @local_values.prepare_request_model_read_scope(
            parent,
            input,
            plan,
            quantity_limits=Some(quantities),
          ),
        ),
      ]
    } else {
      self.original.require_model_plan(
        @local_values.prepare_request_models_read_scopes(
          parent,
          input,
          plan,
          quantity_limits=Some(quantities),
        ),
      )
    }
    // Publish the Scope to cleanup before returning the input or switching
    // from Request preparation to the managed Run.
    business.model_run = Some({
      compiled,
      definition,
      graphs: model.graphs,
      scopes,
      reads: Array::make(count, None),
      completions: Array::make(count, None),
    })
    match
      @local_values.complete_request_model_preparation(parent, input, plan) {
      Err(issue) => {
        self.original.retain_primary(CommandRequestPreparation(issue))
        stop("LocalOriginalModelPreparationUnavailable")
      }
      Ok(_) => ()
    }
    match @local_host.return_native_client_submitted_request_body(body) {
      Err(_) => stop("LocalRequestBodyReturnPending")
      Ok(_) => business.request_body = None
    }
    let run = self.original.require_model_plan(
      @local_values.begin_request_model_managed_run(
        parent,
        request,
        scopes[0],
        scopes=if count == 1 { None } else { Some(scopes) },
      ),
    )
    business.request_run = Some(run)
    business.request_parent = None
    business.request_initial = None
    business.request_input = None
    business.request_intent = None
  })
}

///|
fn LocalCommandBusinessPreparation::prepare_model_group_plan(
  self : Self,
  model : LocalCommandModelCompilation,
  parent : @local_values.ClientRequestPreparation[LocalCommandBusinessInput],
  input : LocalCommandBusinessInput,
  selected : @local_values.ClientInstalledManagedSourceFreePreparation,
  request : @run_host.ClientRequestIdentity,
  compiled : @run_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> @local_values.ClientInstalledManagedModelPlan raise ClientStop {
  let count = model.graphs.length()
  self.original.require_model_plan(
    @local_values.reserve_request_models_plan_projection(parent, input, count),
  )
  let ledger = Array(capacity=count)
  let retained = Array(capacity=count)
  let execution = Array(capacity=count)
  let mut reservations = 0L
  let mut holdings = 0L
  let mut delegations = 0L
  for limits in model.bounds {
    ledger.push(limits.model.ledger)
    retained.push(limits.mapping.logical.max_live_value_bytes)
    execution.push(limits.identity.wire.max_bytes.to_int64())
    reservations += limits.input.rows.operation_entries.to_int64()
    holdings += limits.input.rows.retained_entries.to_int64()
    delegations += limits.input.rows.metadata_entries.to_int64()
  }
  if reservations > 2147483647L ||
    holdings > 2147483647L ||
    delegations > 2147483647L {
    stop("LocalOriginalModelBoundsUnavailable")
  }
  self.original.require_model_plan(
    @local_values.prepare_request_models_source_free_plan(
      parent,
      input,
      selected,
      request,
      compiled,
      definition,
      model.occurrences,
      model.graphs,
      ledger,
      retained,
      execution,
      reservations.to_int(),
      holdings.to_int(),
      delegations.to_int(),
    ),
  )
}

///|
// The transport policy derives these same totals from each exact contract.
// Common still applies each member's separate attempt and cumulative guards.
fn native_model_plan_quantities(
  graphs : Array[@run_host.ClientInferPlanGraph],
) -> @initial_resources.QuantityAmounts raise ClientStop {
  let mut tokens = 0L
  let mut cost_units = 0L
  let mut duration_ms = 0L
  for graph in graphs {
    let execution = @run_host.client_infer_plan_graph_execution_contract(graph)
    guard @execution.checked_preparation_add_product(
        tokens,
        @compiler_environment.model_execution_ceiling(
          execution,
          TotalTokenReservation,
        ),
        1L,
      )
      is Some(t) &&
      @execution.checked_preparation_add_product(
        cost_units,
        @compiler_environment.model_execution_ceiling(execution, TotalCostUnits),
        1L,
      )
      is Some(c) &&
      @execution.checked_preparation_add_product(
        duration_ms,
        @compiler_environment.model_execution_ceiling(
          execution,
          TotalDurationMs,
        ),
        1L,
      )
      is Some(d) else {
      stop("LocalOriginalModelBoundsUnavailable")
    }
    tokens = t
    cost_units = c
    duration_ms = d
  }
  { tokens, cost_units, duration_ms, }
}
