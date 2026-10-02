/- Restricted table-slot structure of the pinned builtin Map. Runtime bytes,
   allocator identity and implementation-wide refinement are separate. -/
namespace MapBacking

structure State where
  slots : Nat
  entries : Nat

def empty : State := ⟨8, 0⟩
def clear (s : State) : State := { s with entries := 0 }
def insert (s : State) : State :=
  if s.entries ≥ s.slots * 13 / 16 then ⟨2 * s.slots, s.entries + 1⟩
  else { s with entries := s.entries + 1 }
def invariant (maximum : Nat) (s : State) : Prop :=
  s.slots = 8 ∧ s.entries ≤ maximum

inductive Reach (maximum : Nat) : State → Prop where
  | start : Reach maximum empty
  | insert (s) : Reach maximum s → s.entries + 1 ≤ maximum → Reach maximum (insert s)
  | update (s) : Reach maximum s → Reach maximum s
  | clear (s) : Reach maximum s → Reach maximum (clear s)

theorem no_growth (maximum : Nat) (s : State)
    (bound : maximum ≤ 6) (held : invariant maximum s)
    (admitted : s.entries + 1 ≤ maximum) : invariant maximum (insert s) := by
  rcases held with ⟨slots, entries⟩
  have small : ¬ s.entries ≥ s.slots * 13 / 16 := by
    rw [slots]
    change ¬ s.entries ≥ 6
    omega
  simp only [insert, if_neg small, invariant]
  exact ⟨slots, admitted⟩

theorem clear_keeps_slots (s : State) : (clear s).slots = s.slots := rfl

-- The finite trace is arbitrary; explicit preconditions keep new-key insertion
-- in the admitted domain. Updating a key does not allocate another Entry.
theorem finite_trace (maximum : Nat) (s : State) (bound : maximum ≤ 6)
    (trace : Reach maximum s) : invariant maximum s := by
  induction trace with
  | start => simp [invariant, empty]
  | insert s prior admitted ih => exact no_growth maximum s bound ih admitted
  | update s prior ih => exact ih
  | clear s prior ih => exact ⟨ih.1, Nat.zero_le _⟩

-- Four independent current tables; construction before replacing the snapshot
-- can keep one additional old/new pair live. No GC/reclamation claim follows.
theorem replacement_overlap : 4 * empty.slots + empty.slots = 40 := rfl

end MapBacking
