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
    !local_retained_output_policy_valid(limits, milliseconds) {
    return Err(Configuration(InvalidLimits))
  }
  installed.preparation = local_dispatch_preparation_policies(
    installed.preparation,
    installed.import_policy,
    installed.import_metadata,
    Some((limits, milliseconds)),
  )
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
  prepare : (Int) -> Result[(Bool, Int), LocalDispatchIssue]
  next : () -> Result[String?, LocalDispatchIssue]
  advance : (Int) -> Result[
    @execution.CompletedOutputExportAdvance,
    LocalDispatchIssue,
  ]
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
  reserve? : ((Int64, Int64) -> Result[Unit, LocalDispatchIssue])? = None,
) -> LocalOutputTransfer {
  let issue = fn(value) {
    LocalDispatchIssue::Preparation(Materializing(value))
  }
  let original : LocalOutputTransfer = {
    key: "task-" + index.to_string(),
    limits,
    install: check => {
      @local.install_local_export_retention(attempt, check).map_err(issue)
    },
    begin: () => @local.begin_local_output_export(attempt).map_err(issue),
    prepare: quantum => {
      @local.advance_local_output_export_preparation(attempt, quantum).map_err(
        issue,
      )
    },
    next: () => @local.next_local_output_export(attempt).map_err(issue),
    advance: quantum => {
      @local.advance_local_output_export(attempt, quantum).map_err(issue)
    },
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
  guard reserve is Some(_) else { return original }
  let emitted = Ref(0L)
  let working = Ref(0L)
  let retained = Ref(0L)
  let failed : Ref[LocalDispatchIssue?] = Ref(None)
  let fund = fn(
    pending : Int,
  ) -> Result[Bool, @execution.CompletedExportIssue] {
    guard pending >= 0 else { return Err(Admission(InvalidCaptureLimits)) }
    if reserve is Some(grow) {
      guard @execution.checked_preparation_add_product(
          emitted.val,
          pending.to_int64(),
          8L,
        )
        is Some(w) &&
        @execution.checked_preparation_add_product(
          emitted.val,
          pending.to_int64(),
          1L,
        )
        is Some(r) else {
        return Err(Admission(InvalidCaptureLimits))
      }
      // The sealed file is consumed after Task completion. Its verifier and
      // frame aliases are bounded by this SAME frame policy and actual file
      // prefix, so retain that reusable window rather than ended writer E.
      guard @execution.checked_preparation_add_product(
          r,
          Int64::min(r, limits.max_batch_bytes.to_int64()),
          8L,
        )
        is Some(r) else {
        return Err(Admission(InvalidCaptureLimits))
      }
      let w = Int64::max(working.val, Int64::max(w, r))
      let r = Int64::max(retained.val, r)
      match grow(w, r) {
        Err(issue) => {
          failed.val = Some(issue)
          return Err(Admission(CaptureLimit))
        }
        Ok(_) => {
          working.val = w
          retained.val = r
          failed.val = None
        }
      }
    }
    Ok(true)
  }
  let observe = fn(part : String) {
    match managed_row_transfer_bytes(part, limits.wire.max_bytes) {
      Err(issue) => Err(issue)
      Ok(bytes) => {
        guard @execution.checked_preparation_add_product(emitted.val, bytes, 1L)
          is Some(next) &&
          (reserve is None || next <= retained.val) else {
          return Err(Configuration(InvalidLimits))
        }
        emitted.val = next
        Ok(())
      }
    }
  }
  {
    ..original,
    next: () => {
      if reserve is None {
        return @local.next_local_output_export(attempt).map_err(issue)
      }
      let mut complete = false
      let mut batch : String? = None
      while !complete && batch is None {
        let value = match
          @local.advance_local_output_export(
            attempt,
            64,
            before_batch_growth=Some(fund),
          ) {
          Ok(value) => value
          Err(value) => return Err(failed.val.unwrap_or(issue(value)))
        }
        batch = value.batch
        complete = value.complete
      }
      if batch is Some(part) {
        match observe(part) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
      }
      Ok(batch)
    },
    advance: quantum => {
      @local.advance_local_output_export(
        attempt,
        quantum,
        before_batch_growth=reserve.map(_ => fund),
      )
      .map_err(value => failed.val.unwrap_or(issue(value)))
      .bind(value => {
        if value.batch is Some(part) {
          match observe(part) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
        }
        Ok(value)
      })
    },
    finish: () => {
      match fund(if emitted.val == 0L { 2 } else { 1 }) {
        Ok(true) => ()
        _ => return Err(failed.val.unwrap_or(Configuration(InvalidLimits)))
      }
      @local.finish_local_output_export(attempt)
      .map_err(issue)
      .bind(value => {
        let (content, tail) = value
        match observe(tail) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        let (cid, bytes, _, rows) = @execution.output_stream_identity(content)
        Ok({
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
        })
      })
    },
  }
}
