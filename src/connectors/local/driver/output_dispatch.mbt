///|
pub fn configure_local_retained_output(
  installed : LocalDispatchModule,
  limits : @local.LocalExportLimits,
  milliseconds : Int64?,
) -> Result[Unit, LocalDispatchIssue] {
  if installed.policy_sealed ||
    installed.output_policy is Some(_) ||
    installed.import_policy is None ||
    @strategy.strategy_history_count(installed.run) != 0 ||
    @local.local_export_retention_capacity(limits) is None ||
    (milliseconds is Some(value) && value < 0L) {
    return Err(Configuration(InvalidLimits))
  }
  installed.output_policy = Some((limits, milliseconds))
  Ok(())
}

///|
pub struct LocalRetainedRepresentation {
  material : @execution.RetainedOutputMaterial
  readable : (@execution.ProducerRead) -> Bool
}

///|
pub struct LocalExportContent {
  cid : String
  bytes : Int
  rows : Int
  tail : String
  bind : (() -> Bool) -> Result[LocalRetainedRepresentation, LocalDispatchIssue]
}

///|
pub struct LocalOutputTransfer {
  key : String
  limits : @local.LocalExportLimits
  install : (() -> Bool) -> Result[Unit, LocalDispatchIssue]
  begin : () -> Result[Unit, LocalDispatchIssue]
  next : () -> Result[String?, LocalDispatchIssue]
  finish : () -> Result[LocalExportContent, LocalDispatchIssue]
  refresh : () -> Result[Bool, LocalDispatchIssue]
}

///|
fn local_output_transfer(
  run : @strategy.CapturedDAG,
  ticket : @strategy.TaskExecution,
  attempt : @local.LocalMaterializingAttempt,
  index : Int,
  limits : @local.LocalExportLimits,
) -> LocalOutputTransfer {
  let issue = fn(value) {
    LocalDispatchIssue::Preparation(Materializing(value))
  }
  {
    key: "task-" + index.to_string(),
    limits,
    install: check => {
      @local.install_local_export_retention(attempt, check).map_err(issue)
    },
    begin: () => @local.begin_local_output_export(attempt).map_err(issue),
    next: () => @local.next_local_output_export(attempt).map_err(issue),
    finish: () => {
      @local.finish_local_output_export(attempt)
      .map(value => {
        let (content, tail) = value
        let (cid, bytes, _, rows) = @execution.output_stream_identity(content)
        {
          cid,
          bytes,
          rows,
          tail,
          bind: available => {
            let handle = @execution.retain_admitted_output_stream(
              content,
              (),
              available,
            )
            @local.bind_local_output_export(
              attempt,
              @execution.retained_output_material(handle),
            )
            .map(_ => {
              material: @execution.retained_output_material(handle),
              readable: input => {
                @execution.retained_producer_payload(handle, input) is Some(_)
              },
            })
            .map_err(issue)
          },
        }
      })
      .map_err(issue)
    },
    refresh: () => {
      @strategy.refresh_task_execution_cleanup(run, ticket).map_err(value => {
        Execution(Physical(value))
      })
    },
  }
}
