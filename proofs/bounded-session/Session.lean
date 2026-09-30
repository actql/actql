import Lean

/- Contract model, not a translation of the MoonBit implementation. A natural
   counter denotes a previously accepted, nonnegative, representable counter.
   Kernel and callback premises are explicit; no physical liveness is assumed. -/
namespace BoundedSession

structure Counters where
  progress : Nat
  work : Nat
  deriving Repr, DecidableEq

def Admissible (before after : Counters) (quantum limit : Nat) : Prop :=
  0 < quantum ∧ before.progress ≤ after.progress ∧ before.work ≤ after.work ∧
  after.work - before.work ≤ quantum ∧ after.progress ≤ limit ∧ after.work ≤ limit

def delta (before after : Counters) : Counters :=
  ⟨after.progress - before.progress, after.work - before.work⟩

theorem delta_reconstructs (before after : Counters) (quantum limit : Nat)
    (h : Admissible before after quantum limit) :
    before.progress + (delta before after).progress = after.progress ∧
    before.work + (delta before after).work = after.work := by
  exact ⟨Nat.add_sub_of_le h.2.1, Nat.add_sub_of_le h.2.2.1⟩

theorem delta_bounded (before after : Counters) (quantum limit : Nat)
    (h : Admissible before after quantum limit) :
    (delta before after).work ≤ quantum ∧ after.work ≤ limit := by
  exact ⟨h.2.2.2.1, h.2.2.2.2.2⟩

def MonotoneReports (initial : Nat) : List Nat → Prop
  | [] => True
  | next :: rest => initial ≤ next ∧ MonotoneReports next rest

def charges (initial : Nat) : List Nat → Nat
  | [] => 0
  | next :: rest => next - initial + charges next rest

def finalWork (initial : Nat) : List Nat → Nat
  | [] => initial
  | next :: rest => finalWork next rest

-- Arbitrary finite poll sequences, rather than one theorem per operation/path.
theorem charges_telescope (reports : List Nat) (initial : Nat)
    (h : MonotoneReports initial reports) :
    initial + charges initial reports = finalWork initial reports := by
  induction reports generalizing initial with
  | nil => simp [charges, finalWork]
  | cons next rest ih =>
    have tail := ih next h.2
    simp only [charges, finalWork]
    have head := h.1
    omega

structure Token where
  owner : Nat
  ordinal : Nat
  deriving DecidableEq

def MayResume (current supplied : Token) (terminal running : Bool) (quantum : Nat) :=
  current = supplied ∧ terminal = false ∧ running = false ∧ 0 < quantum

def successor (token : Token) : Token := ⟨token.owner, token.ordinal + 1⟩

theorem consumed_token_rejected (token : Token) (terminal running : Bool) (q : Nat) :
    ¬ MayResume (successor token) token terminal running q := by
  intro h
  have impossible := congrArg Token.ordinal h.1
  exact Nat.succ_ne_self token.ordinal impossible

theorem foreign_owner_rejected (current supplied : Token) (h : current.owner ≠ supplied.owner)
    (terminal running : Bool) (q : Nat) :
    ¬ MayResume current supplied terminal running q := by
  intro allowed
  exact h (congrArg Token.owner allowed.1)

theorem terminal_cannot_resume (current supplied : Token) (running : Bool) (q : Nat) :
    ¬ MayResume current supplied true running q := by
  simp [MayResume]

-- Cleanup of an unaccepted result must precede kernel-state reclamation.
-- Flags describe obligations, independently of the implementation's fields.
structure Obligations where
  result : Bool
  state : Bool
  deriving DecidableEq

def complete (s : Obligations) : Bool := !s.result && !s.state

def reclaim (s : Obligations) (resultReady stateReady : Bool) : Obligations :=
  let resultPending := s.result && !resultReady
  ⟨resultPending, s.state && (resultPending || !stateReady)⟩

theorem pending_result_keeps_state (s : Obligations) (stateReady : Bool)
    (h : s.result = true) : (reclaim s false stateReady).state = s.state := by
  simp [reclaim, h]

theorem reclaim_preserves_completed (s : Obligations) (rr sr : Bool)
    (h : complete s = true) : reclaim s rr sr = s := by
  cases s with
  | mk r k => cases r <;> cases k <;> simp_all [complete, reclaim]

theorem changed_is_not_completion :
    reclaim ⟨true, true⟩ true false ≠ ⟨true, true⟩ ∧
    complete (reclaim ⟨true, true⟩ true false) = false := by
  decide

inductive Kind | continuing | completed | failed | stopped
  deriving DecidableEq

structure Adapter where
  counters : Counters
  terminal : Bool
  reclaimed : Bool
  deriving DecidableEq

def observed (s : Adapter) (after : Counters) (kind : Kind) : Adapter :=
  ⟨after, kind != .continuing, s.reclaimed⟩

def cleanup (s : Adapter) (callbackComplete : Bool) : Adapter :=
  { s with reclaimed := s.reclaimed || (s.terminal && callbackComplete) }

theorem terminal_poll_closes (s : Adapter) (after : Counters) (kind : Kind)
    (h : kind ≠ .continuing) : (observed s after kind).terminal = true := by
  simp [observed, h]

theorem cleanup_preserves_outcome (s : Adapter) (done : Bool) :
    (cleanup s done).counters = s.counters ∧ (cleanup s done).terminal = s.terminal := by
  exact ⟨rfl, rfl⟩

theorem running_cannot_reclaim (s : Adapter) (done : Bool) (h : s.terminal = false) :
    (cleanup s done).reclaimed = s.reclaimed := by
  simp [cleanup, h]

theorem cleanup_completed_stays_completed (s : Adapter) (done : Bool)
    (h : s.reclaimed = true) : (cleanup s done).reclaimed = true := by
  simp [cleanup, h]

-- The operation supplies the admissible report sequence. Its name and semantic
-- output do not occur in the accounting law; they remain separate obligations.
theorem provider_accounting_instance (reports : List Nat)
    (kernelReports : MonotoneReports 0 reports) :
    charges 0 reports = finalWork 0 reports := by
  simpa using charges_telescope reports 0 kernelReports

end BoundedSession
