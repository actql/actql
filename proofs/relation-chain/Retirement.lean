/- Conditional early scratch retirement over the existing productive chain.
   Pending denotes an accepted, stopped intermediate child. It does not denote
   an arbitrary cancel request. Outputs here are the parent's retained references,
   not physical allocations or permission to revoke externally held values. -/
namespace RelationChainRetirement

structure State where
  core : RelationChain.State
  pending : Bool
  outputs : List Nat
  deriving Repr, DecidableEq

def initial (budget : Nat) : State := ⟨RelationChain.initial budget, false, []⟩

def retireCore (s : RelationChain.State) (done : Bool) : RelationChain.State :=
  { (RelationChain.cleanup { s with terminal := true } done) with terminal := s.terminal }

def retire (s : State) (done : Bool) : State :=
  if s.pending then { s with core := retireCore s.core done } else s

def complete (s : State) (work : Nat) : State :=
  { s with
    core := RelationChain.childPoll s.core work false
    pending := true
    outputs := s.outputs ++ [s.core.started - 1] }

def handoff (s : State) : State :=
  { s with core := RelationChain.handoff s.core true, pending := false }

def cancelPending (s : State) : State :=
  { s with core := RelationChain.stop s.core }

def parentCleanup (s : State) (done : Bool) : State :=
  let clean := RelationChain.cleanup s.core done
  if s.core.terminal && done && clean.owed.isEmpty then ⟨clean, false, []⟩
  else { s with core := clean }

def CanHandoff (s : State) : Prop :=
  s.pending = true ∧ s.core.owed = [] ∧ s.core.terminal = false

def Invariant (s : State) : Prop :=
  RelationChain.Accounted s.core ∧ RelationChain.Responsible s.core ∧ s.core.owed.length ≤ 1

inductive Step : State → State → Prop
  | poll (s : State) (work quantum : Nat)
      (running : s.core.terminal = false) (productive : s.pending = false)
      (positive : 0 < quantum) (bounded : work ≤ quantum)
      (room : s.core.used + work ≤ s.core.budget) :
      Step s { s with core := RelationChain.childPoll s.core work false }
  | completed (s : State) (work quantum : Nat)
      (running : s.core.terminal = false) (productive : s.pending = false)
      (positive : 0 < quantum) (bounded : work ≤ quantum)
      (room : s.core.used + work ≤ s.core.budget) : Step s (complete s work)
  | control (s : State) (room : s.core.used + 1 ≤ s.core.budget)
      (admitted : CanHandoff s) :
      Step s { s with core := RelationChain.charge s.core 0 1 }
  | edge (s : State) (room : s.core.used + 1 ≤ s.core.budget)
      (admitted : CanHandoff s) : Step s (handoff s)
  | reclaimed (s : State) (done : Bool) : Step s (retire s done)
  | cancelled (s : State) (completed : s.pending = true) : Step s (cancelPending s)
  | finished (s : State) (work quantum : Nat)
      (running : s.core.terminal = false) (productive : s.pending = false)
      (positive : 0 < quantum) (bounded : work ≤ quantum)
      (room : s.core.used + work ≤ s.core.budget) :
      Step s { s with core := RelationChain.childPoll s.core work true }
  | cleaned (s : State) (done : Bool) : Step s (parentCleanup s done)

inductive Run : State → State → Prop
  | nil (s : State) : Run s s
  | cons {s middle last : State} : Step s middle → Run middle last → Run s last

theorem retire_core_accounted (s : RelationChain.State) (done : Bool)
    (h : RelationChain.Accounted s) : RelationChain.Accounted (retireCore s done) := by
  cases done <;> cases owed : s.owed <;> simp_all [retireCore, RelationChain.cleanup, RelationChain.Accounted] <;> omega

theorem retire_core_responsible (s : RelationChain.State) (done : Bool)
    (h : RelationChain.Responsible s) : RelationChain.Responsible (retireCore s done) := by
  have ready : RelationChain.Responsible { s with terminal := true } := h
  have retained := RelationChain.step_responsible
    (RelationChain.Step.reclaim { s with terminal := true } done) ready
  cases done <;> cases owed : s.owed <;>
    simpa [retireCore, RelationChain.cleanup, RelationChain.Responsible, owed] using retained

theorem retire_no_compute (s : State) (done : Bool) :
    (retire s done).core.computes = s.core.computes ∧
    (retire s done).core.started = s.core.started ∧
    (retire s done).core.reported = s.core.reported := by
  cases pending : s.pending <;> cases done <;> cases owed : s.core.owed <;>
    simp [retire, retireCore, RelationChain.cleanup, pending, owed]

theorem retire_preserves_outputs (s : State) (done : Bool) :
    (retire s done).outputs = s.outputs := by
  cases pending : s.pending <;> simp [retire, pending]

theorem pending_cleanup_identity (s : State) : retire s false = s := by
  cases s with
  | mk core pending outputs =>
    cases core
    cases pending <;> rfl

theorem successful_retirement_once (s : State) (id : Nat) (ready : s.pending = true)
    (single : s.core.owed = [id]) :
    (retire s true).core.owed = [] ∧
    (retire s true).core.released = id :: s.core.released ∧
    retire (retire s true) true = retire s true := by
  simp [retire, retireCore, RelationChain.cleanup, ready, single]

theorem completed_output_before_reclamation (s : State) (work : Nat) :
    (complete s work).pending = true ∧
    (complete s work).core.owed = s.core.owed ∧
    (complete s work).outputs = s.outputs ++ [s.core.started - 1] := by
  exact ⟨rfl, rfl, rfl⟩

theorem owed_child_blocks_handoff (s : State) (owed : s.core.owed ≠ []) :
    ¬ CanHandoff s := by
  intro admitted; exact owed admitted.2.1

theorem cancellation_preserves_custody (s : State) :
    (cancelPending s).core.owed = s.core.owed ∧
    (cancelPending s).outputs = s.outputs ∧
    (cancelPending s).core.computes = s.core.computes := by
  exact ⟨rfl, rfl, rfl⟩

theorem step_accounted {s t : State} (step : Step s t)
    (h : RelationChain.Accounted s.core) : RelationChain.Accounted t.core := by
  cases step with
  | poll work quantum running productive positive bounded room =>
    exact RelationChain.step_accounted
      (RelationChain.Step.poll s.core work quantum false running positive bounded room) h
  | completed work quantum running productive positive bounded room =>
    exact RelationChain.step_accounted
      (RelationChain.Step.poll s.core work quantum false running positive bounded room) h
  | finished work quantum running productive positive bounded room =>
    exact RelationChain.step_accounted
      (RelationChain.Step.poll s.core work quantum true running positive bounded room) h
  | control room admitted => simpa using RelationChain.charge_accounted s.core 0 1 h room
  | edge room admitted =>
    exact RelationChain.step_accounted (RelationChain.Step.edge s.core true admitted.2.2 room) h
  | cancelled completed => simpa [cancelPending, RelationChain.Accounted, RelationChain.stop] using h
  | reclaimed done =>
    cases pending : s.pending
    · simpa [retire, pending] using h
    · simpa [retire, pending] using retire_core_accounted s.core done h
  | cleaned done =>
    have clean := RelationChain.step_accounted (RelationChain.Step.reclaim s.core done) h
    simp only [parentCleanup]; split <;> exact clean

theorem step_responsible {s t : State} (step : Step s t)
    (h : RelationChain.Responsible s.core) : RelationChain.Responsible t.core := by
  cases step with
  | poll work quantum running productive positive bounded room =>
    exact RelationChain.step_responsible
      (RelationChain.Step.poll s.core work quantum false running positive bounded room) h
  | completed work quantum running productive positive bounded room =>
    exact RelationChain.step_responsible
      (RelationChain.Step.poll s.core work quantum false running positive bounded room) h
  | finished work quantum running productive positive bounded room =>
    exact RelationChain.step_responsible
      (RelationChain.Step.poll s.core work quantum true running positive bounded room) h
  | control room admitted => exact h
  | edge room admitted =>
    exact RelationChain.step_responsible (RelationChain.Step.edge s.core true admitted.2.2 room) h
  | cancelled completed => exact h
  | reclaimed done =>
    cases pending : s.pending
    · simpa [retire, pending] using h
    · simpa [retire, pending] using retire_core_responsible s.core done h
  | cleaned done =>
    have clean := RelationChain.step_responsible (RelationChain.Step.reclaim s.core done) h
    simp only [parentCleanup]; split <;> exact clean

theorem step_single_execution {s t : State} (step : Step s t)
    (h : s.core.owed.length ≤ 1) : t.core.owed.length ≤ 1 := by
  cases step with
  | poll => exact h
  | completed => exact h
  | finished => exact h
  | control => exact h
  | edge room admitted => simp [handoff, RelationChain.handoff, RelationChain.charge, admitted.2.1]
  | cancelled => exact h
  | reclaimed done =>
    cases pending : s.pending <;> cases done <;> cases owed : s.core.owed <;>
      simp_all [retire, retireCore, RelationChain.cleanup] <;> omega
  | cleaned done =>
    simp only [parentCleanup]; split
    all_goals cases terminal : s.core.terminal <;> cases done <;> cases owed : s.core.owed <;>
      simp_all [RelationChain.cleanup] <;> omega

theorem finite_run_invariant {s t : State} (run : Run s t) (h : Invariant s) : Invariant t := by
  induction run with
  | nil => exact h
  | cons step tail ih =>
    exact ih ⟨step_accounted step h.1, step_responsible step h.2.1, step_single_execution step h.2.2⟩

theorem initial_invariant (budget : Nat) : Invariant (initial budget) := by
  exact ⟨RelationChain.initial_accounted budget, RelationChain.initial_responsible budget, by simp [initial, RelationChain.initial]⟩

theorem step_budget {s t : State} (step : Step s t) : t.core.budget = s.core.budget := by
  cases step with
  | poll => rfl
  | completed => rfl
  | finished => rfl
  | control => rfl
  | edge => rfl
  | cancelled => rfl
  | reclaimed done =>
    cases pending : s.pending <;> cases done <;> cases owed : s.core.owed <;>
      simp [retire, retireCore, RelationChain.cleanup, pending, owed]
  | cleaned done =>
    simp only [parentCleanup]; split
    all_goals cases terminal : s.core.terminal <;> cases done <;> cases owed : s.core.owed <;>
      simp [RelationChain.cleanup, terminal, owed]

theorem finite_run_budget {s t : State} (run : Run s t) : t.core.budget = s.core.budget := by
  induction run with
  | nil => rfl
  | cons step tail ih => exact ih.trans (step_budget step)

theorem chain_accounting (budget : Nat) (t : State) (run : Run (initial budget) t) :
    t.core.reported = t.core.childWork + t.core.handoffWork ∧ t.core.reported ≤ budget := by
  have h := (finite_run_invariant run (initial_invariant budget)).1
  have sameBudget : t.core.budget = budget := by
    simpa [initial, RelationChain.initial] using finite_run_budget run
  rcases h with ⟨report, sum, bounded⟩
  exact ⟨by omega, by omega⟩

theorem step_terminal_no_compute {s t : State} (step : Step s t)
    (terminal : s.core.terminal = true) :
    t.core.terminal = true ∧ t.core.computes = s.core.computes ∧ t.core.started = s.core.started := by
  cases step with
  | poll work quantum running => simp_all
  | completed work quantum running => simp_all
  | finished work quantum running => simp_all
  | control room admitted => simp_all [CanHandoff]
  | edge room admitted => simp_all [CanHandoff]
  | cancelled => exact ⟨rfl, rfl, rfl⟩
  | reclaimed done =>
    cases pending : s.pending <;> cases done <;> cases owed : s.core.owed <;>
      simp [retire, retireCore, RelationChain.cleanup, pending, owed, terminal]
  | cleaned done =>
    simp only [parentCleanup]; split
    all_goals cases done <;> cases owed : s.core.owed <;>
      simp [RelationChain.cleanup, terminal, owed]

theorem terminal_run_no_compute {s t : State} (run : Run s t)
    (terminal : s.core.terminal = true) : t.core.computes = s.core.computes ∧ t.core.started = s.core.started := by
  induction run with
  | nil => exact ⟨rfl, rfl⟩
  | cons step tail ih =>
    have next := step_terminal_no_compute step terminal
    have rest := ih next.1
    exact ⟨rest.1.trans next.2.1, rest.2.trans next.2.2⟩

end RelationChainRetirement
