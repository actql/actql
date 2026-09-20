///|
/// Explicit conservative conversion allowance. Configuration is frozen before
/// any estimate can escape; actual started capacity counts only missing copies.
/// The work estimate covers all imports required by this task, not one file.
pub fn configure_local_retained_inputs(
  installed : LocalDispatchModule,
  limits : @local.LocalImportLimits,
  milliseconds : Int64?,
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
  settle : () -> Result[Unit, LocalDispatchIssue]
  complete : () -> Result[Unit, LocalDispatchIssue]
  close : () -> Unit
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
    Synchronous(compute) => {
      match @strategy.execute_captured_synchronous_task(run, index, compute) {
        Err(issue) => return Err(Execution(issue))
        Ok(_) => ()
      }
      Ok({
        inputs: [],
        output: None,
        execute: () => Ok(()),
        settle: () => Ok(()),
        complete: () => Ok(()),
        close: fn() {  },
      })
    }
    Materializing(prepared, limits, output_limits) => {
      let (attempt, ticket) = match
        @strategy.start_captured_materializing_execution(run, index, prepared) {
        Ok(value) => value
        Err(issue) => return Err(Execution(issue))
      }
      let inputs = []
      let mut port = 0
      while @local.local_materializing_input(attempt, port) is Some(input) {
        let position = port
        if @execution.producer_read_retained_material(input) is Some(material) &&
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
        port += 1
      }
      Ok({
        inputs,
        output: output_limits.map(limits => {
          local_output_transfer(run, ticket, attempt, index, limits)
        }),
        execute: () => {
          @local.execute_local_materializing_attempt(attempt).map_err(issue => {
            Preparation(Materializing(issue))
          })
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
      })
    }
  }
}
