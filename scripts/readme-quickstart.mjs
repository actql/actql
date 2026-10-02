// Read the exact documented files/commands; do not maintain a second example.
export function readmeQuickstart(markdown) {
  const section = markdown.split('## Quickstart\n')[1]?.split('\n## ')[0];
  if (!section) throw new Error('MissingReadmeQuickstart');
  const blocks = [...section.matchAll(/```(\w+)\n([\s\S]*?)\n```/gu)];
  const one = language => {
    const selected = blocks.filter(block => block[1] === language);
    if (selected.length !== 1) throw new Error(`AmbiguousQuickstart:${language}`);
    return selected[0][2] + '\n';
  };
  const commands = blocks.filter(block => block[1] === 'bash').map(block => block[2]);
  if (commands.length !== 3 || commands[2] !== 'node quickstart.mjs\ncat answer.jsonl') {
    throw new Error('ChangedQuickstartCommands');
  }
  return {program: one('yaml'), client: one('js'), expected: one('jsonl'),
    prepare: commands[0], install: commands[1], run: commands[2]};
}
