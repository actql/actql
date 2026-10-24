///|
/// Metadata admission is independent of payload and logical-row wire traversal.
/// These are validation ceilings, not a claim that every slot is allocated.
pub(all) struct LocalManagedMetadataLimits {
  name_bytes : Int
  bridge_entries : Int
  completion_entries : Int
  schema : @execution.RelationSchemaIdentityLimits
  result_workspace_entries : Int
  retained_bytes : Int64
}

///|
/// Explicit conservative conversion allowance. Configuration is frozen before
/// any estimate can escape; actual started capacity counts only missing copies.
/// The work estimate covers all imports required by this task, not one file.
pub fn configure_local_retained_inputs(
  installed : LocalDispatchModule,
  limits : @local.LocalImportLimits,
  milliseconds : Int64?,
  metadata? : LocalManagedMetadataLimits? = None,
) -> Result[Unit, LocalDispatchIssue] {
  if installed.policy_sealed ||
    installed.import_policy is Some(_) ||
    @strategy.strategy_history_count(installed.run) != 0 ||
    @local.local_import_retention_capacity(limits) is None ||
    limits.row.max_bytes > 16777216 ||
    limits.max_batch_bytes > 16777216 ||
    limits.row.max_depth < 1 ||
    limits.row.max_depth > 64 ||
    (milliseconds is Some(value) && value < 0L) {
    return Err(Configuration(InvalidLimits))
  }
  guard local_managed_metadata_limits(limits, metadata) is Some(selected) else {
    return Err(Configuration(InvalidLimits))
  }
  installed.import_metadata = Some(selected)
  installed.import_policy = Some((limits, milliseconds))
  Ok(())
}

///|
/// Installed Local-only operations. These are not a common backend enumeration
/// or result constructor. Every closure is bound to the admitted task attempt.
pub struct LocalInputFrames {
  maxBytes : Int
  maxRows : Int
  maxRowBytes : Int
  maxDepth : Int
  maxFrameBytes : Int
}

///|
pub struct LocalInputTransfer {
  material : @execution.RetainedOutputMaterial
  input : @execution.ProducerRead
  frames : LocalInputFrames
  begin : () -> Result[Unit, LocalDispatchIssue]
  charge : (Int64) -> Result[Unit, LocalDispatchIssue]
  append : (String) -> Result[Unit, LocalDispatchIssue]
  finish : () -> Result[Unit, LocalDispatchIssue]
}

///|
pub struct LocalDispatchOperations {
  inputs : Array[LocalInputTransfer]
  output : LocalOutputTransfer?
  execute : () -> Result[Unit, LocalDispatchIssue]
  advance : (Int) -> Result[LocalManagedAdvance, LocalDispatchIssue]
  request_cancel : () -> Bool
  execution_stopped : () -> Bool
  guard_usage : () -> Array[Int]
  // Work reported by the bounded provider of a completed attempt.
  provider_work : () -> Int64?
  // Diagnostic work remains observable after failure and close; not billing.
  cumulative_provider_work : () -> Result[
    Int64,
    @local.ManagedProviderWorkIssue,
  ]
  publication_output : () -> @execution.CompletedOutput?
  settle : () -> Result[Unit, LocalDispatchIssue]
  complete : () -> Result[Unit, LocalDispatchIssue]
  close : () -> Unit
  cleanup_refresh : () -> Bool
}

///|
pub fn[C, E] start_local_dispatch(
  installed : LocalDispatchModule,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
) -> Result[LocalDispatchOperations, LocalDispatchIssue] {
  let plan = match @host.take_installed_task(host, task, installed.channel) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  let run = installed.run
  let index = @host.prepared_task_index(task)
  match plan {
    Materializing(prepared, limits, output_limits) => {
      let (attempt, ticket) = match
        @strategy.start_captured_materializing_execution(run, index, prepared) {
        Ok(value) => value
        Err(issue) => return Err(Execution(issue))
      }
      guard @strategy.task_execution_numeric_reduction_count(run, ticket)
        is Some(numeric_count) else {
        @local.close_local_materializing_attempt(attempt)
        @strategy.fail_task_execution(run, ticket, ForeignCandidate) |> ignore
        return Err(Execution(ForeignCandidate))
      }
      if local_task_numeric_execution(run, ticket, numeric_count)
        is Some(numeric) &&
        !@local.bind_local_materializing_numeric_execution(attempt, numeric) {
        @local.close_local_materializing_attempt(attempt)
        @strategy.fail_task_execution(run, ticket, ForeignCandidate) |> ignore
        return Err(Execution(ForeignCandidate))
      }
      let inputs = []
      for port in 0..<@local.local_materializing_input_count(attempt) {
        let position = port
        if @local.local_materializing_input(attempt, port) is Some(input) &&
          @execution.producer_read_retained_material(input) is Some(material) &&
          !@execution.producer_read_has_cell_access(input) {
          inputs.push({
            material,
            input,
            frames: {
              maxBytes: limits.wire.max_bytes,
              maxRows: limits.max_rows,
              maxRowBytes: limits.row.max_bytes,
              maxDepth: limits.row.max_depth,
              maxFrameBytes: limits.max_batch_bytes,
            },
            begin: () => {
              @local.begin_local_materializing_input(attempt, position).map_err(issue => {
                  Preparation(Materializing(issue))
                },
              )
            },
            charge: bytes => {
              @strategy.charge_task_execution_transfer(run, ticket, bytes).map_err(issue => {
                  Execution(Physical(issue))
                },
              )
            },
            append: row => {
              @local.append_local_materializing_input(attempt, position, row).map_err(issue => {
                  Preparation(Materializing(issue))
                },
              )
            },
            finish: () => {
              @local.finish_local_materializing_input(attempt, position).map_err(issue => {
                  Preparation(Materializing(issue))
                },
              )
            },
          })
        }
      }
      Ok({
        inputs,
        output: output_limits.map(limits => {
          local_output_transfer(run, ticket, attempt, index, limits)
        }),
        execute: () => {
          match @local.execute_local_materializing_attempt(attempt) {
            Err(issue) =>
              Err(local_materializing_failure(run, ticket, attempt, issue))
            Ok(_) =>
              seal_local_materializing_numeric_completion(
                run, ticket, attempt, numeric_count,
              )
          }
        },
        advance: quantum => {
          match @local.advance_local_materializing_attempt(attempt, quantum) {
            Err(issue) =>
              Err(local_materializing_failure(run, ticket, attempt, issue))
            Ok(value) => {
              if value.complete {
                match
                  seal_local_materializing_numeric_completion(
                    run, ticket, attempt, numeric_count,
                  ) {
                  Err(issue) => return Err(issue)
                  Ok(_) => ()
                }
              }
              Ok({
                complete: value.complete,
                waiting: value.waiting,
                settlement: value.settlement,
                progress: value.progress,
                work: value.work,
              })
            }
          }
        },
        request_cancel: () => @local.cancel_local_materializing_attempt(attempt),
        execution_stopped: () => @local.local_materializing_stopped(attempt),
        guard_usage: () => {
          match @local.local_materializing_guard_usage(attempt) {
            Some((work, bytes, nodes)) => [work, bytes, nodes]
            None => []
          }
        },
        provider_work: () => @local.local_materializing_provider_work(attempt),
        cumulative_provider_work: () => {
          @local.local_materializing_cumulative_work(attempt)
        },
        publication_output: () => {
          @local.local_materializing_publication_output(attempt)
        },
        settle: () => {
          @strategy.settle_task_execution(run, ticket, true).map_err(issue => {
            Execution(Physical(issue))
          })
        },
        complete: () => {
          guard @local.local_materializing_completed_output(attempt)
            is Some(output) else {
            return Err(Preparation(Materializing(State)))
          }
          @strategy.complete_materializing_task_execution(run, ticket, output).map_err(issue => {
              Execution(issue)
            },
          )
        },
        close: fn() { @strategy.close_task_execution(run, ticket) },
        cleanup_refresh: fn() {
          if !@local.advance_local_materializing_cleanup(attempt, 64) {
            return false
          }
          @strategy.refresh_task_execution_cleanup(run, ticket).unwrap_or(false)
        },
      })
    }
  }
}

///|
/// Both bounded and draining callers close the same selected observation
/// domain before task completion can expose an output.
fn seal_local_materializing_numeric_completion(
  run : @strategy.CapturedDAG,
  ticket : @strategy.TaskExecution,
  attempt : @local.LocalMaterializingAttempt,
  numeric_count : Int,
) -> Result[Unit, LocalDispatchIssue] {
  if numeric_count > 0 && !@strategy.seal_task_numeric_reductions(run, ticket) {
    @local.close_local_materializing_attempt(attempt)
    @strategy.fail_task_execution(run, ticket, ForeignCandidate) |> ignore
    Err(Execution(ForeignCandidate))
  } else {
    Ok(())
  }
}

///|
/// A provider stop surfaces as the common stopped execution, not a state fault.
fn local_materializing_issue(
  attempt : @local.LocalMaterializingAttempt,
  issue : @local.LocalMaterializingIssue,
) -> LocalDispatchIssue {
  if issue is State && @local.local_materializing_stopped(attempt) {
    Execution(Stopped)
  } else {
    Preparation(Materializing(issue))
  }
}

///|
/// A failed computation is the task's primary failure, as for the retired
/// synchronous lane, so its typed evaluation evidence stays observable.
fn local_materializing_failure(
  run : @strategy.CapturedDAG,
  ticket : @strategy.TaskExecution,
  attempt : @local.LocalMaterializingAttempt,
  issue : @local.LocalMaterializingIssue,
) -> LocalDispatchIssue {
  if issue is Candidate(computation) {
    @strategy.fail_task_execution(run, ticket, Compute(computation)) |> ignore
  }
  local_materializing_issue(attempt, issue)
}

///|
fn local_managed_metadata_limits(
  limits : @local.LocalImportLimits,
  metadata : LocalManagedMetadataLimits?,
) -> LocalManagedMetadataLimits? {
  let selected = metadata.unwrap_or({
    name_bytes:limits.wire.max_bytes,
    bridge_entries: limits.wire.max_nodes,
    completion_entries: limits.wire.max_nodes,
    schema: {max_fields:limits.wire.max_columns,max_bytes:limits.wire.max_bytes,max_nodes:limits.wire.max_nodes,max_depth:limits.wire.max_depth},
    result_workspace_entries: limits.max_rows,
    retained_bytes: 0L,
  })
  if selected.name_bytes < 0 || selected.bridge_entries < 0 ||
    selected.completion_entries < 0 ||
    selected.schema.max_nodes < 0 || selected.schema.max_fields < 0 || selected.schema.max_bytes < 0 || selected.schema.max_depth < 0 ||
    selected.result_workspace_entries < 0 ||
    selected.retained_bytes < 0L {
    return None
  }
  Some(selected)
}

///|
/// One checked conversion for the offer and the actual retained holding.
fn local_retained_with_metadata(base : Int64, metadata : Int64) -> Int64? {
  if base < 0L || metadata < 0L || metadata > 9223372036854775807L - base {
    None
  } else { Some(base + metadata) }
}
