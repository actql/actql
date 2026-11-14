// Literal branches and duplicate counts are authored independently of product
// output. SQL Relations are unordered; every duplicate and column is retained.
const counts = new Map([[10, [4, 3, 3]], [11, [4, 4, 3]], [24, [8, 8, 8]],
  [25, [9, 8, 8]], [40, [14, 13, 13]]]);
export const unionBudgetCases = [...counts].flatMap(([branches, duplicates]) => {
  const union = Array.from({length: branches}, (_, index) =>
    `SELECT ${index % 3} AS n`).join(' UNION ALL ');
  const expected = duplicates.flatMap((count, n) =>
    Array.from({length: count}, () => ({n})));
  return [false, true].map(cte => ({name: `${cte ? 'cte' : 'direct'}-${branches}`,
    branches, cte, format: 'sql', text: cte
      ? `WITH all_rows AS (${union}) SELECT n FROM all_rows` : union,
    expected, columns: [{name: 'n', contract: {type: 'number', nullable: false}}]}));
});
