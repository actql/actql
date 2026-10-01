// Keep ordinary TAP diagnostics, then retain Node's structured per-file counts.
// The final process summary can count an empty selected file as one pass.
import {tap} from 'node:test/reporters';

export default async function* reporter(source) {
  const summaries = [];
  async function* observe() {
    for await (const event of source) {
      if (event.type === 'test:summary') summaries.push(event.data);
      yield event;
    }
  }
  yield* tap(observe());
  for (const summary of summaries) {
    yield `ACTQL_TEST_SUMMARY ${JSON.stringify(summary)}\n`;
  }
}
