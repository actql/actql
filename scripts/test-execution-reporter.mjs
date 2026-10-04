// Keep ordinary TAP diagnostics, then retain Node's structured cases and counts.
// The final process summary can count an empty selected file as one pass.
import {tap} from 'node:test/reporters';

export default async function* reporter(source) {
  const summaries = [];
  const cases = [];
  const diagnostics = [];
  async function* observe() {
    for await (const event of source) {
      if (event.type === 'test:summary') summaries.push(event.data);
      if (event.type === 'test:diagnostic' && event.data.file !== undefined) {
        diagnostics.push(event.data);
      }
      if (event.type === 'test:pass' || event.type === 'test:fail') {
        const {name, file, skip, todo, details} = event.data;
        const error = details?.error;
        const cause = error?.cause ?? error;
        cases.push({name, file, passed: event.type === 'test:pass',
          skipped: Boolean(skip), todo: Boolean(todo),
          failureType: error?.failureType, errorCode: cause?.code,
          errorMessage: cause?.message, operator: cause?.operator});
      }
      yield event;
    }
  }
  yield* tap(observe());
  for (const entry of cases) {
    yield `ACTQL_TEST_CASE ${JSON.stringify(entry)}\n`;
  }
  for (const entry of diagnostics) {
    yield `ACTQL_TEST_DIAGNOSTIC ${JSON.stringify(entry)}\n`;
  }
  for (const summary of summaries) {
    yield `ACTQL_TEST_SUMMARY ${JSON.stringify(summary)}\n`;
  }
}
