///|
fn emit_shared_work(
  w : @encode.Writer,
  work : SharedWorkEstimate,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  @encode.key(w, "required_slots")
  @encode.number_value(w, work.slots.to_double())
  @encode.key(w, "lines")
  @encode.begin_array(w)
  for line in work.lines {
    @encode.begin_object(w)
    @encode.key(w, "slots")
    @encode.begin_array(w)
    for slot in line.work_slots {
      @encode.number_value(w, slot.to_double())
    }
    @encode.end_array(w)
    @encode.key(w, "milliseconds")
    match line.milliseconds {
      Some(value) => @encode.string_value(w, value.to_string())
      None => @encode.null_value(w)
    }
    @encode.end_object(w)
  }
  @encode.end_array(w)
  @encode.end_object(w)
}

///|
/// Bounded Host-private diagnostics. Decimal strings preserve Int64 quantities;
/// null duration means unknown, not zero. No canonical identity is constructed.
pub fn explain_captured_strategy(
  run : CapturedDAG,
  max_bytes : Int,
  max_nodes : Int,
  excluded? : Array[(Int, String, String)] = [],
) -> Result[String, @encode.EncodeFailure] {
  try {
    let w = @encode.writer(max_bytes, max_nodes, 12)
    @encode.begin_object(w)
    @encode.key(w, "excluded_realizations")
    @encode.begin_array(w)
    for (task, capability, reason) in excluded {
      @encode.begin_object(w)
      @encode.key(w, "task")
      @encode.number_value(w, task.to_double())
      @encode.key(w, "capability")
      @encode.string_value(w, capability)
      @encode.key(w, "reason")
      @encode.string_value(w, reason)
      @encode.end_object(w)
    }
    @encode.end_array(w)
    @encode.key(w, "kind")
    @encode.string_value(w, "host-private-strategy-explanation/0.1")
    @encode.key(w, "program_success")
    @encode.bool_value(w, false)
    @encode.key(w, "ledger")
    emit_strategy_ledger(w, @resources.ledger_usage(run.ledger))
    @encode.key(w, "available_root_statistics")
    match captured_root_statistics(run) {
      None => @encode.null_value(w)
      Some(statistics) => {
        @encode.begin_object(w)
        emit_strategy_quantity(w, "rows", statistics.rows.to_int64())
        emit_strategy_quantity(
          w,
          "canonical_wire_bytes",
          statistics.canonical_wire_bytes.to_int64(),
        )
        @encode.end_object(w)
      }
    }
    @encode.key(w, "selection_state")
    @encode.string_value(
      w,
      if run.strategy is Some(_) {
        "selected"
      } else if !run.search_report_complete {
        "not_selected"
      } else {
        let mut feasible = false
        for assessment in run.search_report {
          if assessment.rejection is None {
            feasible = true
          }
        }
        if feasible {
          "deferred"
        } else {
          "no_feasible"
        }
      },
    )
    @encode.key(w, "selection")
    // Keep the last selected plan explainable after site cleanup revokes its
    // dispatch permission. History is diagnostic, never renewed authority.
    let displayed = match run.strategy {
      Some(revision) => Some(revision)
      None => run.revision_history.get(run.revision_history.length() - 1)
    }
    match displayed {
      None => @encode.null_value(w)
      Some(revision) => {
        @encode.begin_object(w)
        @encode.key(w, "dispatch_authorized")
        @encode.bool_value(w, run.strategy is Some(_) && !run.stopped)
        @encode.key(w, "revision")
        @encode.number_value(w, revision.number.to_double())
        @encode.key(w, "reason")
        @encode.string_value(
          w,
          if !revision.search_complete {
            "bounded_frontier"
          } else if revision.estimated_fastest {
            "estimated_fastest"
          } else {
            "host_preferred"
          },
        )
        @encode.key(w, "remaining_at_selection")
        emit_strategy_assessment(w, revision.assessment)
        @encode.key(w, "ledger_at_selection")
        emit_strategy_ledger(w, revision.before)
        @encode.key(w, "tasks")
        @encode.begin_array(w)
        for task = 1; task < revision.choices.length(); task = task + 1 {
          guard revision.choices[task] is Some(offer) else { continue }
          @encode.begin_object(w)
          @encode.key(w, "task")
          @encode.number_value(w, task.to_double())
          @encode.key(w, "completed")
          @encode.bool_value(w, task_done(run, task))
          @encode.key(w, "capability")
          @encode.string_value(
            w,
            @connector.capability_description(offer.registration).name,
          )
          @encode.key(w, "estimated_milliseconds")
          emit_strategy_duration(w, offer.duration)
          @encode.key(w, "resident_profile")
          match offer.resident {
            None => @encode.null_value(w)
            Some(profile) => {
              @encode.begin_object(w)
              emit_strategy_quantity(
                w,
                "database_bytes",
                profile.database_bytes,
              )
              @encode.key(w, "preparation_milliseconds")
              emit_strategy_duration(w, profile.preparation.duration)
              @encode.key(w, "preparation_work")
              emit_shared_work(w, profile.preparation)
              @encode.key(w, "cleanup_milliseconds")
              emit_strategy_duration(w, profile.cleanup.duration)
              @encode.key(w, "cleanup_work")
              emit_shared_work(w, profile.cleanup)
              @encode.key(w, "import_envelopes_by_producer")
              @encode.begin_array(w)
              for estimate in profile.imports {
                @encode.begin_object(w)
                @encode.key(w, "milliseconds")
                emit_strategy_duration(w, estimate.work.duration)
                @encode.key(w, "work")
                emit_shared_work(w, estimate.work)
                emit_strategy_quantity(
                  w,
                  "transfer_bytes",
                  estimate.transfer_bytes,
                )
                emit_strategy_quantity(
                  w,
                  "scratch_bytes",
                  estimate.scratch_bytes,
                )
                emit_strategy_quantity(w, "table_bytes", estimate.table_bytes)
                @encode.end_object(w)
              }
              @encode.end_array(w)
              @encode.end_object(w)
            }
          }
          @encode.key(w, "required_work_slots")
          @encode.number_value(w, offer.work_slots.to_double())
          @encode.key(w, "work_estimates")
          @encode.begin_array(w)
          for line in offer.lines {
            @encode.begin_object(w)
            @encode.key(w, "slots")
            @encode.begin_array(w)
            for slot in line.work_slots {
              @encode.number_value(w, slot.to_double())
            }
            @encode.end_array(w)
            @encode.key(w, "milliseconds")
            match line.milliseconds {
              Some(value) => @encode.string_value(w, value.to_string())
              None => @encode.null_value(w)
            }
            @encode.end_object(w)
          }
          @encode.end_array(w)
          @encode.key(w, "capacity")
          @encode.begin_object(w)
          emit_strategy_quantity(
            w,
            "transfer_bytes",
            offer.capacity.transfer_bytes,
          )
          emit_strategy_quantity(
            w,
            "retained_bytes",
            offer.capacity.retained_bytes,
          )
          emit_strategy_quantity(
            w,
            "execution_bytes",
            offer.capacity.execution_bytes,
          )
          @encode.end_object(w)
          @encode.end_object(w)
        }
        @encode.end_array(w)
        @encode.end_object(w)
      }
    }
    @encode.key(w, "assessed_strategies")
    @encode.begin_array(w)
    for assessment in run.search_report {
      emit_strategy_assessment(w, assessment)
    }
    @encode.end_array(w)
    @encode.key(w, "assessment_complete")
    @encode.bool_value(w, run.search_report_complete)
    @encode.key(w, "assessment_revision")
    @encode.number_value(w, run.revisions.to_double())
    @encode.end_object(w)
    Ok(@encode.finish(w))
  } catch {
    issue => Err(issue)
  }
}

///|
fn emit_strategy_quantity(
  w : @encode.Writer,
  key : String,
  value : Int64,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(w, key)
  @encode.string_value(w, value.to_string())
}

///|
fn emit_strategy_duration(
  w : @encode.Writer,
  duration : @cost.DurationEstimate,
) -> Unit raise @encode.EncodeFailure {
  match duration {
    Complete(value) => @encode.string_value(w, value.to_string())
    Unknown => @encode.null_value(w)
  }
}

///|
fn emit_strategy_ledger(
  w : @encode.Writer,
  usage : @resources.LedgerUsage,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  emit_strategy_quantity(w, "planning_work", usage.planning_work.to_int64())
  emit_strategy_quantity(w, "attempts", usage.attempts.to_int64())
  emit_strategy_quantity(w, "holdings", usage.holdings.to_int64())
  emit_strategy_quantity(w, "transferred_bytes", usage.transferred_bytes)
  emit_strategy_quantity(
    w,
    "uncertain_transfer_bytes",
    usage.uncertain_transfer_bytes,
  )
  emit_strategy_quantity(
    w,
    "reserved_transfer_bytes",
    usage.reserved_transfer_bytes,
  )
  emit_strategy_quantity(w, "held_bytes", usage.held_bytes)
  emit_strategy_quantity(
    w,
    "reserved_retention_bytes",
    usage.reserved_retention_bytes,
  )
  emit_strategy_quantity(
    w,
    "reserved_execution_bytes",
    usage.reserved_execution_bytes,
  )
  emit_strategy_quantity(w, "peak_retention_bytes", usage.peak_retention_bytes)
  @encode.end_object(w)
}

///|
fn emit_strategy_assessment(
  w : @encode.Writer,
  assessment : StrategyAssessment,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  @encode.key(w, "position")
  @encode.number_value(w, assessment.position.to_double())
  @encode.key(w, "estimated_milliseconds")
  emit_strategy_duration(w, assessment.duration)
  emit_strategy_quantity(w, "transfer_bytes", assessment.transfer_bytes)
  emit_strategy_quantity(w, "retained_bytes", assessment.retained_bytes)
  emit_strategy_quantity(w, "execution_bytes", assessment.execution_bytes)
  @encode.key(w, "rejection")
  match assessment.rejection {
    None => @encode.null_value(w)
    Some(issue) =>
      @encode.string_value(
        w,
        match issue {
          InvalidLimits => "invalid_limits"
          PlanningLimit => "planning_limit"
          AttemptLimit => "attempt_limit"
          HoldingLimit => "holding_limit"
          TransferLimit => "transfer_limit"
          RetentionLimit => "retention_limit"
          ExecutionLimit => "execution_limit"
          TokenLimit => "token_limit"
          CostLimit => "cost_limit"
          DurationLimit => "duration_limit"
          ForeignOwner => "foreign_owner"
          ClosedReservation => "closed_reservation"
          ClosedHolding => "closed_holding"
          InvalidCharge => "invalid_charge"
        },
      )
  }
  @encode.end_object(w)
}
