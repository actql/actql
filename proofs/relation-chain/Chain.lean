/- Contract model for finite serial chains. Child poll work is accepted only
   after its own Session/adapter obligations hold. Terminal observes physical
   stop under the checked prompt-stop premise; cleanup completion is separate.
   Values, child logical charges and capacity are deliberately not modeled. -/
namespace RelationChain

structure State where
  budget : Nat
  used : Nat
  reported : Nat
  childWork : Nat
  handoffWork : Nat
  started : Nat
  computes : Nat
  terminal : Bool
  owed : List Nat
  released : List Nat
  deriving Repr, DecidableEq

def initial (budget : Nat) : State :=
  ⟨budget, 0, 0, 0, 0, 1, 0, false, [0], []⟩

def Accounted (s : State) : Prop :=
  s.reported = s.used ∧ s.used = s.childWork + s.handoffWork ∧ s.used ≤ s.budget

def Responsible (s : State) : Prop :=
  ∀ id, id < s.started → id ∈ s.owed ∨ id ∈ s.released

def charge (s : State) (child control : Nat) : State :=
  { s with
    used := s.used + child + control
    reported := s.reported + child + control
    childWork := s.childWork + child
    handoffWork := s.handoffWork + control }

def childPoll (s : State) (work : Nat) (done : Bool) : State :=
  { (charge s work 0) with computes := s.computes + 1, terminal := done }

def handoff (s : State) (started : Bool) : State :=
  let charged := charge s 0 1
  if started then { charged with started := s.started + 1, owed := s.started :: s.owed }
  else { charged with terminal := true }

def stop (s : State) : State := { s with terminal := true }

def cleanup (s : State) (done : Bool) : State :=
  if s.terminal && done then
    match s.owed with
    | [] => s
    | id :: rest => { s with owed := rest, released := id :: s.released }
  else s

def remaining (s : State) : Nat := s.budget - s.used

-- Every constructor is a checked contract action, not a second production
-- owner. A stop confirmation cannot call Compute under the pilot premise.
inductive Step : State → State → Prop
  | poll (s : State) (work quantum : Nat) (done : Bool)
      (running : s.terminal = false) (positive : 0 < quantum)
      (bounded : work ≤ quantum) (budget : s.used + work ≤ s.budget) :
      Step s (childPoll s work done)
  | edge (s : State) (started : Bool) (running : s.terminal = false)
      (budget : s.used + 1 ≤ s.budget) : Step s (handoff s started)
  | stopped (s : State) : Step s (stop s)
  | reclaim (s : State) (done : Bool) : Step s (cleanup s done)

inductive Run : State → State → Prop
  | nil (s : State) : Run s s
  | cons {s middle last : State} : Step s middle → Run middle last → Run s last

theorem charge_accounted (s : State) (child control : Nat)
    (h : Accounted s) (room : s.used + child + control ≤ s.budget) :
    Accounted (charge s child control) := by
  rcases h with ⟨report, sum, _⟩
  change s.reported + child + control = s.used + child + control ∧
    s.used + child + control = (s.childWork + child) + (s.handoffWork + control) ∧
    s.used + child + control ≤ s.budget
  exact ⟨by omega, by omega, room⟩

theorem step_accounted {s t : State} (step : Step s t) (h : Accounted s) :
    Accounted t := by
  cases step with
  | poll work quantum done running positive bounded budget =>
    simpa [Accounted, childPoll, charge] using charge_accounted s work 0 h (by omega)
  | edge started running budget =>
    cases started <;> simpa [handoff, Accounted, charge] using
      charge_accounted s 0 1 h (by omega)
  | stopped => simpa [Accounted, stop] using h
  | reclaim done =>
    cases terminal : s.terminal <;> cases done <;>
      cases owed : s.owed <;> simp_all [cleanup, Accounted] <;> omega

theorem step_responsible {s t : State} (step : Step s t) (h : Responsible s) :
    Responsible t := by
  cases step with
  | poll work quantum done running positive bounded budget =>
    simpa [Responsible, childPoll, charge] using h
  | edge started running budget =>
    cases started
    · simpa [Responsible, handoff, charge] using h
    · intro id before
      simp only [handoff, ↓reduceIte, charge] at before ⊢
      by_cases last : id = s.started
      · left; simp [last]
      · have old : id < s.started := by omega
        rcases h id old with owed | released
        · left; simp [owed]
        · right; exact released
  | stopped => simpa [Responsible, stop] using h
  | reclaim done =>
    cases terminal : s.terminal <;> cases done
    all_goals simp only [cleanup, terminal, Bool.and_false, Bool.and_true, Bool.false_eq_true, ↓reduceIte]
    all_goals try exact h
    cases owed : s.owed with
    | nil => simpa [owed] using h
    | cons owner rest =>
      intro id before
      rcases h id before with pending | released
      · simp only [owed, List.mem_cons] at pending
        rcases pending with same | tail
        · right; simp [same]
        · left; exact tail
      · right; simp [released]

theorem finite_run_accounted {s t : State} (run : Run s t) (h : Accounted s) :
    Accounted t := by
  induction run with
  | nil => exact h
  | cons step tail ih => exact ih (step_accounted step h)

theorem finite_run_responsible {s t : State} (run : Run s t) (h : Responsible s) :
    Responsible t := by
  induction run with
  | nil => exact h
  | cons step tail ih => exact ih (step_responsible step h)

theorem initial_accounted (budget : Nat) : Accounted (initial budget) := by
  simp [initial, Accounted]

theorem initial_responsible (budget : Nat) : Responsible (initial budget) := by
  intro id small
  have zero : id = 0 := by simp only [initial] at small; omega
  left; simp [initial, zero]

theorem step_budget {s t : State} (step : Step s t) : t.budget = s.budget := by
  cases step with
  | poll => rfl
  | edge started => cases started <;> rfl
  | stopped => rfl
  | reclaim done =>
    cases terminal : s.terminal <;> cases done <;> cases owed : s.owed <;>
      simp [cleanup, terminal, owed]

theorem finite_run_budget {s t : State} (run : Run s t) : t.budget = s.budget := by
  induction run with
  | nil => rfl
  | cons step tail ih => exact ih.trans (step_budget step)

theorem chain_accounting (budget : Nat) (t : State) (run : Run (initial budget) t) :
    t.reported = t.childWork + t.handoffWork ∧ t.reported ≤ budget := by
  have h := finite_run_accounted run (initial_accounted budget)
  have sameBudget : t.budget = budget := by
    simpa [initial] using finite_run_budget run
  rcases h with ⟨report, sum, bounded⟩
  exact ⟨by omega, by omega⟩

theorem chain_responsibility (budget : Nat) (t : State) (run : Run (initial budget) t) :
    ∀ id, id < t.started → id ∈ t.owed ∨ id ∈ t.released :=
  finite_run_responsible run (initial_responsible budget)

theorem handoff_budget_not_reset (s : State) (started : Bool) :
    (handoff s started).used = s.used + 1 ∧
    remaining (handoff s started) = s.budget - (s.used + 1) := by
  cases started <;> simp [handoff, charge, remaining]

theorem failed_handoff_keeps_responsibility (s : State) :
    (handoff s false).owed = s.owed ∧ (handoff s false).started = s.started ∧
    (handoff s false).computes = s.computes := by
  exact ⟨rfl, rfl, rfl⟩

theorem cleanup_does_not_compute (s : State) (done : Bool) :
    (cleanup s done).started = s.started ∧
    (cleanup s done).computes = s.computes ∧
    (cleanup s done).reported = s.reported := by
  cases terminal : s.terminal <;> cases done <;> cases owed : s.owed <;>
    simp [cleanup, terminal, owed]

theorem pending_cleanup_keeps_responsibility (s : State) : cleanup s false = s := by
  simp [cleanup]

theorem terminal_step_no_compute {s t : State} (step : Step s t)
    (terminal : s.terminal = true) : t.computes = s.computes ∧ t.started = s.started := by
  cases step with
  | poll work quantum done running => simp_all
  | edge started running => simp_all
  | stopped => exact ⟨rfl, rfl⟩
  | reclaim done =>
    have clean := cleanup_does_not_compute s done
    exact ⟨clean.2.1, clean.1⟩

theorem step_terminal_preserved {s t : State} (step : Step s t)
    (terminal : s.terminal = true) : t.terminal = true := by
  cases step with
  | poll work quantum done running => simp_all
  | edge started running => simp_all
  | stopped => rfl
  | reclaim done =>
    cases done <;> cases owed : s.owed <;> simp [cleanup, terminal, owed]

theorem terminal_run_no_compute {s t : State} (trace : Run s t)
    (terminal : s.terminal = true) : t.computes = s.computes ∧ t.started = s.started := by
  induction trace with
  | nil => exact ⟨rfl, rfl⟩
  | cons step tail ih =>
    have preserved := terminal_step_no_compute step terminal
    have rest := ih (step_terminal_preserved step terminal)
    exact ⟨rest.1.trans preserved.1, rest.2.trans preserved.2⟩

theorem prompt_stop_does_not_compute (s : State) :
    (stop s).computes = s.computes ∧ (stop s).reported = s.reported ∧
    (stop s).owed = s.owed := by exact ⟨rfl, rfl, rfl⟩

theorem terminal_is_not_reclaimed (budget : Nat) :
    (stop (initial budget)).terminal = true ∧ (stop (initial budget)).owed ≠ [] := by
  simp [stop, initial]

-- Reuse the existing Session cumulative-to-delta theorem for each child;
-- folds then compose arbitrarily many such children plus explicit controls.
def childCost (reports : List Nat) := BoundedSession.charges 0 reports

theorem session_child_cost (reports : List Nat)
    (h : BoundedSession.MonotoneReports 0 reports) :
    childCost reports = BoundedSession.finalWork 0 reports :=
  BoundedSession.provider_accounting_instance reports h

theorem finite_children_cost (children : List (List Nat))
    (h : ∀ reports ∈ children, BoundedSession.MonotoneReports 0 reports) :
    (children.map childCost).sum =
      (children.map (BoundedSession.finalWork 0)).sum := by
  induction children with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.map_cons, List.sum_cons]
    rw [session_child_cost head (h head (by simp))]
    rw [ih (by intro x member; exact h x (by simp [member]))]

end RelationChain
