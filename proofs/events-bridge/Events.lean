namespace EventsBridge

-- Semantic model only: no allocation, pin, parser, UTC conversion or Owner model.
inductive Cell where
  | number (value : Int)
  | text (value : String)
  | null
  deriving DecidableEq

inductive Clock where
  | milliseconds (value : Int)
  | timestamp (authored : String)
  deriving DecidableEq

structure Field where
  name : String
  kind : String
  nullable : Bool
  deriving DecidableEq

structure Row where
  identity : Int
  clock : Clock
  payload : List Cell
  deriving DecidableEq

structure Rows where
  schema : List Field
  records : List Row
  deriving DecidableEq

structure EventRecord where
  key : Int
  time : Clock
  properties : List Cell
  deriving DecidableEq

structure Events where
  schema : List Field
  records : List EventRecord
  deriving DecidableEq

inductive Issue where
  | invalidSchema
  | invalidWidth
  | duplicateIdentity
  deriving DecidableEq

def fits (field : Field) (cell : Cell) : Bool :=
  match cell with
  | .null => field.nullable
  | .number _ => field.kind == "number"
  | .text _ => field.kind == "string"

def schemaAdmitted (schema : List Field) : Bool :=
  match schema with
  | idField :: clockField :: payload =>
    idField == ⟨"event_id", "number", false⟩ &&
    clockField.name == "occurred_at" && !clockField.nullable &&
    (clockField.kind == "number" || clockField.kind == "timestamp") &&
    (schema.map Field.name).all (fun name =>
      ((schema.map Field.name).filter (fun other => other == name)).length == 1) &&
    payload.all (fun field => field.kind == "number" || field.kind == "string")
  | _ => false

def rowAdmitted (schema : List Field) (row : Row) : Bool :=
  match schema with
  | _ :: clockField :: payload =>
    (match row.clock with
      | .milliseconds _ => clockField.kind == "number"
      | .timestamp _ => clockField.kind == "timestamp") &&
    (payload.zip row.payload).all (fun pair => fits pair.1 pair.2)
  | _ => false

-- UTC validity and numeric range admission remain implementation obligations;
-- clocks here are typed, and timestamp/text strings are retained exactly.
def admission (rows : Rows) : Except Issue Unit :=
  if !schemaAdmitted rows.schema || !rows.records.all (rowAdmitted rows.schema) then
    .error .invalidSchema
  else if rows.records.all (fun row => row.payload.length + 2 == rows.schema.length) then
    if (rows.records.map Row.identity).all (fun id =>
        ((rows.records.map Row.identity).filter (fun other => other == id)).length == 1) then
      .ok ()
    else .error .duplicateIdentity
  else .error .invalidWidth

def encodeRecord (row : Row) : EventRecord := ⟨row.identity, row.clock, row.payload⟩
def decodeRecord (event : EventRecord) : Row := ⟨event.key, event.time, event.properties⟩
def encodeRows (rows : Rows) : Events := ⟨rows.schema, rows.records.map encodeRecord⟩
def eventRows (events : Events) : Rows := ⟨events.schema, events.records.map decodeRecord⟩

theorem encoded_rows_round_trip (rows : Rows) : eventRows (encodeRows rows) = rows := by
  cases rows with
  | mk schema records =>
    have recordsLaw : (records.map encodeRecord).map decodeRecord = records := by
      induction records with
      | nil => rfl
      | cons row rest ih =>
        cases row
        simp [encodeRecord, decodeRecord, ih]
    simp [encodeRows, eventRows, recordsLaw]

def admittedRows (rows : Rows) : Except Issue Rows :=
  BridgeComposition.composeResult (admission rows) (fun _ => .ok rows)

def toEvents (rows : Rows) : Except Issue Events :=
  BridgeComposition.composeResult (admission rows) (fun _ => .ok (encodeRows rows))

def toRows (events : Events) : Except Issue Rows := .ok (eventRows events)

-- Both stages are checked against the same complete ordered Rows observation,
-- although the intermediate carrier has separate records and identity/time roles.
theorem to_events_respects (rows : Rows) :
    BridgeComposition.observeResult eventRows (toEvents rows) = admittedRows (id rows) := by
  cases decision : admission rows <;>
    simp [toEvents, admittedRows, decision, BridgeComposition.composeResult,
      BridgeComposition.observeResult, encoded_rows_round_trip]

theorem to_rows_respects (events : Events) :
    BridgeComposition.observeResult id (toRows events) = .ok (eventRows events) := rfl

theorem round_trip (rows : Rows) (h : admission rows = .ok ()) :
    BridgeComposition.composeResult (toEvents rows) toRows = .ok rows := by
  simp [toEvents, h, BridgeComposition.composeResult, toRows, encoded_rows_round_trip]

theorem rejected_input_preserves_error (rows : Rows) (issue : Issue)
    (h : admission rows = .error issue) :
    BridgeComposition.composeResult (toEvents rows) toRows = .error issue := by
  simp [toEvents, h, BridgeComposition.composeResult]

theorem round_trip_schema_and_order (rows : Rows) (h : admission rows = .ok ()) :
    BridgeComposition.composeResult (toEvents rows) toRows = .ok
      { schema := rows.schema, records := rows.records } := round_trip rows h

-- The output contract, rather than matching sorts, discharges the next premise.
theorem events_establish_precondition (rows : Rows) (events : Events)
    (completed : toEvents rows = .ok events) : admission (eventRows events) = .ok () := by
  cases decision : admission rows with
  | error issue => simp [toEvents, decision, BridgeComposition.composeResult] at completed
  | ok witness =>
    cases witness
    have same : encodeRows rows = events := by
      simpa [toEvents, decision, BridgeComposition.composeResult] using completed
    rw [← same, encoded_rows_round_trip, decision]

theorem rows_preserve_precondition (events : Events) (rows : Rows)
    (admitted : admission (eventRows events) = .ok ())
    (completed : toRows events = .ok rows) : admission rows = .ok () := by
  have same : eventRows events = rows := by simpa [toRows] using completed
  rw [← same]
  exact admitted

theorem sequential_contract (input output : Rows) (admitted : admission input = .ok ())
    (completed : BridgeComposition.composeResult (toEvents input) toRows = .ok output) :
    admission output = .ok () :=
  BridgeComposition.sequential_preconditions toEvents toRows
    (fun rows => admission rows = .ok ()) (fun events => admission (eventRows events) = .ok ())
    (fun rows => admission rows = .ok ())
    (fun rows events _ proof => events_establish_precondition rows events proof)
    rows_preserve_precondition input output admitted completed

-- Apply the shared law with a representation-changing middle observation.
theorem observed_round_trip (rows : Rows) :
    BridgeComposition.observeResult id (BridgeComposition.composeResult (toEvents rows) toRows) =
    BridgeComposition.composeResult (admittedRows (id rows)) (fun observed => .ok observed) :=
  BridgeComposition.observed_composition id eventRows id toEvents toRows admittedRows
    (fun observed => .ok observed) to_events_respects to_rows_respects rows

-- Nonvacuous witnesses: empty input, repeated payload, unsorted clock, NULL,
-- authored timestamp text, and duplicate ID failure. No product-generated oracle.
def schema : List Field := [⟨"event_id", "number", false⟩,
  ⟨"occurred_at", "number", false⟩, ⟨"payload", "string", true⟩]

def timestampSchema : List Field := [⟨"event_id", "number", false⟩,
  ⟨"occurred_at", "timestamp", false⟩, ⟨"payload", "string", true⟩]

example : admission ⟨schema, []⟩ = .ok () := rfl
example : admission ⟨schema, [⟨2, .milliseconds 10, [.null]⟩,
    ⟨1, .milliseconds 1, [.null]⟩]⟩ = .ok () := rfl
example : admission ⟨timestampSchema, [⟨1, .timestamp "1969-12-31T23:59:59.999Z", [.text "é\r\n"]⟩]⟩ =
    .ok () := rfl
example : admission ⟨schema, [⟨1, .milliseconds 1, [.text "first"]⟩,
    ⟨1, .milliseconds 2, [.text "second"]⟩]⟩ = .error .duplicateIdentity := rfl
example : admission ⟨schema, [⟨1, .milliseconds 1, [.number 3]⟩]⟩ = .error .invalidSchema := rfl
example : admission ⟨timestampSchema, [⟨1, .milliseconds 1, [.null]⟩]⟩ = .error .invalidSchema := rfl

end EventsBridge
