// Prepared controls from the already adopted UTC artifact and Calendar examples.
// These require an explicitly selected artifact on the existing Host owner;
// they do not enable a capability, install TZDB or implement Calendar execution.
export const calendarSourceArtifact = '{"conversion_law":"actql-calendar-boundaries/0.1","coverage_end_ms":253402300800000,"coverage_start_ms":-62135596800000,"tzdb_version":"test-fixture","version":"actql-tzdb-table/0.1","zones":{"UTC":{"initial_offset_seconds":0,"transitions":[]}}}\n';
export const calendarSourceSelection = {
  version: 'actql-calendar-selection/0.1', tzdb_version: 'test-fixture',
  conversion_law: 'actql-calendar-boundaries/0.1',
  table_bytes_cid: 'sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca',
};
export const calendarSourceArtifactLimits = {
  max_bytes: 1000, max_nodes: 100, max_depth: 8, max_zones: 1, max_transitions: 0,
};
const start = '2000-01-01T00:00:00.000Z', end = '2000-01-03T00:00:00.000Z';
const timestamp = {type: 'timestamp', nullable: false};
const seriesRows = [{start, end: '2000-01-02T00:00:00.000Z'},
  {start: '2000-01-02T00:00:00.000Z', end}];
const seriesColumns = [{name: 'start', contract: timestamp}, {name: 'end', contract: timestamp}];
const month = {start, end: '2000-02-01T00:00:00.000Z'};
const bucketColumns = [...seriesColumns, {name: 'month', contract: {
  type: 'object', nullable: false, additional_properties: false,
  fields: {start: timestamp, end: timestamp},
}}];
const generator = `calendar_series(start:'${start}',end:'${end}',unit:'day',timezone:'UTC')`;
function control(bucket) {
  const fields = bucket ? ['start', 'end', 'month'] : ['start', 'end'];
  const from = bucket ? 'bucketed' : 'days';
  return {version: 'actql/0.1', id: 'fixture.calendar_source', stages: [{id: 'main', inputs: {}, steps: [
    {calendar_series: {start, end, unit: 'day', timezone: 'UTC'}, as: 'days'},
    ...(bucket ? [{calendar_bucket: {time: 'start', into: 'month', unit: 'month', timezone: 'UTC'}, as: 'bucketed'}] : []),
    {from, sort: [{field: 'start', dir: 'asc', nulls: 'first'}]},
    {select: fields, as: 'out'},
  ], results: {rows: {from: 'out', fields}}}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
}
export const calendarSourceSuccesses = [false, true].flatMap(bucket => {
  const text = `WITH days AS (${generator}) ` + (bucket
    ? "FROM days AS d |> calendar_bucket(time:d.start,unit:'month',timezone:'UTC',into:month) |> SELECT start,`end`,month |> ORDER BY start"
    : 'SELECT start,`end` FROM days ORDER BY start');
  const rows = bucket ? seriesRows.map(row => ({...row, month})) : seriesRows;
  const columns = bucket ? bucketColumns : seriesColumns;
  return ['json', 'sql', 'aql-text'].map(format => ({
    name: `calendar-${bucket ? 'month-bucket' : 'day-series'}-${format}`, format,
    text: format === 'json' ? JSON.stringify(control(bucket)) : text,
    results: {answer: {rows, columns}}, sourceReadCount: 0, sourceReadSessionCount: 0,
  }));
});

// The existing Calendar unit selector is a non-null string in both the machine
// operation and text signature. Preserve the valid inputs and change only that
// authored selector for independent pre-admission refusal controls.
const nullUnitProgram = control(false);
nullUnitProgram.stages[0].steps[0].calendar_series.unit = null;
const nullUnitText = `WITH days AS (calendar_series(start:'${start}',end:'${end}',unit:NULL,timezone:'UTC')) ` +
  'SELECT start,`end` FROM days ORDER BY start';
export const calendarSourceRefusals = ['json', 'sql', 'aql-text'].map(format => ({
  name: `calendar-null-unit-${format}`, format,
  text: format === 'json' ? JSON.stringify(nullUnitProgram) : nullUnitText,
  expectedCode: 'ClientProgramInvalidInput',
}));
