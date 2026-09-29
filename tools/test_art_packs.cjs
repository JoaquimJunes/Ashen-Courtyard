'use strict';
const assert = require('node:assert/strict');
const A = require('../docs/tracker/art-search.js');
const P = require('../docs/tracker/art-packs.js');
const all = changes => ({...A.defaults(), origins: [], ...changes});
const entry = (id, changes = {}) => ({id, title: id, path: 'art/' + id + '.png',
  kind: 'Images', types: ['Images'], collections: [], origin: 'Project files', role: '',
  modified_at: '2026-09-20T00:00:00Z', ...changes});
const files = [
  entry('texture', {title: 'Copper grain', types: ['Images', 'Textures'], role: 'Reference'}),
  entry('ui', {title: 'Health reference', collections: ['UI'], origin: 'Third-party library', role: 'Reference'}),
  entry('frame', {title: 'Glow keyframe 2', types: ['Images', 'Animations'], collections: ['UI'], path: 'art/sequence/glow-0002.png'}),
  entry('loose', {title: 'Map drawing 10', modified_at: '2026-09-25T00:00:00Z'}),
  entry('missing', {title: 'Missing frame', missing: true, types: ['Images', 'Animations'], collections: ['UI']})
];
const pack = {id: 'art:pack:glow', title: 'Soul light studies', description: 'Documented pale lantern variations',
  kind: 'Image packs', types: ['Images', 'Textures', 'Animations'], collections: ['UI'], origin: 'Project files', role: '',
  path: 'art/studies', members: ['texture', 'ui', 'frame', 'missing'], modified_at: '2026-09-20T00:00:00Z'};
const records = {
  texture: {status: 'Completed', priority: 'Low', attention: [], note: 'Oxidized copper treatment'},
  ui: {status: 'Planned', priority: 'High', attention: ['Bug found'], note: 'HUD health icon'},
  frame: {status: 'In progress', priority: 'High', attention: ['Needs testing'], note: 'Blue soul trail'},
  missing: {status: 'Deferred', priority: 'Normal', attention: ['Blocked'], note: 'Keep the old notes'}
};
const options = {metadata: e => records[e.id] || {}};
const ids = result => result.entries.map(e => e.id);
const snapshot = JSON.stringify({files, pack, records});

let result = P.project(files, [pack], all(), options);
assert.deepEqual(ids(result), ['loose', pack.id]);
assert.equal(result.matchedFileCount, 5);
assert.equal(result.matchedPackCount, 1);
assert.equal(result.groupedFileCount, 4);
assert.deepEqual(result.entries[1].matching_member_ids, ['texture', 'ui', 'frame', 'missing']);
assert.equal(result.entries[1].matching_count, 4);
assert.equal(result.entries[1].member_count, 4);
assert.equal(result.entries[1].matched_self, true);
assert.equal(result.entries[0], files[3], 'Original assets retain their identity');
assert.notEqual(result.entries[1], pack, 'Display-only pack fields never modify catalog data');

result = P.project(files, [pack], all({individualImages: true}), options);
assert.equal(result.entries.length, 5);
assert.equal(result.matchedPackCount, 0);
assert.equal(result.groupedFileCount, 0);
assert.equal(result.matchedFileCount, 5);
assert.ok(result.entries.every(e => files.includes(e)));

// Facets and tracking decisions must all belong to one complete member match.
assert.deepEqual(ids(P.project(files, [pack], all({types: ['Textures'], collections: ['UI']}), options)), [],
  'The texture child and a different UI child cannot lend each other facets');
assert.deepEqual(ids(P.project(files, [pack], all({origins: ['Third-party library'], types: ['Animations']}), options)), [],
  'Origin cannot be borrowed from another child');
assert.deepEqual(ids(P.project(files, [pack], all({roles: ['Reference'], types: ['Animations']}), options)), [],
  'Reference role cannot be borrowed from another child');
assert.deepEqual(ids(P.project(files, [pack], all({statuses: ['Completed'], attention: ['Bug found']}), options)), [],
  'Completed on one child plus Bug found on another is not a match');
assert.deepEqual(ids(P.project(files, [pack], all({statuses: ['Completed'], priorities: ['High']}), options)), [],
  'Priority also belongs to the same matching child');
result = P.project(files, [pack], all({types: ['Textures', 'Animations'], collections: ['UI'],
  origins: ['Project files'], roles: ['Not a reference'], statuses: ['In progress'],
  attention: ['Bug found', 'Needs testing'], priorities: ['High'], search: 'soul blue'}), options);
assert.deepEqual(ids(result), [pack.id]);
assert.deepEqual(result.entries[0].matching_member_ids, ['frame']);
assert.equal(result.matchedFileCount, 1);
assert.equal(result.entries[0].matched_self, false);

// Pack decisions are separate records and can be searched without a file hit.
records[pack.id] = {status: 'Deferred', attention: ['Needs improvement'], priority: 'High', note: 'Compare the warmer palette'};
result = P.project(files, [pack], all({search: 'warmer palette', statuses: ['Deferred'], attention: ['Needs improvement']}), options);
assert.deepEqual(ids(result), [pack.id]);
assert.equal(result.entries[0].matched_self, true);


assert.deepEqual(result.entries[0].matching_member_ids, []);
assert.equal(result.matchedFileCount, 0, 'Pack notes do not invent file matches');
assert.equal(result.matchedPackCount, 1);
assert.deepEqual(ids(P.project(files, [pack], all({search: 'pale lantern'}), options)), [pack.id], 'Pack description is searchable');
assert.deepEqual(ids(P.project(files, [pack], all({search: 'Soul studies'}), options)), [pack.id], 'Pack title is searchable');
assert.deepEqual(ids(P.project(files, [pack], all({search: 'glow 0002'}), options)), [pack.id], 'Member filename matches stay grouped');
assert.equal(P.project(files, [pack], all({search: 'warmer palette', individualImages: true}), options).entries.length, 0,
  'Individual-file view never copies pack notes onto every file');
assert.equal(P.project(files, [pack], all({search: 'warm copper'}), options).entries.length, 0,
  'One search token in a pack and another in a child cannot manufacture a match');
assert.deepEqual(ids(P.project(files, [pack], all({search: 'lantern', types: ['Textures'], collections: ['UI']}), options)), [],
  'Even a matching pack title/description cannot defeat the same-member facet witness');
delete records[pack.id];

// Duplicated source declarations never duplicate the original files in totals.
const overlap = {...pack, id: 'art:pack:other', title: 'Other pack', members: ['frame', 'missing', 'loose', 'loose']};
result = P.project([...files, files[0]], [pack, overlap, pack], all(), options);
assert.equal(result.matchedFileCount, 5);
assert.equal(result.groupedFileCount, 5);
assert.equal(result.entries.length, 2);
const projectedMembers = result.entries.flatMap(e => e.matching_member_ids || []);
assert.equal(new Set(projectedMembers).size, projectedMembers.length);
assert.deepEqual(result.entries.find(e => e.id === overlap.id).matching_member_ids, ['loose']);
const duplicatePack = {...pack, id: 'art:pack:duplicate', title: 'Independent duplicate pack'};
result = P.project(files, [pack, duplicatePack], all({search: 'Independent duplicate pack'}), options);
assert.deepEqual(ids(result), [duplicatePack.id], 'Shared file ownership never hides a pack matching its own exact title');
assert.deepEqual(result.entries[0].matching_member_ids, []);
assert.equal(result.entries[0].member_count, 4);
assert.equal(result.matchedFileCount, 0);
assert.equal(result.entries[0].matched_self, true);

result = P.project(files, [pack], all({view: 'missing'}), options);
assert.deepEqual(result.entries[0].matching_member_ids, ['missing']);
assert.equal(result.matchedFileCount, 1);
const retained = {...pack, id: 'art:pack:retained', title: 'Old annotated pack', members: ['not-in-current-catalog'], missing: true};
result = P.project([], [retained], A.defaults(), {metadata: () => ({note: 'Preserved decision'})});
assert.deepEqual(ids(result), [retained.id]);
assert.equal(result.matchedFileCount, 0);
assert.equal(result.entries[0].member_count, 1);
assert.equal(result.entries[0].missing, true);
assert.deepEqual(ids(P.project([], [retained], all({types: ['Textures']}))), [], 'Unresolved children cannot prove a texture filter');
assert.deepEqual(ids(P.project([], [{...retained, members: []}], all({search: 'old annotated'}))), [retained.id]);

// Ranking uses the strongest actual matching file or the pack's own evidence.
const activity = new Map([['frame', '2026-09-29T00:00:00Z']]);
result = P.project(files, [pack], all({sort: 'recent'}), {...options, activity});
assert.equal(result.entries[0].id, pack.id, 'Member activity moves its pack above older loose files');
result = P.project(files, [pack], all({sort: 'attention'}), options);
assert.equal(result.entries[0].id, pack.id, 'Member attention remains visible in pack ordering');
const titleMatch = entry('title', {title: 'Blue soul'});
const pathMatch = entry('path', {title: 'Unrelated file', path: 'art/blue_soul.png'});
result = P.project([...files, titleMatch, pathMatch], [pack], all({search: 'blue soul', sort: 'relevance'}),
  {...options, indexes: new Map(files.map(e => [e.id, A.indexEntry(e)]))});
assert.deepEqual(ids(result), ['title', pack.id, 'path'], 'A grouped member-note match outranks a loose path-only match');
assert.equal(JSON.stringify({files, pack, records}), snapshot, 'Projection never edits assets, membership or tracking decisions');

const customPack = {...duplicatePack, pack_source: 'custom'};
result = P.project(files, [pack, customPack], all({search: 'glow 0002'}), options);
assert.equal(result.entries.length, 2, 'A manually chosen image is searchable in each of its packs');
assert.equal(result.matchedFileCount, 1);
assert.equal(result.groupedFileCount, 1, 'Overlapping custom packs do not double-count files');
assert.deepEqual(result.entries.find(e => e.id === customPack.id).matching_member_ids, ['frame']);
console.log('Art packs: grouping, individual-file mode, all filter groups, independent pack/member search, missing records, unique counts, ranking and non-mutation passed.');
