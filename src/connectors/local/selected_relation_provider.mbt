///|
/// Common Relation execution for one checked internal unary operation. Family
/// providers do not reinterpret or implement RelA after a Carrier bridge.
fn selected_relation_provider(
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> ManagedProvider {
  managed_provider(
    sequence => {
      match @execution.generated_completion_preparation(sequence) {
        preparation =>
          match @execution.completion_preparation_selected_step(preparation) {
            Some(step) =>
              match @execution.generated_sequence_step_at(sequence, 0) {
                Some(@lower.RowStep(_)) =>
                  @lower.node_at(
                    @lower.bound_preparation(
                      @execution.generated_sequence_owner(sequence),
                    ),
                    step,
                  )
                  .map(node => {
                    @lower.node_accepts_managed_relation_view(node, 0)
                  })
                  .unwrap_or(false)
                _ => false
              }
            None => false
          }
      }
    },
    sequence => {
      @execution.generated_sequence_capacity(sequence, limits, measurement)
    },
    (sequence, inputs, _max_rows, _max_value_bytes, execution) => {
      guard inputs is [input] else {
        return Err(@connector.Execution(@execution.InputSet))
      }
      let terminated = Ref(false)
      let canceled = Ref(false)
      Ok(
        managed_provider_execution(
          quantum => {
            if quantum <= 0 || terminated.val {
              return Err(@connector.InvalidLimits)
            }
            terminated.val = true
            if canceled.val {
              return Ok(managed_provider_stopped_poll(0L, 0L))
            }
            match
              @execution.execute_selected_relation_step(
                sequence, input, execution,
              ) {
              Ok((output, work)) =>
                Ok(managed_provider_complete(output, 0L, work))
              Err((issue, work)) =>
                Ok(
                  managed_provider_failed(@connector.Execution(issue), 0L, work),
                )
            }
          },
          fn() {
            canceled.val = true
            true
          },
          fn() { terminated.val },
          fn() { Ok(terminated.val) },
        ),
      )
    },
  )
}
