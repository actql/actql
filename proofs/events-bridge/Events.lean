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

structure Events where
  rows : Rows
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

def toEvents (rows : Rows) : Except Issue Events :=
  BridgeComposition.composeResult (admission rows) (fun _ => .ok ⟨rows⟩)

def toRows (events : Events) : Except Issue Rows := .ok events.rows

-- Full ordered semantic values are the observations for this instance.
-- No equivalence discards schema, row order, duplicates, NULL or text bytes.
theorem to_events_respects (rows : Rows) :
    BridgeComposition.observeResult id (toEvents rows) = toEvents (id rows) :=
  BridgeComposition.observe_identity (toEvents rows)

theorem to_rows_respects (events : Events) :
    BridgeComposition.observeResult id (toRows events) = toRows (id events) :=
  BridgeComposition.observe_identity (toRows events)

theorem round_trip (rows : Rows) (h : admission rows = .ok ()) :
    BridgeComposition.composeResult (toEvents rows) toRows = .ok rows := by
  simp [toEvents, h, BridgeComposition.composeResult, toRows]

theorem rejected_input_preserves_error (rows : Rows) (issue : Issue)
    (h : admission rows = .error issue) :
    BridgeComposition.composeResult (toEvents rows) toRows = .error issue := by
  simp [toEvents, h, BridgeComposition.composeResult]

theorem round_trip_schema_and_order (rows : Rows) (h : admission rows = .ok ()) :
    BridgeComposition.composeResult (toEvents rows) toRows = .ok
      { schema := rows.schema, records := rows.records } := round_trip rows h

-- Apply the shared observation-composition law to two distinct carriers.
theorem observed_round_trip (rows : Rows) :
    BridgeComposition.observeResult id (BridgeComposition.composeResult (toEvents rows) toRows) =
    BridgeComposition.composeResult (toEvents (id rows)) toRows :=
  BridgeComposition.observed_composition id id id toEvents toRows toEvents toRows
    to_events_respects to_rows_respects rows

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
