/- Stop-inclusive contract extension of the existing productive chain model.
   Stop requests are not stop observations. Accepted stop-only poll deltas add
   diagnostic work without restoring productive budget or starting a child.
   This is a model, not a second runtime owner or an eventual-stop assumption. -/
namespace RelationChainStop

structure State where
  productive : RelationChain.State
  requested : Bool
  stopWork : Nat
  deriving Repr, DecidableEq

def initial (budget : Nat) : State := ⟨RelationChain.initial budget, false, 0⟩
def reported (s : State) : Nat := s.productive.reported + s.stopWork

def request (s : State) : State := { s with requested := true }
def stopPoll (s : State) (work : Nat) (done : Bool) : State :=
  { s with
    productive := if done then RelationChain.stop s.productive else s.productive
    stopWork := s.stopWork + work }
def reclaim (s : State) (done : Bool) : State :=
  { s with productive := RelationChain.cleanup s.productive done }

-- The pause tag is observable at the provider boundary. It does not confer
-- physical-stop or reclamation authority on the accounting state.
inductive Pause where
  | waiting
  | settling (slot : Nat)
  deriving Repr, DecidableEq

def stopPause (s : State) (work : Nat) : State := stopPoll s work false

inductive Step : State → State → Prop
  | productive (s : State) (t : RelationChain.State) (notRequested : s.requested = false)
      (step : RelationChain.Step s.productive t) :
      Step s { s with productive := t }
  | request (s : State) : Step s (RelationChainStop.request s)
  | stopPoll (s : State) (work quantum : Nat) (done : Bool)
      (requested : s.requested = true) (running : s.productive.terminal = false)
      (positive : 0 < quantum) (bounded : work ≤ quantum)
      (valid : done = true ∨ 0 < work) : Step s (RelationChainStop.stopPoll s work done)
  | stopPause (s : State) (kind : Pause) (work quantum : Nat)
      (requested : s.requested = true) (running : s.productive.terminal = false)
      (positive : 0 < quantum) (bounded : work ≤ quantum) :
      Step s (RelationChainStop.stopPause s work)
  | reclaim (s : State) (done : Bool) : Step s (RelationChainStop.reclaim s done)

inductive Run : State → State → Prop
  | nil (s : State) : Run s s
  | cons {s middle last : State} : Step s middle → Run middle last → Run s last

theorem step_accounted {s t : State} (step : Step s t)
    (h : RelationChain.Accounted s.productive) : RelationChain.Accounted t.productive := by
  cases step with
  | productive next notRequested checked => exact RelationChain.step_accounted checked h
  | request => exact h
  | stopPoll work quantum done requested running positive bounded valid =>
    cases done <;> simpa [stopPoll, RelationChain.stop, RelationChain.Accounted] using h
  | stopPause kind work quantum requested running positive bounded =>
    simpa [stopPause, stopPoll] using h
  | reclaim done => exact RelationChain.step_accounted (RelationChain.Step.reclaim s.productive done) h

theorem run_accounted {s t : State} (run : Run s t)
    (h : RelationChain.Accounted s.productive) : RelationChain.Accounted t.productive := by
  induction run with
  | nil => exact h
  | cons step tail ih => exact ih (step_accounted step h)

theorem step_responsible {s t : State} (step : Step s t)
    (h : RelationChain.Responsible s.productive) : RelationChain.Responsible t.productive := by
  cases step with
  | productive next notRequested checked => exact RelationChain.step_responsible checked h
  | request => exact h
  | stopPoll work quantum done requested running positive bounded valid =>
    cases done <;> simpa [stopPoll, RelationChain.stop, RelationChain.Responsible] using h
  | stopPause kind work quantum requested running positive bounded =>
    simpa [stopPause, stopPoll] using h
  | reclaim done => exact RelationChain.step_responsible (RelationChain.Step.reclaim s.productive done) h

theorem run_responsible {s t : State} (run : Run s t)
    (h : RelationChain.Responsible s.productive) : RelationChain.Responsible t.productive := by
  induction run with
  | nil => exact h
  | cons step tail ih => exact ih (step_responsible step h)

theorem step_budget {s t : State} (step : Step s t) :
    t.productive.budget = s.productive.budget := by
  cases step with
  | productive next notRequested checked => exact RelationChain.step_budget checked
  | request => rfl
  | stopPoll work quantum done requested running positive bounded valid => cases done <;> rfl
  | stopPause kind work quantum requested running positive bounded => rfl
  | reclaim done => exact RelationChain.step_budget (RelationChain.Step.reclaim s.productive done)

theorem run_budget {s t : State} (run : Run s t) :
    t.productive.budget = s.productive.budget := by
  induction run with
  | nil => rfl
  | cons step tail ih => exact ih.trans (step_budget step)

theorem chain_accounting (budget : Nat) (t : State) (run : Run (initial budget) t) :
    reported t = t.productive.childWork + t.productive.handoffWork + t.stopWork ∧
    t.productive.used ≤ budget := by
  have h := run_accounted run (RelationChain.initial_accounted budget)
  have sameBudget : t.productive.budget = budget := by simpa [initial] using run_budget run
  rcases h with ⟨report, sum, bounded⟩
  exact ⟨by simp only [reported]; omega, by omega⟩

theorem stop_poll_reporting (s : State) (work : Nat) (done : Bool) :
    reported (stopPoll s work done) = reported s + work ∧
    (stopPoll s work done).productive.used = s.productive.used ∧
    (stopPoll s work done).productive.owed = s.productive.owed := by
  cases done <;> simp [reported, stopPoll, RelationChain.stop, Nat.add_assoc]

theorem request_not_stopped (s : State) :
    (request s).productive.terminal = s.productive.terminal ∧
    reported (request s) = reported s ∧ (request s).productive.owed = s.productive.owed := by
  exact ⟨rfl, rfl, rfl⟩

theorem pending_cleanup_keeps (s : State) : reclaim s false = s := by
  simp [reclaim, RelationChain.pending_cleanup_keeps_responsibility]

theorem stopping_step_no_compute {s t : State} (step : Step s t) (h : s.requested = true) :
    t.requested = true ∧ t.productive.computes = s.productive.computes ∧
    t.productive.started = s.productive.started := by
  cases step with
  | productive next notRequested checked => simp_all
  | request => exact ⟨rfl, rfl, rfl⟩
  | stopPoll work quantum done requested running positive bounded valid =>
    cases done <;> simp [stopPoll, RelationChain.stop, h]
  | stopPause kind work quantum requested running positive bounded =>
    exact ⟨h, rfl, rfl⟩
  | reclaim done =>
    have clean := RelationChain.cleanup_does_not_compute s.productive done
    exact ⟨h, clean.2.1, clean.1⟩

theorem stopping_run_no_compute {s t : State} (run : Run s t) (h : s.requested = true) :
    t.requested = true ∧ t.productive.computes = s.productive.computes ∧
    t.productive.started = s.productive.started := by
  induction run with
  | nil => exact ⟨h, rfl, rfl⟩
  | cons step tail ih =>
    have first := stopping_step_no_compute step h
    have rest := ih first.1
    exact ⟨rest.1, rest.2.1.trans first.2.1, rest.2.2.trans first.2.2⟩

-- Independent numerical witness matching the existing accepted deltas [1,1,1].
def productiveOne : State :=
  { initial 1 with productive := RelationChain.childPoll (RelationChain.initial 1) 1 false }
def exhausted : State := request productiveOne
def pendingStop : State := stopPoll exhausted 1 false
def stopped : State := stopPoll pendingStop 1 true

theorem exhausted_witness : reported stopped = 3 ∧ stopped.productive.used = 1 ∧
    stopped.productive.budget = 1 ∧ stopped.productive.computes = 1 ∧
    stopped.productive.started = 1 ∧ stopped.productive.terminal = true ∧
    stopped.productive.owed = [0] := by decide

theorem exhausted_witness_run : Run (initial 1) stopped := by
  apply Run.cons (Step.productive (initial 1) _ rfl
    (RelationChain.Step.poll (RelationChain.initial 1) 1 1 false rfl (by decide) (by decide) (by decide)))
  apply Run.cons (Step.request productiveOne)
  apply Run.cons (Step.stopPoll exhausted 1 1 false rfl rfl (by decide) (by decide) (Or.inr (by decide)))
  apply Run.cons (Step.stopPoll pendingStop 1 1 true rfl rfl (by decide) (by decide) (Or.inl rfl))
  exact Run.nil stopped

-- A pause may report already-performed work, but neither kind confirms stop.
theorem pause_reporting (s : State) (work : Nat) :
    reported (stopPause s work) = reported s + work ∧
    (stopPause s work).productive = s.productive ∧
    (stopPause s work).requested = s.requested := by
  simp [reported, stopPause, stopPoll, Nat.add_assoc]

theorem zero_pause_identity (s : State) : stopPause s 0 = s := by
  simp [stopPause, stopPoll]

-- Both pause kinds precede the final stop observation; the numerical witness
-- matches the independent runtime deltas [1,0,1,0,0]. This is not liveness.
def pausedSettling : State := stopPause exhausted 1
def pausedStopped : State := stopPoll pausedSettling 0 true

theorem paused_witness_run : Run exhausted pausedStopped := by
  apply Run.cons (Step.stopPause exhausted Pause.waiting 0 1 rfl rfl (by decide) (by decide))
  rw [zero_pause_identity]
  apply Run.cons (Step.stopPause exhausted (Pause.settling 7) 1 1 rfl rfl (by decide) (by decide))
  apply Run.cons (Step.stopPause pausedSettling (Pause.settling 7) 0 1 rfl rfl (by decide) (by decide))
  rw [zero_pause_identity]
  apply Run.cons (Step.stopPoll pausedSettling 0 1 true rfl rfl (by decide) (by decide) (Or.inl rfl))
  exact Run.nil pausedStopped

theorem paused_witness_accounting : reported pausedStopped = 2 ∧
    pausedStopped.productive.used = 1 ∧ pausedStopped.productive.computes = 1 ∧
    pausedStopped.productive.started = 1 ∧ pausedStopped.productive.terminal = true ∧
    pausedStopped.productive.owed = [0] := by decide

end RelationChainStop
