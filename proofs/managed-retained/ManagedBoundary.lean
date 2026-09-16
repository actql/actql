import Std

/- A limited contract model, not a proof of DuckDB, codecs, FFI or the Host.
   Witness truth and successful identity generation are trusted inputs here.
   Subject equality, issuance scope, publication and lifetime gates are modeled.
   Logical row-CID laws and PosEqStrict are neither imported nor weakened. -/
namespace ManagedBoundary

structure Subject where
  run : Nat
  producer : Nat
  attempt : Nat
  generation : Nat
  view : Nat
  scope : Nat
  deriving DecidableEq, Repr

structure Evidence where
  subject : Subject
  issuer : Nat
  kind : Nat
  contract : Nat
  deriving DecidableEq, Repr

structure State where
  subject : Subject
  required : List (Nat × Nat)
  issuers : List (Nat × Nat × Nat)
  evidence : List Evidence := []
  completed : Bool := false
  retained : Bool := true
  authorized : Bool := true
  revoked : Bool := false
  identityRequired : Bool := false
  identityEstablished : Bool := false
  pins : List Nat := []
  maxPins : Nat
  lateFailures : Nat := 0
  deriving DecidableEq, Repr

def admitted (s : State) (e : Evidence) : Bool :=
  decide (e.subject = s.subject ∧ (e.issuer, e.kind, e.contract) ∈ s.issuers)

def covered (s : State) : Bool :=
  s.required.all fun r => s.evidence.any fun e =>
    admitted s e && decide ((e.kind, e.contract) = r)

def usable (s : State) : Bool := s.retained && s.authorized && !s.revoked

def ready (s : State) : Bool :=
  usable s && covered s && (!s.identityRequired || s.identityEstablished)

inductive Action where
  | evidence (e : Evidence)
  | complete
  | acquire (token : Nat)
  | release (token : Nat)
  | revoke
  | reclaim
  | identitySucceeded
  | identityFailed
  deriving DecidableEq, Repr

def step (s : State) : Action → Option State
  | .evidence e => if usable s && admitted s e then
      some {s with evidence := e :: s.evidence} else none
  | .complete => if !s.completed && ready s then some {s with completed := true} else none
  | .acquire token => if usable s && !s.pins.contains token && decide (s.pins.length < s.maxPins)
      then some {s with pins := token :: s.pins} else none
  | .release token => if s.pins.contains token
      then some {s with pins := s.pins.filter (fun other => other != token)} else none
  | .revoke => some {s with revoked := true, authorized := false}
  | .reclaim => if s.revoked && s.pins.isEmpty then some {s with retained := false} else none
  | .identitySucceeded => if usable s then some {s with identityEstablished := true} else none
  | .identityFailed => some {s with lateFailures := s.lateFailures + 1}

theorem completion_requires_ready (s t : State)
    (h : step s .complete = some t) : ready s = true := by
  simp only [step] at h
  split at h
  next guard =>
    simp only [Bool.and_eq_true] at guard
    exact guard.2
  next => contradiction

theorem required_identity_precedes_completion (s t : State)
    (required : s.identityRequired = true)
    (h : step s .complete = some t) : s.identityEstablished = true := by
  have hr := completion_requires_ready s t h
  simp [ready, required] at hr
  exact hr.2

theorem uncovered_cannot_complete (s : State) (h : covered s = false) :
    step s .complete = none := by simp [step, ready, h]

theorem revoked_cannot_acquire (s : State) (token : Nat) (h : s.revoked = true) :
    step s (.acquire token) = none := by simp [step, usable, h]

theorem foreign_subject_cannot_issue (s : State) (e : Evidence)
    (h : e.subject ≠ s.subject) : step s (.evidence e) = none := by
  simp [step, admitted, h]

theorem foreign_issuer_scope_cannot_issue (s : State) (e : Evidence)
    (h : (e.issuer, e.kind, e.contract) ∉ s.issuers) :
    step s (.evidence e) = none := by simp [step, admitted, h]

theorem live_pin_prevents_reclamation (s : State) (token : Nat)
    (h : token ∈ s.pins) : step s .reclaim = none := by
  cases hp : s.pins with
  | nil => simp [hp] at h
  | cons head tail => simp [step, hp]

theorem foreign_release_cannot_change_state (s : State) (token : Nat)
    (h : token ∉ s.pins) : step s (.release token) = none := by
  simp [step, h]

theorem late_failure_preserves_completion (s : State) :
    (step s .identityFailed).map State.completed = some s.completed := by rfl

theorem late_failure_preserves_requirements (s : State) :
    (step s .identityFailed).map State.required = some s.required := by rfl

theorem successful_step_preserves_history (s t : State) (a : Action)
    (h : step s a = some t) (hc : s.completed = true) : t.completed = true := by
  cases a <;> simp only [step] at h <;>
    (try split at h) <;> simp_all <;> subst t <;> rfl

theorem successful_step_cannot_revive (s t : State) (a : Action)
    (h : step s a = some t) (hr : s.revoked = true) : t.revoked = true := by
  cases a <;> simp only [step] at h <;>
    (try split at h) <;> simp_all <;> subst t <;> rfl

inductive Trace : State → State → Prop where
  | refl (s) : Trace s s
  | next {s t u} (prior : Trace s t) (a : Action) (h : step t a = some u) : Trace s u

theorem revoked_trace_cannot_revive {s t : State} (path : Trace s t)
    (hr : s.revoked = true) : t.revoked = true := by
  induction path with
  | refl => exact hr
  | next prior a h ih => exact successful_step_cannot_revive _ _ a h ih

theorem completion_history_is_monotone {s t : State} (path : Trace s t)
    (hc : s.completed = true) : t.completed = true := by
  induction path with
  | refl => exact hc
  | next prior a h ih => exact successful_step_preserves_history _ _ a h ih

/- A small preservation rule: selection retains a universal bound, not the
   existence or position of a violation. Values/measurement interpretation are
   abstracted as natural quantities; codec correctness is outside this model. -/
def bounded (xs : List Nat) (ceiling : Nat) : Prop := ∀ x ∈ xs, x ≤ ceiling

theorem selected_bound (xs : List Nat) (keep : Nat → Bool) (low high : Nat)
    (bound : bounded xs low) (weaker : low ≤ high) : bounded (xs.filter keep) high := by
  intro x member
  exact Nat.le_trans (bound x (List.mem_filter.mp member).1) weaker

example : bounded ([100, 1].filter (fun x => decide (x < 64))) 64 := by
  simp [bounded]
example : ¬ bounded [100, 1] 64 := by simp [bounded]
example : ([120, 160].find? (fun x => decide (100 < x))) = some 120 := by decide

-- Positive completion without unrequested content identity is executable.
def sample : State := {
  subject := ⟨1, 2, 3, 4, 5, 6⟩, required := [], issuers := [], maxPins := 2
}

example : (step sample .complete).map State.identityEstablished = some false := by decide
example : step {sample with identityRequired := true} .complete = none := by decide
example : step {sample with pins := [7, 8]} (.acquire 9) = none := by decide

end ManagedBoundary

#print axioms ManagedBoundary.revoked_trace_cannot_revive
#print axioms ManagedBoundary.completion_history_is_monotone
#print axioms ManagedBoundary.selected_bound
