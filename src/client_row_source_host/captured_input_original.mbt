///|
/// Closed borrowed Source custody. A restored input borrows its actual receiving
/// allocation and buffer; it never acquires a RowRun or completed task identity.
struct RowCapturedInput {
  original : RowCapturedInputOriginal
}

///|
priv enum RowCapturedInputOriginal {
  Live(RowSourceCapture)
  Restored(
    RowInputAcquisition,
    RowRestoredOriginalInput,
    @query.CapturedInputSource,
    @resources.Ledger,
    @resources.Reservation,
    @resources.Holding,
    Ref[Bool]
  )
}

///|
pub fn row_capture_input(capture : RowSourceCapture) -> RowCapturedInput? {
  guard capture.run.configuration is DirectConfiguration(_) ||
    capture.run.configuration is InputConfiguration(_) else {
    return None
  }
  let value = RowCapturedInput::{ original: Live(capture), }
  if row_captured_input_source(value) is Some(_) {
    Some(value)
  } else {
    None
  }
}

///|
/// Only the existing receiving Source owner supplies these exact typed tokens.
pub fn restored_row_capture_input(
  acquisition : RowInputAcquisition,
  original : RowRestoredOriginalInput,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
  holding : @resources.Holding,
  live : Ref[Bool],
) -> RowCapturedInput? {
  let value = RowCapturedInput::{
    original: Restored(
      acquisition, original, source, ledger, reservation, holding, live,
    ),
  }
  guard row_captured_input_source(value) is Some(_) &&
    row_captured_input_fence(value, ledger, reservation, holding, false) else {
    return None
  }
  Some(value)
}

///|
pub fn row_captured_input_source(
  value : RowCapturedInput,
) -> @query.CapturedInputSource? {
  match value.original {
    Live(capture) => {
      guard row_capture_source(capture) is Ok(source) else { return None }
      let matches = match capture.run.configuration {
        DirectConfiguration(configuration) =>
          @query.captured_source_matches_query(
            source,
            @planning.query_material_owner(
              @planning.query_requirement_material(configuration.requirement),
            ),
          )
        InputConfiguration(acquisition) =>
          @query.captured_source_matches_input_acquisition(
            source,
            acquisition.preparation.original,
          )
        _ => false
      }
      if matches {
        Some(source)
      } else {
        None
      }
    }
    Restored(acquisition, original, source, ledger, _, holding, live) => {
      guard live.val &&
        restored_row_original_read(original) is Some(read) &&
        @query.captured_source_matches_input_acquisition(
          source,
          acquisition.preparation.original,
        ) &&
        @query.captured_source_original_input_read(source) is Some(actual) &&
        @execution.supplied_relation_read_same_binding(read, actual) &&
        live.val &&
        original.live.val &&
        @resources.holding_available(ledger, holding) else {
        return None
      }
      Some(source)
    }
  }
}

///|
pub fn row_captured_input_source_original(
  value : RowCapturedInput,
) -> @sourcequery.SourceAcquisition? {
  match value.original {
    Live(capture) =>
      match capture.run.configuration {
        InputConfiguration(acquisition) =>
          Some(acquisition.preparation.original)
        _ => None
      }
    Restored(acquisition, _, _, _, _, _, _) =>
      Some(acquisition.preparation.original)
  }
}

///|
fn row_captured_input_pair(
  value : RowCapturedInput,
  ledger : @resources.Ledger,
) -> (@resources.Reservation, @resources.Holding)? {
  match value.original {
    Live(capture) => {
      guard !capture.run.closed &&
        capture.run.physical is Some(physical) &&
        physical_equal(physical.ledger, ledger) &&
        physical.dag is None &&
        physical.holding is Some(holding) else {
        return None
      }
      Some((physical.reservation, holding))
    }
    Restored(_, _, _, original, reservation, holding, _) =>
      if physical_equal(original, ledger) {
        Some((reservation, holding))
      } else {
        None
      }
  }
}

///|
// Callback-free census after ALL Source/current callbacks, including siblings.
fn row_captured_input_fence(
  value : RowCapturedInput,
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
  original : @resources.Holding,
  allow_dag : Bool,
) -> Bool {
  match value.original {
    Live(capture) => {
      guard !capture.run.closed &&
        capture.run.physical is Some(physical) &&
        physical_equal(physical.ledger, ledger) &&
        physical_equal(physical.reservation, reservation) else {
        return false
      }
      match (physical.dag, physical.holding) {
        (None, Some(holding)) => physical_equal(holding, original)
        (Some((dag, task)), None) =>
          allow_dag &&
          @strategy.captured_task_allocation_matches(dag, task, original)
        _ => false
      }
    }
    Restored(_, input, _, actual_ledger, actual_reservation, holding, live) =>
      live.val &&
      input.live.val &&
      physical_equal(actual_ledger, ledger) &&
      physical_equal(actual_reservation, reservation) &&
      physical_equal(holding, original) &&
      @resources.holding_available(ledger, holding)
  }
}
