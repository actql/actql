example : ∀ rows, BridgeComposition.observeResult id (EventsBridge.toEvents rows) =
    EventsBridge.toEvents (id rows) := EventsBridge.to_events_respects
example : ∀ events, BridgeComposition.observeResult id (EventsBridge.toRows events) =
    EventsBridge.toRows (id events) := EventsBridge.to_rows_respects
example : ∀ rows, EventsBridge.admission rows = .ok () →
    BridgeComposition.composeResult (EventsBridge.toEvents rows) EventsBridge.toRows = .ok rows :=
  EventsBridge.round_trip
example : ∀ rows issue, EventsBridge.admission rows = .error issue →
    BridgeComposition.composeResult (EventsBridge.toEvents rows) EventsBridge.toRows = .error issue :=
  EventsBridge.rejected_input_preserves_error
example : ∀ rows, EventsBridge.admission rows = .ok () →
    BridgeComposition.composeResult (EventsBridge.toEvents rows) EventsBridge.toRows =
      .ok { schema := rows.schema, records := rows.records } :=
  EventsBridge.round_trip_schema_and_order
example : ∀ rows,
    BridgeComposition.observeResult id
      (BridgeComposition.composeResult (EventsBridge.toEvents rows) EventsBridge.toRows) =
    BridgeComposition.composeResult (EventsBridge.toEvents (id rows)) EventsBridge.toRows :=
  EventsBridge.observed_round_trip
