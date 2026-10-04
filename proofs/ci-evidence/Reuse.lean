import Lean

/- This checks supplied, independently authenticated action applications.
   It does not prove completeness of Git dependency extraction, hash collision
   resistance, CI provenance authentication or compiler/runtime determinism. -/
namespace IncrementalEvidence

structure Requirement where
  action : String
  candidate : String
  kind : String
  target : String
  scope : String
  premises : String
  inputs : String
  minimumUnits : Nat
  deriving Repr, DecidableEq

structure Application where
  action : String
  origin : String
  kind : String
  target : String
  scope : String
  premises : String
  inputs : String
  units : Nat
  authenticated : Bool
  successful : Bool
  reused : Bool
  closed : Bool
  mainOrigin : Bool
  deriving Repr, DecidableEq

def ValidApplication (required : Requirement) (application : Application) : Prop :=
  application.authenticated = true ∧ application.successful = true ∧
  application.action = required.action ∧ application.kind = required.kind ∧
  application.target = required.target ∧ application.scope = required.scope ∧
  application.premises = required.premises ∧ application.inputs = required.inputs ∧
  required.minimumUnits ≤ application.units ∧
  (if application.reused then application.closed = true ∧ application.mainOrigin = true
   else application.origin = required.candidate)

instance (required : Requirement) (application : Application) :
    Decidable (ValidApplication required application) := by
  unfold ValidApplication
  infer_instance

def ValidPlan : List Requirement → List Application → Prop
  | [], [] => True
  | r :: rs, a :: as => ValidApplication r a ∧ ValidPlan rs as
  | _, _ => False

def check : List Requirement → List Application → Bool
  | [], [] => true
  | r :: rs, a :: as => decide (ValidApplication r a) && check rs as
  | _, _ => false

theorem checker_sound (required : List Requirement) (applications : List Application)
    (accepted : check required applications = true) : ValidPlan required applications := by
  induction required generalizing applications with
  | nil => cases applications <;> simp_all [check, ValidPlan]
  | cons r rs ih =>
    cases applications with
    | nil => simp [check] at accepted
    | cons a as =>
      have h : decide (ValidApplication r a) = true ∧ check rs as = true := by
        simpa only [check, Bool.and_eq_true] using accepted
      exact ⟨of_decide_eq_true h.1, ih as h.2⟩

theorem checker_complete (required : List Requirement) (applications : List Application)
    (valid : ValidPlan required applications) : check required applications = true := by
  induction required generalizing applications with
  | nil => cases applications <;> simp_all [check, ValidPlan]
  | cons r rs ih =>
    cases applications with
    | nil => simp [ValidPlan] at valid
    | cons a as =>
      rcases valid with ⟨head, tail⟩
      simp only [check, Bool.and_eq_true]
      exact ⟨decide_eq_true head, ih as tail⟩

theorem scope_and_kind_preserved (required : Requirement) (application : Application)
    (valid : ValidApplication required application) :
    application.kind = required.kind ∧ application.target = required.target ∧
    application.scope = required.scope ∧ application.premises = required.premises := by
  exact ⟨valid.2.2.2.1, valid.2.2.2.2.1, valid.2.2.2.2.2.1, valid.2.2.2.2.2.2.1⟩

theorem required_obligations_preserved (required : List Requirement)
    (applications : List Application) (valid : ValidPlan required applications) :
    required.map Requirement.action = applications.map Application.action := by
  induction required generalizing applications with
  | nil => cases applications <;> simp_all [ValidPlan]
  | cons r rs ih =>
    cases applications with
    | nil => simp [ValidPlan] at valid
    | cons a as =>
      rcases valid with ⟨head, tail⟩
      simp only [List.map_cons]
      rw [head.2.2.1, ih as tail]

theorem identical_inputs_preserve_observation {Source Input Evidence : Type}
    (inputs : Source → Input) (observe : Input → Evidence) (origin candidate : Source)
    (same : inputs origin = inputs candidate) :
    observe (inputs origin) = observe (inputs candidate) := by
  exact congrArg observe same

end IncrementalEvidence
