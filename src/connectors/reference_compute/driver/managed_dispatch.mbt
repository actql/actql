///|
/// Pure prepared reference managed task. Candidate support and cost comparison
/// perform no representation read, pin, task reservation or identity work.
struct NumericManagedDispatchConfiguration[T] {
  run : @strategy.CapturedDAG
  task : Int
  choice : @connector.ManagedFixedComputeChoice[T]
  prepared : @connector.PreparedManagedCompute[
    T,
    @numeric.ManagedNumericCompute[T],
  ]
  generated : @execution.CompletionPreparation
  limits : @numeric.NumericExecutionLimits
  capacity : @connector.ExecutionCapacity
  identity_capability : @execution.ManagedIdentityIssuanceCapability
}

///|
pub struct NumericManagedInputTransfer[T] {
  input : @execution.ManagedProducerRead[T]
  append : (String) -> Result[Unit, @numeric.PlanIssue]
  finish : () -> Result[Unit, @numeric.PlanIssue]
}

///|
pub struct NumericManagedDispatchOperations[T] {
  inputs : Array[NumericManagedInputTransfer[T]]
  execute : () -> Result[Unit, @numeric.PlanIssue]
  settle : () -> Result[Unit, @numeric.PlanIssue]
  complete : (T, Int64, () -> Bool) -> Result[
    @execution.ManagedCompletedOutput[T],
    @numeric.PlanIssue,
  ]
  output_rows : () -> Int
  output_row : (Int) -> Result[String, @numeric.PlanIssue]
  material : () -> @execution.ManagedRetainedOutput[T]?
  storage_bytes : Int64
  close : () -> Unit
  cleanup_refresh : () -> Bool
}

///|
priv enum NumericManagedPreparationIssue {
  Inapplicable
  Fatal(@strategy.RunIssue)
  Plan(@numeric.PlanIssue)
}

///|
fn managed_numeric_row_limits(
  limits : @numeric.NumericExecutionLimits,
) -> @execution.RetainedRowDecodeLimits {
  // The retained-row JSON decoder has an explicit structural ceiling of 64.
  // This connector only accepts a flat numeric row shape, so using that
  // implementation ceiling does not narrow any accepted plan value.
  let max_depth = if limits.physical.max_depth > 64 {
    64
  } else {
    limits.physical.max_depth
  }
  {
    max_bytes: limits.physical.max_bytes,
    max_nodes: limits.physical.max_nodes,
    max_depth,
    max_text_bytes: limits.values.max_text_bytes,
  }
}

///|
fn managed_numeric_wire_limits(
  limits : @numeric.NumericExecutionLimits,
) -> @execution.RowWireLimits {
  {
    max_columns: limits.max_entries,
    max_order_work: limits.max_work,
    max_bytes: limits.physical.max_bytes,
    max_nodes: limits.physical.max_nodes,
    max_depth: limits.physical.max_depth,
  }
}

///|
/// Conservative owned-memory bound, not RSS or an observed byte count. It
/// includes the bridged input, numeric output, managed checked-value copy,
/// measurement/index administration and their generation-time overlap.
fn managed_numeric_capacity(
  limits : @numeric.NumericExecutionLimits,
) -> Result[@connector.ExecutionCapacity, @numeric.PlanIssue] {
  let base = match @numeric.numeric_execution_capacity(limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let work = limits.max_work.to_int64()
  let nodes = limits.values.max_nodes.to_int64() +
    limits.physical.max_nodes.to_int64()
  let bytes = limits.values.max_text_bytes.to_int64() +
    limits.physical.max_bytes.to_int64()
  if work < 0L ||
    nodes < 0L ||
    bytes < 0L ||
    work > 144115188075855871L ||
    nodes > 144115188075855871L ||
    bytes > 1152921504606846975L {
    return Err(@numeric.Limit)
  }
  let imported = work * 64L + nodes * 64L + bytes * 8L
  if base.retained_bytes > 4611686018427387903L ||
    imported > 9223372036854775807L - base.execution_bytes ||
    imported > 9223372036854775807L - base.retained_bytes * 2L {
    return Err(@numeric.Limit)
  }
  Ok({
    transfer_bytes: limits.physical.max_bytes.to_int64(),
    retained_bytes: base.retained_bytes * 2L + imported,
    scratch_bytes: base.execution_bytes + imported,
    execution_bytes: base.execution_bytes + imported,
  })
}

///|
fn[T] prepare_numeric_managed_dispatch_installed(
  installed : NumericDispatchModule,
  outputs : Array[@execution.ManagedCompletedOutput[T]],
  obligations : @execution.ManagedObligations,
  _output_file_bytes : Int64,
) -> Result[
  NumericManagedDispatchConfiguration[T],
  NumericManagedPreparationIssue,
] {
  let run = @host.dispatch_driver_run(installed.driver)
  guard @strategy.next_captured_task(run) is Some(task) &&
    @host.compute_author_sequence(installed.context, task) is Some(generated) else {
    return Err(Inapplicable)
  }
  let inputs = []
  for index, output in outputs {
    match
      @strategy.captured_managed_task_input(
        run,
        task,
        output,
        installed.limits.max_work,
        installed.limits.max_name_bytes,
        input_index=index,
      ) {
      Ok(value) => inputs.push(value)
      Err(issue) => return Err(Fatal(issue))
    }
  }
  let request = match
    @connector.prepare_managed_fixed_compute_request(
      inputs,
      {
        contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
        max_rows: installed.limits.max_work,
        max_value_bytes: installed.limits.physical.max_bytes,
        common_fragment: None,
      },
      obligations,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Plan(@numeric.ManagedCandidate(issue)))
  }
  for requirement in @execution.managed_obligations_identities(obligations) {
    if requirement.need is @execution.EstablishedBy(_) &&
      (
        requirement.domain != @execution.OrderedRows ||
        requirement.subject != @execution.TaskOutput ||
        requirement.occurrence is Some(_)
      ) {
      return Err(Inapplicable)
    }
  }
  let prepared = match
    @numeric.offer_managed_numeric_compute(
      installed.registration,
      request,
      installed.limits.max_entries,
      installed.limits.max_name_bytes,
      installed.expressions,
      0,
      [],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
    ) {
    Ok(value) => value
    Err(@numeric.Unsupported) => return Err(Inapplicable)
    Err(issue) => return Err(Plan(issue))
  }
  let choice = match
    @connector.choose_managed_fixed_compute_candidate(
      installed.registry,
      request,
      [@connector.prepared_managed_compute_candidate(prepared)],
      Some([0]),
      installed.limits.max_work,
    ) {
    Ok(@connector.Proposed(value)) => value
    Ok(_) => return Err(Inapplicable)
    Err(issue) => return Err(Plan(@numeric.ManagedCandidate(issue)))
  }
  let capacity = match managed_numeric_capacity(installed.limits) {
    Ok(value) => value
    Err(issue) => return Err(Plan(issue))
  }
  Ok({
    run,
    task,
    choice,
    prepared,
    generated,
    limits: installed.limits,
    capacity,
    identity_capability: installed.identity_capability,
  })
}

///|
/// Generated common composition enters through the configured contribution,
/// preserving the same error projection as the legacy reference driver.
pub fn[T] prepare_numeric_managed_dispatch(
  configured : NumericComputeContribution,
  outputs : Array[@execution.ManagedCompletedOutput[T]],
  obligations : @execution.ManagedObligations,
  output_file_bytes : Int64,
) -> Result[NumericManagedDispatchConfiguration[T]?, @strategy.RunIssue] {
  match
    prepare_numeric_managed_dispatch_installed(
      configured.installed,
      outputs,
      obligations,
      output_file_bytes,
    ) {
    Ok(value) => Ok(Some(value))
    Err(Inapplicable) => Ok(None)
    Err(Fatal(issue)) => Err(issue)
    Err(Plan(issue)) => Err(numeric_dispatch_issue(issue))
  }
}

///|
pub fn[T] start_numeric_managed_dispatch(
  setup : NumericManagedDispatchConfiguration[T],
) -> Result[NumericManagedDispatchOperations[T], @numeric.PlanIssue] {
  let live = Ref(true)
  let settled = Ref(false)
  let bridges : Array[@execution.ManagedProducerBridge[T]] = []
  let reads : Array[@execution.ProducerRead?] = []
  let ordinary : Ref[@execution.CompletedOutput?] = Ref(None)
  let retained : Ref[@execution.ManagedRetainedOutput[T]?] = Ref(None)
  let request = @connector.managed_fixed_compute_candidate_request(
    @connector.prepared_managed_compute_candidate(setup.prepared),
  )
  let identity_permit : @execution.ManagedIdentityAttemptPermit? = {
    let mut selected = None
    for
      requirement in @execution.managed_obligations_identities(
        @connector.managed_fixed_compute_request_obligations(request),
      ) {
      if requirement.domain == @execution.OrderedRows &&
        requirement.subject == @execution.TaskOutput &&
        requirement.occurrence is None {
        match
          @execution.authorize_managed_identity_attempt(
            setup.identity_capability,
            setup.generated,
            requirement,
          ) {
          Ok(value) => selected = Some(value)
          Err(_) => return Err(@numeric.Unsupported)
        }
      }
    }
    selected
  }
  let managed_inputs = @connector.managed_fixed_compute_request_inputs(request)
  let bound = match
    @connector.bind_prepared_managed_execution(
      setup.choice,
      setup.prepared,
      setup.capacity,
      [],
      fn(_) {
        for input in managed_inputs {
          let bridge = match
            @execution.prepare_managed_producer_bridge(
              input,
              @connector.managed_fixed_compute_request_capacity(request).max_rows,
              setup.limits.values,
              setup.limits.max_entries,
              setup.limits.max_name_bytes,
            ) {
            Ok(value) => value
            Err(_) =>
              return Err(
                @strategy.RunIssue::Compute(@connector.InputUnavailable),
              )
          }
          bridges.push(bridge)
          reads.push(None)
        }
        let operations : @connector.ManagedExecutionOperations[
          @strategy.RunIssue,
        ] = {
          cancel: fn() {
            live.val = false
            for bridge in bridges {
              @execution.close_managed_producer_bridge(bridge)
            }
          },
          dispose: fn() {
            live.val = false
            for bridge in bridges {
              @execution.close_managed_producer_bridge(bridge)
            }
          },
          settled: fn() { settled.val = true },
          retention_released: fn() {
            retained.val is None ||
            retained.val
            .map(value => {
              @execution.managed_retained_output_payload(value) is None
            })
            .unwrap()
          },
          released: fn() { () },
          ready: fn() {
            if live.val && settled.val {
              Ok(())
            } else {
              Err(@strategy.RunIssue::NotReady)
            }
          },
        }
        Ok(((), operations))
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(@numeric.ManagedCandidate(issue))
  }
  let execution = match
    @strategy.start_captured_managed_execution(setup.run, setup.task, bound) {
    Ok((_, value)) => value
    Err(_) => return Err(@numeric.Unsupported)
  }
  let row_limits = managed_numeric_row_limits(setup.limits)
  let wire_limits = managed_numeric_wire_limits(setup.limits)
  let transfers = Array::makei(bridges.length(), index => {
    let bridge = bridges[index]
    NumericManagedInputTransfer::{
      input: managed_inputs[index],
      append: fn(row) {
        match
          @strategy.charge_task_execution_transfer(
            setup.run,
            execution,
            row.length().to_int64(),
          ) {
          Err(_) => Err(@numeric.Limit)
          Ok(_) =>
            @execution.append_managed_producer_bridge_wire(
              bridge, row, row_limits,
            ).map_err(issue => @numeric.ManagedBridge(issue))
        }
      },
      finish: fn() {
        @execution.finish_managed_producer_bridge(
          bridge,
          setup.limits.max_entries,
          setup.limits.max_name_bytes,
        )
        .map(value => reads[index] = Some(value))
        .map_err(issue => @numeric.ManagedBridge(issue))
      },
    }
  })
  let owner = @connector.managed_fixed_compute_request_owner(request)
  let output_target = @lower.preparation_output_target(
    @lower.bound_preparation(owner),
  )
  Ok({
    inputs: transfers,
    execute: fn() {
      guard live.val && reads.length() == 1 && reads[0] is Some(input) else {
        return Err(@numeric.Unsupported)
      }
      let output = match
        @numeric.execute_managed_numeric_output(
          setup.choice,
          setup.prepared,
          input,
          setup.generated,
          setup.limits,
          () => live.val,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      ordinary.val = Some(output)
      for bridge in bridges {
        @execution.close_managed_producer_bridge(bridge)
      }
      Ok(())
    },
    settle: fn() {
      @strategy.settle_task_execution(setup.run, execution, true).map_err(_ => {
        @numeric.Unsupported
      })
    },
    complete: fn(payload, storage_bytes, available) {
      guard ordinary.val is Some(output) &&
        output_target is Some(target) &&
        storage_bytes == setup.capacity.retained_bytes &&
        available() else {
        return Err(@numeric.Unsupported)
      }
      let values = match
        @execution.prepare_managed_output_values(
          owner,
          target,
          @connector.managed_fixed_compute_request_capacity(request).max_rows,
          setup.limits.values,
          @connector.managed_fixed_compute_request_capacity(request).max_value_bytes,
          setup.limits.physical,
        ) {
        Ok(value) => value
        Err(_) => return Err(@numeric.Limit)
      }
      let receipt_ref : Ref[@execution.ManagedOutputValueReceipt?] = Ref(None)
      let retention = match
        @execution.prepare_managed_output_retention_port(values, fn(
          proof : (@execution.ManagedOutputValueReceipt, T, Int64, () -> Bool),
        ) {
          let (receipt, proof_payload, bytes, proof_available) = proof
          if receipt_ref.val is Some(expected) &&
            physical_equal(receipt, expected) &&
            bytes == storage_bytes &&
            proof_available() &&
            available() {
            Some((receipt, proof_payload, bytes, proof_available))
          } else {
            None
          }
        }) {
        Ok(value) => value
        Err(_) => return Err(@numeric.Unsupported)
      }
      for row in 0..<@execution.completed_row_count(output) {
        match
          @execution.append_completed_projection_managed_values(
            values, output, row,
          ) {
          Ok(_) => ()
          Err(_) => return Err(@numeric.Unsupported)
        }
      }
      let receipt = match @execution.finish_managed_output_values(values) {
        Ok(value) => value
        Err(_) => return Err(@numeric.Unsupported)
      }
      receipt_ref.val = Some(receipt)
      let material = match
        @execution.retain_managed_output(
          retention,
          (receipt, payload, storage_bytes, available),
        ) {
        Ok(value) => value
        Err(_) => return Err(@numeric.Unsupported)
      }
      // The issuer is installed for this exact attempt only after the output
      // generation and its retained material both exist. It computes, rather
      // than approves, the registered canonical ordered-row identity.
      let issuer = identity_permit.map(permit => {
        @execution.bind_managed_identity_issuer(permit, material, fn(source) {
          if !physical_equal(source, material) || !available() {
            return None
          }
          match @execution.identify_completed_rows(output, wire_limits) {
            Ok(identity) => Some(@execution.row_wire_cid(identity))
            Err(_) => None
          }
        })
      })
      let port = match
        @execution.prepare_managed_completion_port(
          @execution.selected_managed_execution_profile(),
          setup.generated,
          target,
          setup.limits.max_entries,
          setup.limits.max_name_bytes,
          fn(candidate : @execution.ManagedRetainedOutput[T]) {
            if physical_equal(candidate, material) {
              Some(material)
            } else {
              None
            }
          },
          managed_inputs~,
          obligations=@connector.managed_fixed_compute_request_obligations(
            request,
          ),
          identity_issuer?=issuer,
        ) {
        Ok(value) => value
        Err(_) => return Err(@numeric.Unsupported)
      }
      let completed = match @execution.complete_managed_output(port, material) {
        Ok(value) => value
        Err(_) => return Err(@numeric.Unsupported)
      }
      for
        identity in @execution.managed_obligations_identities(
          @connector.managed_fixed_compute_request_obligations(request),
        ) {
        if identity.need is @execution.EstablishedBy(_) {
          match
            @execution.establish_managed_completed_identity(
              completed,
              identity.domain,
              identity.subject,
            ) {
            Ok(_) => ()
            Err(_) => return Err(@numeric.Unsupported)
          }
        }
      }
      if !@execution.managed_completed_deadline_satisfied(
          completed,
          @execution.BeforeCidOperation,
        ) ||
        !@execution.managed_completed_deadline_satisfied(
          completed,
          @execution.BeforeDiscard,
        ) {
        return Err(@numeric.Unsupported)
      }
      let allocation : @strategy.TaskRetainedAllocation? = if storage_bytes ==
        0L {
        None
      } else {
        match
          @strategy.retain_task_execution_allocation(
            setup.run,
            execution,
            storage_bytes,
          ) {
          Ok(value) => Some(value)
          Err(_) => return Err(@numeric.Limit)
        }
      }
      match
        @strategy.complete_managed_task_execution(
          setup.run,
          execution,
          completed,
          allocation?,
          managed_inputs~,
        ) {
        Err(_) => {
          if allocation is Some(value) {
            @strategy.release_task_execution_allocation(value) |> ignore
          }
          Err(@numeric.Unsupported)
        }
        Ok(_) => {
          retained.val = Some(material)
          Ok(completed)
        }
      }
    },
    output_rows: fn() {
      ordinary.val.map(@execution.completed_row_count).unwrap_or(0)
    },
    output_row: fn(row) {
      guard ordinary.val is Some(output) else {
        return Err(@numeric.Unsupported)
      }
      @execution.completed_output_row_wire(
        output,
        row,
        row_limits.max_bytes,
        row_limits.max_nodes,
        row_limits.max_depth,
      ).map_err(_ => @numeric.Unsupported)
    },
    material: fn() { retained.val },
    storage_bytes: setup.capacity.retained_bytes,
    close: fn() { @strategy.close_task_execution(setup.run, execution) },
    cleanup_refresh: fn() {
      @strategy.refresh_task_execution_cleanup(setup.run, execution).unwrap_or(
        false,
      )
    },
  })
}

///|
pub fn start_numeric_managed_dispatch_node(
  setup : NumericManagedDispatchConfiguration[Int],
) -> Result[NumericManagedDispatchOperations[Int], @numeric.PlanIssue] {
  start_numeric_managed_dispatch(setup)
}
