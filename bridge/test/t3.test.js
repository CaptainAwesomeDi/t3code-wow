import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pickModelSelection, modelChoices, chosenModelSelection, effortLevels, effortOf, withEffort } from '../src/t3.js';

const sel = (instanceId, model) => ({ instanceId, model, options: [] });
const providers = [
  { instanceId: 'codex', enabled: true },
  { instanceId: 'claude', enabled: true },
  { instanceId: 'off', enabled: false },
];

test('a configured default wins, project first', () => {
  const settings = { defaultModelSelection: sel('codex', 'a'), fallbackModelSelection: sel('codex', 'b') };
  assert.equal(pickModelSelection({ project: { id: 'p', defaultModelSelection: sel('claude', 'c') }, settings, providers }).model, 'c');
  assert.equal(pickModelSelection({ project: { id: 'p' }, settings, providers }).model, 'a');
  assert.equal(pickModelSelection({ settings: { fallbackModelSelection: sel('codex', 'b') }, providers }).model, 'b');
});

test('without defaults, the latest thread in the project, then anywhere', () => {
  const threads = [
    { projectId: 'p', createdAt: '2026-11-01T00:00:00Z', modelSelection: sel('codex', 'old-here') },
    { projectId: 'p', createdAt: '2026-11-05T00:00:00Z', modelSelection: sel('claude', 'new-here') },
    { projectId: 'q', createdAt: '2026-11-08T00:00:00Z', modelSelection: sel('codex', 'elsewhere') },
    { projectId: 'p', createdAt: '2026-11-09T00:00:00Z', modelSelection: sel('codex', 'deleted'), deletedAt: '2026-11-09T01:00:00Z' },
    { projectId: 'p', createdAt: '2026-11-10T00:00:00Z', modelSelection: sel('codex', 'subagent'), lineage: { parentThreadId: 'x' } },
  ];
  const settings = { defaultModelSelection: null, fallbackModelSelection: null };
  assert.equal(pickModelSelection({ project: { id: 'p' }, settings, threads, providers }).model, 'new-here');
  assert.equal(pickModelSelection({ project: { id: 'none' }, settings, threads, providers }).model, 'elsewhere');
  assert.equal(pickModelSelection({ settings, threads: [], providers }), null);
});

test('models on a switched-off provider are skipped', () => {
  const threads = [
    { projectId: 'p', createdAt: '2026-11-09T00:00:00Z', modelSelection: sel('off', 'x') },
    { projectId: 'p', createdAt: '2026-11-01T00:00:00Z', modelSelection: sel('codex', 'y') },
  ];
  const got = pickModelSelection({ project: { id: 'p' }, settings: { defaultModelSelection: sel('off', 'z') }, threads, providers });
  assert.equal(got.model, 'y');
});

test('the model list leaves out switched-off providers and legacy models', () => {
  const list = modelChoices([
    { instanceId: 'codex', displayName: 'Codex', enabled: true, models: [{ slug: 'a', name: 'A' }, { slug: 'old', name: 'Old', isLegacy: true }] },
    { instanceId: 'off', enabled: false, models: [{ slug: 'z', name: 'Z' }] },
  ]);
  assert.deepEqual(list, [{ instanceId: 'codex', model: 'a', name: 'A', provider: 'Codex', effort: undefined }]);
});

test('a picked model keeps the options last used with it', () => {
  const providers = [
    { instanceId: 'codex', enabled: true, models: [{ slug: 'a' }, { slug: 'b' }] },
    { instanceId: 'off', enabled: false, models: [{ slug: 'z' }] },
  ];
  const high = [{ id: 'reasoningEffort', value: 'high' }];
  const low = [{ id: 'reasoningEffort', value: 'low' }];
  // The selection T3 would have used wins when it's the same model.
  const auto = { instanceId: 'codex', model: 'a', options: high };
  assert.deepEqual(chosenModelSelection({ instanceId: 'codex', model: 'a' }, { providers, candidates: [auto] }).options, high);
  // Otherwise the latest thread on that model.
  const threads = [
    { createdAt: '2026-11-01T00:00:00Z', modelSelection: { instanceId: 'codex', model: 'b', options: high } },
    { createdAt: '2026-11-05T00:00:00Z', modelSelection: { instanceId: 'codex', model: 'b', options: low } },
  ];
  assert.deepEqual(chosenModelSelection({ instanceId: 'codex', model: 'b' }, { providers, candidates: [auto], threads }).options, low);
  // "Latest" is the latest active, the order the game lists threads in.
  threads[0].latestRunStartedAt = '2026-11-08T00:00:00Z';
  assert.deepEqual(chosenModelSelection({ instanceId: 'codex', model: 'b' }, { providers, candidates: [auto], threads }).options, high);
  // Never used: no options, so T3 applies the model's defaults.
  assert.deepEqual(chosenModelSelection({ instanceId: 'codex', model: 'b' }, { providers }), { instanceId: 'codex', model: 'b' });
  assert.throws(() => chosenModelSelection({ instanceId: 'off', model: 'z' }, { providers }), /switched off/);
  assert.throws(() => chosenModelSelection({ instanceId: 'codex', model: 'gone' }, { providers }), /no longer offers/);
});

test('reasoning levels: read from the model, set on a selection', () => {
  // Shaped like Claude's descriptor in T3 Code: ultrathink only works typed into a prompt.
  const opus = {
    slug: 'opus',
    name: 'Opus',
    capabilities: {
      optionDescriptors: [
        { id: 'fastMode', type: 'boolean' },
        { id: 'effort', label: 'Reasoning', type: 'select', options: [{ id: 'low', label: 'Low' }, { id: 'medium', label: 'Medium', isDefault: true }, { id: 'ultrathink', label: 'Ultrathink' }], promptInjectedValues: ['ultrathink'] },
      ],
    },
  };
  assert.deepEqual(effortLevels(opus), { id: 'effort', options: [{ id: 'low', label: 'Low' }, { id: 'medium', label: 'Medium' }], default: 'medium' });
  assert.equal(effortLevels({ slug: 'plain' }), undefined);
  const providers = [{ instanceId: 'claude', enabled: true, models: [opus, { slug: 'plain' }] }];
  const sel = { instanceId: 'claude', model: 'opus', options: [{ id: 'effort', value: 'low' }, { id: 'contextWindow', value: '1m' }] };
  assert.equal(effortOf(sel), 'low');
  assert.deepEqual(withEffort(sel, 'medium', providers).options, [{ id: 'contextWindow', value: '1m' }, { id: 'effort', value: 'medium' }], 'other options are kept');
  assert.equal(withEffort(sel, undefined, providers), sel);
  assert.throws(() => withEffort(sel, 'ultrathink', providers), /doesn't offer ultrathink/);
  assert.throws(() => withEffort({ instanceId: 'claude', model: 'plain' }, 'low', providers), /no reasoning levels/);
});

test('a side chat forks with a minted id, then sends its first message', async () => {
  const { T3Client } = await import('../src/t3.js');
  const c = new T3Client({ tokenProvider: async () => 'x' });
  const calls = [];
  c.dispatch = async (cmd) => calls.push(cmd);
  const res = await c.forkSideChat('parent', 'What did the build say?\n(see log)');
  assert.equal(calls[0].targetThreadId, res.threadId, 'the fork id is minted before the fork');
  assert.deepEqual(calls[0], {
    type: 'thread.fork',
    sourceThreadId: 'parent',
    targetThreadId: res.threadId,
    sourcePoint: { type: 'latest_stable' },
    sideChat: true,
    title: 'What did the build say?',
    createdBy: 'user',
    creationSource: 'web',
  });
  assert.deepEqual(calls[1], {
    type: 'message.dispatch',
    threadId: res.threadId,
    messageId: calls[1].messageId,
    text: 'What did the build say?\n(see log)',
    attachments: [],
    createdBy: 'user',
    creationSource: 'web',
    dispatchMode: { type: 'start_immediately' },
  }, 'the first message starts the fork at once');
});

test('an unused fork is deleted again when its first message fails', async () => {
  const { T3Client } = await import('../src/t3.js');
  const c = new T3Client({ tokenProvider: async () => 'x' });
  const calls = [];
  c.dispatch = async (cmd) => {
    calls.push(cmd);
    if (cmd.type === 'message.dispatch') throw new Error('boom');
  };
  await assert.rejects(() => c.forkSideChat('parent', 'hi'), /boom/);
  assert.deepEqual(calls[2], { type: 'thread.delete', threadId: calls[0].targetThreadId, onlyIfUnused: true });
});

test('the thread family is read with getThreadFamily, gated on the server advertising it', async () => {
  const { T3Client } = await import('../src/t3.js');
  const c = new T3Client({ tokenProvider: async () => 'x' });
  const calls = [];
  c.request = async (tag, payload) => (calls.push([tag, payload]), { threads: [{ id: 'kid' }] });
  assert.deepEqual(await c.getThreadFamily('t1'), [{ id: 'kid' }]);
  assert.deepEqual(calls, [['orchestration.getThreadFamily', { threadId: 't1' }]]);

  assert.equal(c.sideChatsSupported(), false);
  c.config = { environment: { capabilities: { sideChats: true } } };
  assert.equal(c.sideChatsSupported(), false, 'family reads need shellThreadFamilies too');
  c.config = { environment: { capabilities: { sideChats: true } }, shellThreadFamilies: true };
  assert.equal(c.sideChatsSupported(), true);
});
