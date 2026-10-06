example : ∀ rows, EventsBridge.eventRows (EventsBridge.encodeRows rows) = rows :=
  EventsBridge.encoded_rows_round_trip
example : ∀ rows, BridgeComposition.observeResult EventsBridge.eventRows (EventsBridge.toEvents rows) =
    EventsBridge.admittedRows (id rows) := EventsBridge.to_events_respects
example : ∀ events, BridgeComposition.observeResult id (EventsBridge.toRows events) =
    .ok (EventsBridge.eventRows events) := EventsBridge.to_rows_respects
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
example : ∀ rows events, EventsBridge.toEvents rows = .ok events →
    EventsBridge.admission (EventsBridge.eventRows events) = .ok () :=
  EventsBridge.events_establish_precondition
example : ∀ events rows, EventsBridge.admission (EventsBridge.eventRows events) = .ok () →
    EventsBridge.toRows events = .ok rows → EventsBridge.admission rows = .ok () :=
  EventsBridge.rows_preserve_precondition
example : ∀ input output, EventsBridge.admission input = .ok () →
    BridgeComposition.composeResult (EventsBridge.toEvents input) EventsBridge.toRows = .ok output →
    EventsBridge.admission output = .ok () := EventsBridge.sequential_contract
example : ∀ rows,
    BridgeComposition.observeResult id
      (BridgeComposition.composeResult (EventsBridge.toEvents rows) EventsBridge.toRows) =
    BridgeComposition.composeResult (EventsBridge.admittedRows (id rows)) (fun observed => .ok observed) :=
  EventsBridge.observed_round_trip
