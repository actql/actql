// Conformance only. No product entry imports this fixture-backed driver.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { runFixedCompute, matchesFixedCompute, releaseFixedCompute } from '../fixed-compute.mjs';

const hash = value => `sha256:${createHash('sha256').update(JSON.stringify(value)).digest('hex')}`;

export async function exerciseOwnedFixedTransport(moon, producer, output, contracts, limits, expectedIds) {
  const create = () => moon.ownedFixedCreate(producer, output, ...contracts);
  const accepted = value => { if (!value) throw new Error('OwnedFixedReceiverRejected'); };
  async function receive(maxRows, signal, onChunk) {
    const fixed = create();
    let result;
    let begun = false;
    let parameterReads = 0;
    const port = Object.freeze({
      rowCount: () => moon.ownedFixedRowCount(fixed),
      columnCount: () => moon.ownedFixedColumnCount(fixed),
      createSql: () => moon.ownedFixedSql(fixed, 0),
      insertSql: () => moon.ownedFixedSql(fixed, 1),
      parameter(row, column) {
        parameterReads++;
        return JSON.parse(moon.ownedFixedParameter(fixed, row, column, false));
      },
      querySql: () => moon.ownedFixedSql(fixed, 2),
      queryParameters: () => [JSON.parse(moon.ownedFixedParameter(fixed, 0, 0, true))],
    });
    const begin = fields => {
      accepted(moon.ownedFixedBegin(fixed, JSON.stringify(fields), maxRows));
      begun = true;
    };
    const consume = chunk => {
      assert.equal(matchesFixedCompute(result, port, consume), false);
      if (!begun) begin(chunk.fields);
      accepted(moon.ownedFixedAccept(fixed, chunk.rowCount, JSON.stringify(chunk.columns)));
      assert.equal(moon.ownedFixedRows(fixed), 'null'); // not sealed during execution
      onChunk?.();
    };
    try {
      result = await runFixedCompute(port, limits, { maxRows: 100, maxCells: 1000 }, consume, signal);
      assert.equal(matchesFixedCompute(result, port, consume), true);
      assert.equal(matchesFixedCompute({ ...result }, port, consume), false);
      assert.equal(matchesFixedCompute(result, { ...port }, consume), false);
      if (!begun) begin(result.value.fields);
      accepted(moon.ownedFixedFinish(fixed));
      assert.equal(parameterReads, result.value.importedCells);
      assert.equal(result.usage.statements, result.value.importedRows + 2);
      // These are provisional, admitted rows, NOT a successful Compute output.
      assert.deepEqual(JSON.parse(moon.ownedFixedRows(fixed)), expectedIds);
      assert.equal(moon.ownedFixedLocalCid(fixed), hash(expectedIds.map(id => ({ id }))));
      return { fixed, close() {
        releaseFixedCompute(result);
        moon.ownedFixedAbort(fixed);
        assert.equal(matchesFixedCompute(result, port, consume), false);
        assert.equal(moon.ownedFixedRows(fixed), 'null');
      } };
    } catch (error) {
      if (result !== undefined) releaseFixedCompute(result);
      moon.ownedFixedAbort(fixed);
      assert.equal(moon.ownedFixedRows(fixed), 'null');
      throw error;
    }
  }
  if (expectedIds.length) {
    for (const maxRows of [0, expectedIds.length - 1]) {
      await assert.rejects(receive(maxRows), /OwnedFixedReceiverRejected/);
    }
    const cancel = new AbortController();
    await assert.rejects(receive(100, cancel.signal, () => cancel.abort()));
  }
  const first = await receive(expectedIds.length);
  const second = await receive(100);
  first.close();
  assert.deepEqual(JSON.parse(moon.ownedFixedRows(second.fixed)), expectedIds);
  second.close();
  const unstarted = create();
  return () => {
    assert.equal(moon.ownedFixedLocalCid(unstarted), 'null');
    assert.equal(moon.ownedFixedParameter(unstarted, 0, 0, false), 'null');
    assert.equal(moon.ownedFixedBegin(unstarted, JSON.stringify([{ name: 'id', type: { id: 'DOUBLE' } }]), 100), false);
  };
}
