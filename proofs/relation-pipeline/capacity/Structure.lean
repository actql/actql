/- Filled-container bounds, not allocator bytes. Runtime representations and
   the existing parent's 256-byte allowance remain undischarged premises. -/
namespace RelationStructure

-- The independent first-occurrence specification supplies the cardinality
-- premise. Equality correspondence to the production comparator is tested,
-- not established by this list-model proof.
def firstOccurrenceRows {Row : Type} [DecidableEq Row]
    (seen : List Row) : List Row → List Row
  | [] => []
  | row :: rest => if row ∈ seen then firstOccurrenceRows seen rest
      else row :: firstOccurrenceRows (row :: seen) rest

theorem first_occurrence_count_bound {Row : Type} [DecidableEq Row]
    (rows seen : List Row) :
    (firstOccurrenceRows seen rows).length ≤ rows.length := by
  induction rows generalizing seen with
  | nil => simp [firstOccurrenceRows]
  | cons row rest ih =>
    simp only [firstOccurrenceRows, List.length_cons]
    split
    · exact Nat.le_trans (ih seen) (Nat.le_succ _)
    · simpa only [List.length_cons] using
        Nat.succ_le_succ (ih (row :: seen))

structure Counts where
  metadata : Nat
  index : Nat
  keep : Nat
  terms : Nat
  outputRows : Nat
  outputCells : Nat
  roots : Nat
  temporary : Nat
  measureFrames : Nat

def total (c : Counts) : Nat := c.metadata + c.index + c.keep + c.terms +
  c.outputRows + c.outputCells + c.roots + c.temporary + c.measureFrames
def bounded (n w : Nat) (c : Counts) : Prop :=
  c.metadata ≤ 4*w ∧ c.index ≤ 2*n ∧ c.keep ≤ n ∧ c.terms ≤ w ∧
  c.outputRows ≤ n ∧ c.outputCells ≤ n*w ∧ c.roots ≤ n ∧ c.temporary ≤ 6*w ∧ c.measureFrames ≤ 5
def childBound (n w : Nat) : Nat := n*w + 5*n + 11*w + 5

theorem distinct_structural_bound (n w : Nat) (c : Counts) (h : bounded n w c) :
    total c ≤ childBound n w := by
  unfold bounded at h
  unfold total childBound
  omega

theorem output_cells_bound (n w u : Nat) (rows : u ≤ n) : u*w ≤ n*w :=
  Nat.mul_le_mul_right w rows

-- An IEEE754 Number contains 64 payload bits. This definition does not say
-- that an admitted-value wrapper or JS Number occupies eight allocation bytes.
theorem numeric_content_octets_bound (n w u : Nat) (rows : u ≤ n) :
    8*(u*w) ≤ 8*(n*w) :=
  Nat.mul_le_mul_left 8 (output_cells_bound n w u rows)

structure Child where
  rows : Nat
  width : Nat
  state : Counts

def finiteBound : List Child → Nat
  | [] => 0
  | c::rest => childBound c.rows c.width + finiteBound rest
def finiteTotal : List Child → Nat
  | [] => 0
  | c::rest => total c.state + finiteTotal rest

theorem serial_bounds (children : List Child)
    (bounds : ∀ c ∈ children, bounded c.rows c.width c.state) :
    finiteTotal children ≤ finiteBound children := by
  induction children with
  | nil => simp [finiteTotal, finiteBound]
  | cons c rest ih =>
    have hc := distinct_structural_bound c.rows c.width c.state (bounds c (by simp))
    have tail := ih (by intro x member; exact bounds x (by simp [member]))
    simp only [finiteTotal, finiteBound]
    omega

-- Structural proofs never invent a runtime byte conversion. Discharging this
-- implication requires an independent representation/storage upper bound.
theorem conditional_bytes (actual elements bytesPerEntry management : Nat)
    (representation : actual ≤ elements*bytesPerEntry + management)
    (upper : Nat) (countBound : elements ≤ upper) :
    actual ≤ upper*bytesPerEntry + management := by
  have scaled := Nat.mul_le_mul_right bytesPerEntry countBound
  omega

-- Reuse the allocation-union model. The size function can count filled entries
-- instead of bytes; a byte conversion still needs conditional_bytes' premise.
theorem shared_structural_chain (r : RelationCapacity.Registry)
    (children : List RelationCapacity.Child)
    (bounds : ∀ c ∈ children,
      RelationCapacity.charge r.ids r.size c.live ≤ c.retained + c.execution) :
    RelationCapacity.charge r.ids r.size (RelationCapacity.childrenLive children) ≤
      RelationCapacity.childCapacity children :=
  RelationCapacity.children_bound r.ids r.size children bounds

theorem output_holder_keeps_charge (r : RelationCapacity.Registry)
    (executor output : Nat → Bool)
    (outputOwns : ∀ id ∈ r.ids, executor id = true → output id = true) :
    RelationCapacity.charge r.ids r.size (fun id => executor id || output id) =
      RelationCapacity.charge r.ids r.size output := by
  have upper := RelationCapacity.charge_mono r.ids r.size
    (fun id => executor id || output id) output (by
      intro id member yes
      cases he : executor id with
      | false => simpa [he] using yes
      | true => exact outputOwns id member he)
  have lower := RelationCapacity.charge_mono r.ids r.size output
    (fun id => executor id || output id) (by
      intro id _ yes
      simp [yes])
  omega

end RelationStructure
