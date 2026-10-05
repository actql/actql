///|
/// A digest of the exact ordered, feasible assignment projection and whether
/// search was complete. The private offer handles remain local; the response
/// can only select the projected candidate positions.
fn strategy_policy_candidate_set(
  choices : StrategyChoiceSet,
) -> Result[PolicyCandidateSet, SearchIssue] {
  let writer = @encode.buffered_hashing_writer(8388608, 1000000, 24, 8388608) catch {
    _ => return Err(InvalidPreference)
  }
  try {
    @encode.begin_array(writer)
    @encode.string_value(writer, "actql-policy-candidates/0.1")
    @encode.string_value(
      writer,
      graph_program_definition_cid(choices.run.graph),
    )
    @encode.number_value(writer, choices.generation.to_double())
    @encode.number_value(writer, choices.revision.to_double())
    @encode.bool_value(writer, choices.run.search_report_complete)
    @encode.begin_array(writer)
    for candidate in choices.feasible {
      @encode.begin_array(writer)
      @encode.number_value(writer, candidate.assessment.position.to_double())
      emit_strategy_duration(writer, candidate.assessment.duration)
      @encode.string_value(
        writer,
        candidate.assessment.transfer_bytes.to_string(),
      )
      @encode.string_value(
        writer,
        candidate.assessment.retained_bytes.to_string(),
      )
      @encode.string_value(
        writer,
        candidate.assessment.execution_bytes.to_string(),
      )
      @encode.begin_array(writer)
      for task, offered in candidate.choices {
        match offered {
          None => @encode.null_value(writer)
          Some(offer) => {
            @encode.begin_array(writer)
            @encode.number_value(writer, task.to_double())
            @encode.string_value(
              writer,
              @connector.capability_registration_selection_key(
                offer.registration,
              ),
            )
            emit_strategy_duration(writer, offer.duration)
            @encode.number_value(writer, offer.work_slots.to_double())
            @encode.string_value(
              writer,
              offer.capacity.transfer_bytes.to_string(),
            )
            @encode.string_value(
              writer,
              offer.capacity.retained_bytes.to_string(),
            )
            @encode.string_value(
              writer,
              offer.capacity.execution_bytes.to_string(),
            )
            @encode.string_value(
              writer,
              offer.resident_output_bytes.to_string(),
            )
            @encode.begin_array(writer)
            for line in offer.lines {
              @encode.begin_array(writer)
              @encode.begin_array(writer)
              for slot in line.work_slots {
                @encode.number_value(writer, slot.to_double())
              }
              @encode.end_array(writer)
              match line.milliseconds {
                Some(value) => @encode.string_value(writer, value.to_string())
                None => @encode.null_value(writer)
              }
              @encode.end_array(writer)
            }
            @encode.end_array(writer)
            match offer.resident {
              None => @encode.null_value(writer)
              Some(profile) => {
                @encode.begin_array(writer)
                @encode.string_value(writer, profile.database_bytes.to_string())
                emit_shared_work(writer, profile.preparation)
                emit_shared_work(writer, profile.cleanup)
                @encode.begin_array(writer)
                for item in profile.imports {
                  @encode.begin_array(writer)
                  emit_shared_work(writer, item.work)
                  @encode.string_value(writer, item.transfer_bytes.to_string())
                  @encode.string_value(writer, item.scratch_bytes.to_string())
                  @encode.string_value(writer, item.table_bytes.to_string())
                  @encode.end_array(writer)
                }
                @encode.end_array(writer)
                @encode.end_array(writer)
              }
            }
            @encode.end_array(writer)
          }
        }
      }
      @encode.end_array(writer)
      @encode.end_array(writer)
    }
    @encode.end_array(writer)
    @encode.end_array(writer)
    let canonical_json = @encode.drain_hash_output(writer)
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    Ok({ cid: "sha256:" + digest, canonical_json, })
  } catch {
    _ => Err(InvalidPreference)
  }
}
