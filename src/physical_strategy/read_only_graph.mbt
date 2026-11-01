// Read-only projections retain the exact checked owner; no mutable collection escapes.

///|
pub fn CheckedDAG::program_value(self : CheckedDAG) -> @checked.CheckedProgram {
  self.program
}

///|
pub fn CheckedDAG::source_free_root_value(self : CheckedDAG) -> Bool {
  self.source_free_root
}

///|
pub fn CheckedDAG::captured_prefix_value(self : CheckedDAG) -> Int {
  self.captured_prefix
}

///|
pub fn CheckedDAG::original_tasks_count(self : CheckedDAG) -> Int {
  self.original_tasks.length()
}

///|
pub fn CheckedDAG::original_tasks_at(self : CheckedDAG, index : Int) -> Int? {
  self.original_tasks.get(index)
}

///|
pub fn CheckedDAG::original_tasks_iter(self : CheckedDAG) -> Iter[Int] {
  self.original_tasks.iter()
}

///|
pub fn CheckedDAG::original_task_count_value(self : CheckedDAG) -> Int {
  self.original_task_count
}

///|
pub fn CheckedDAG::owners_count(self : CheckedDAG) -> Int {
  self.owners.length()
}

///|
pub fn CheckedDAG::owners_at(
  self : CheckedDAG,
  index : Int,
) -> @lower.BoundPrepared? {
  self.owners.get(index)
}

///|
pub fn CheckedDAG::owners_iter(self : CheckedDAG) -> Iter[@lower.BoundPrepared] {
  self.owners.iter()
}

///|
pub fn CheckedDAG::stage_tasks_count(self : CheckedDAG) -> Int {
  self.stage_tasks.length()
}

///|
pub fn CheckedDAG::stage_tasks_iter_at(
  self : CheckedDAG,
  index : Int,
) -> Iter[Int]? {
  checked_graph_rows_iter_at(self.stage_tasks, index)
}

///|
pub fn CheckedDAG::targets_count(self : CheckedDAG) -> Int {
  self.targets.length()
}

///|
pub fn CheckedDAG::targets_at(
  self : CheckedDAG,
  index : Int,
) -> @pipeline.Target?? {
  self.targets.get(index)
}

///|
pub fn CheckedDAG::targets_iter(self : CheckedDAG) -> Iter[@pipeline.Target?] {
  self.targets.iter()
}

///|
pub fn CheckedDAG::input_counts_count(self : CheckedDAG) -> Int {
  self.input_counts.length()
}

///|
pub fn CheckedDAG::input_counts_at(self : CheckedDAG, index : Int) -> Int? {
  self.input_counts.get(index)
}

///|
pub fn CheckedDAG::input_counts_iter(self : CheckedDAG) -> Iter[Int] {
  self.input_counts.iter()
}

///|
pub fn CheckedDAG::selected_steps_count(self : CheckedDAG) -> Int {
  self.selected_steps.length()
}

///|
pub fn CheckedDAG::selected_steps_at(self : CheckedDAG, index : Int) -> Int?? {
  self.selected_steps.get(index)
}

///|
pub fn CheckedDAG::selected_steps_iter(self : CheckedDAG) -> Iter[Int?] {
  self.selected_steps.iter()
}

///|
pub fn CheckedDAG::prefix_ends_count(self : CheckedDAG) -> Int {
  self.prefix_ends.length()
}

///|
pub fn CheckedDAG::prefix_ends_at(self : CheckedDAG, index : Int) -> Int?? {
  self.prefix_ends.get(index)
}

///|
pub fn CheckedDAG::prefix_ends_iter(self : CheckedDAG) -> Iter[Int?] {
  self.prefix_ends.iter()
}

///|
pub fn CheckedDAG::data_count(self : CheckedDAG) -> Int {
  self.data.length()
}

///|
pub fn CheckedDAG::data_at(self : CheckedDAG, index : Int) -> DataEdge? {
  self.data.get(index)
}

///|
pub fn CheckedDAG::data_iter(self : CheckedDAG) -> Iter[DataEdge] {
  self.data.iter()
}

///|
pub fn CheckedDAG::supplied_slots_count(self : CheckedDAG) -> Int {
  self.supplied_slots.length()
}

///|
pub fn CheckedDAG::supplied_slots_at(
  self : CheckedDAG,
  index : Int,
) -> LocalInputSlot? {
  self.supplied_slots.get(index)
}

///|
pub fn CheckedDAG::supplied_slots_iter(
  self : CheckedDAG,
) -> Iter[LocalInputSlot] {
  self.supplied_slots.iter()
}

///|
pub fn CheckedDAG::control_count(self : CheckedDAG) -> Int {
  self.control.length()
}

///|
pub fn CheckedDAG::control_at(self : CheckedDAG, index : Int) -> ControlEdge? {
  self.control.get(index)
}

///|
pub fn CheckedDAG::control_iter(self : CheckedDAG) -> Iter[ControlEdge] {
  self.control.iter()
}

///|
pub fn CheckedDAG::operations_count(self : CheckedDAG) -> Int {
  self.operations.length()
}

///|
pub fn CheckedDAG::operations_iter_at(
  self : CheckedDAG,
  index : Int,
) -> Iter[TaskOperationRequirement]? {
  checked_graph_rows_iter_at(self.operations, index)
}

///|
pub fn CheckedDAG::numeric_count(self : CheckedDAG) -> Int {
  self.numeric.length()
}

///|
pub fn CheckedDAG::numeric_iter_at(
  self : CheckedDAG,
  index : Int,
) -> Iter[TaskNumericObservation]? {
  checked_graph_rows_iter_at(self.numeric, index)
}

///|
pub fn CheckedDAG::results_count(self : CheckedDAG) -> Int {
  self.results.length()
}

///|
pub fn CheckedDAG::results_at(
  self : CheckedDAG,
  index : Int,
) -> CheckedResultOccurrence? {
  self.results.get(index)
}

///|
pub fn CheckedDAG::results_iter(
  self : CheckedDAG,
) -> Iter[CheckedResultOccurrence] {
  self.results.iter()
}

///|
pub fn CheckedEffectComputationDAG::candidate_value(
  self : CheckedEffectComputationDAG,
) -> @checked.EffectProgramStaticCandidate {
  self.candidate
}

///|
pub fn CheckedEffectComputationDAG::graph_value(
  self : CheckedEffectComputationDAG,
) -> CheckedDAG {
  self.graph
}

///|
pub fn CheckedEffectComputationDAG::sources_count(
  self : CheckedEffectComputationDAG,
) -> Int {
  self.sources.length()
}

///|
pub fn CheckedEffectComputationDAG::sources_at(
  self : CheckedEffectComputationDAG,
  index : Int,
) -> CheckedEffectSourcePort?? {
  self.sources.get(index)
}

///|
pub fn CheckedEffectComputationDAG::sources_iter(
  self : CheckedEffectComputationDAG,
) -> Iter[CheckedEffectSourcePort?] {
  self.sources.iter()
}

///|
pub fn CheckedEffectComputationDAG::table_sources_count(
  self : CheckedEffectComputationDAG,
) -> Int {
  self.table_sources.length()
}

///|
pub fn CheckedEffectComputationDAG::table_sources_at(
  self : CheckedEffectComputationDAG,
  index : Int,
) -> CheckedEffectTableInputPort?? {
  self.table_sources.get(index)
}

///|
pub fn CheckedEffectComputationDAG::table_sources_iter(
  self : CheckedEffectComputationDAG,
) -> Iter[CheckedEffectTableInputPort?] {
  self.table_sources.iter()
}

///|
pub fn CheckedDAG::stage_tasks_count_at(self : CheckedDAG, index : Int) -> Int? {
  checked_graph_rows_count_at(self.stage_tasks, index)
}

///|
fn[T] checked_graph_rows_iter_at(
  rows : Array[Array[T]],
  index : Int,
) -> Iter[T]? {
  rows.get(index).map(row => row.iter())
}

///|
fn[T] checked_graph_rows_count_at(rows : Array[Array[T]], index : Int) -> Int? {
  rows.get(index).map(row => row.length())
}
