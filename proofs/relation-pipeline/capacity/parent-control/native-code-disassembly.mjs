import assert from 'node:assert/strict';

export function nativeFunctionEntries(text) {
  return text.split('\n').map(line => line.match(/^([0-9a-f]+)\s+[tT]\s+(\S+)$/))
    .filter(match => match && !match[2].startsWith('.') && !match[2].includes('$bb'));
}

// Scheduling only: never shorten a selected function to meet this batch size.
// A larger function retains its complete old range in a separate invocation.
const batchSpan = 128n * 1024n;
export function nativeFunctionRanges(entries, names) {
  assert(names.length > 0, 'Missing Native function selection');
  assert.equal(new Set(names).size, names.length, 'Duplicate Native function selection');
  const addresses = entries.map(entry => BigInt(`0x${entry[1]}`));
  assert(addresses.every((address, index) => index === 0 || address >= addresses[index - 1]),
    'Unordered Native symbols');
  const ranges = names.map(name => {
    const matches = entries.filter(entry => entry[2] === name);
    assert.equal(matches.length, 1, 'Missing or duplicate Native function range');
    const start = BigInt(`0x${matches[0][1]}`), end = addresses.find(address => address > start);
    assert(end !== undefined, 'Missing Native function range end');
    return {name, start, end};
  });
  const sorted = [...ranges].sort((a, b) => a.start < b.start ? -1 : a.start > b.start ? 1 : 0);
  for (let index = 1; index < sorted.length; index++)
    assert(sorted[index].start >= sorted[index - 1].end, 'Overlapping selected Native function ranges');
  return ranges;
}

export function extractNativeRanges(text, ranges) {
  const marker = 'Disassembly of section .text:';
  assert.equal(text.split(marker).length, 2, 'Missing or repeated Native text disassembly');
  const body = text.slice(text.indexOf(marker) + marker.length);
  const sorted = [...ranges].sort((a, b) => a.start < b.start ? -1 : a.start > b.start ? 1 : 0);
  const bodies = new Map(sorted.map(range => [range.name, []]));
  assert.equal(bodies.size, sorted.length, 'Duplicate extracted Native function');
  for (let index = 0; index < sorted.length; index++) {
    assert(sorted[index].start < sorted[index].end, 'Empty selected Native function range');
    if (index > 0) assert(sorted[index].start >= sorted[index - 1].end, 'Overlapping extracted Native ranges');
  }
  let address, index = 0;
  for (const line of body.split('\n')) {
    const match = line.match(/^\s*([0-9a-f]+)(?: <[^>]+>)?:/);
    if (match) {
      const next = BigInt(`0x${match[1]}`);
      assert(address === undefined || next >= address, 'Regressive Native disassembly addresses');
      address = next;
      while (index < sorted.length && address >= sorted[index].end) index++;
    }
    else assert(line.trim() === '', 'Unaddressed Native disassembly output');
    if (index < sorted.length && address !== undefined && address >= sorted[index].start)
      bodies.get(sorted[index].name).push(line);
  }
  const selected = new Map();
  for (const range of ranges) {
    const lines = bodies.get(range.name);
    while (lines.at(-1)?.trim() === '') lines.pop();
    const opening = lines[0]?.match(/^([0-9a-f]+) <([^>]+)>:$/);
    assert(opening && BigInt(`0x${opening[1]}`) === range.start && opening[2] === range.name,
      'Selected Native function heading differs from symbols');
    assert(lines.some(line => /^\s*[0-9a-f]+:\s+\S/.test(line)), 'Empty Native function disassembly');
    assert(!selected.has(range.name), 'Duplicate extracted Native function');
    // Match the existing per-function GNU output exactly, including its
    // header and single final newline. Keep interior labels and relocations.
    selected.set(range.name, `${marker}\n\n${lines.join('\n')}\n`);
  }
  return selected;
}

export function disassembleNativeRanges(run, tool, file, entries, names, relocations) {
  const ranges = nativeFunctionRanges(entries, names);
  const sorted = [...ranges].sort((a, b) => a.start < b.start ? -1 : 1), groups = [];
  for (const range of sorted) {
    const prior = groups.at(-1);
    if (!prior || range.end - prior[0].start > batchSpan) groups.push([range]);
    else prior.push(range);
  }
  const selected = new Map();
  for (const group of groups) {
    const text = run(tool, ['-d', '-Mintel', '--section=.text', '--no-show-raw-insn', ...(relocations ? ['-r'] : []),
      `--start-address=0x${group[0].start.toString(16)}`, `--stop-address=0x${group.at(-1).end.toString(16)}`, file]);
    for (const [name, body] of extractNativeRanges(text, group)) selected.set(name, body);
  }
  return ranges.map(range => selected.get(range.name)).join('\n');
}
