/* Pure display projection: original file IDs and editable records stay separate. */
(function(root, factory) {
  if (typeof module !== 'undefined' && module.exports) module.exports = factory(require('./art-search.js'));
  else root.ArtPacks = factory(root.ArtSearch);
})(typeof window !== 'undefined' ? window : globalThis, function(A) {
  'use strict';
  const natural = new Intl.Collator(undefined, {numeric: true, sensitivity: 'base'});
  const uniqueIds = values => [...new Set(Array.isArray(values) ? values.filter(id => typeof id === 'string' && id) : [])];
  const lookup = (values, id) => values instanceof Map ? values.get(id) : values && Object.prototype.hasOwnProperty.call(values, id) ? values[id] : undefined;
  const attention = metadata => Array.isArray(metadata?.attention) ? new Set(metadata.attention).size : 0;
  const nameOrder = (a, b, metadata) => natural.compare(metadata(a)?.display_name || a.title || '', metadata(b)?.display_name || b.title || '') || natural.compare(a.path || '', b.path || '') || String(a.path || '').localeCompare(String(b.path || '')) || String(a.id || '').localeCompare(String(b.id || ''));

  // Every child is filtered on its own. Pack-level unions are useful labels but
  // cannot make a Texture in one folder and a UI image elsewhere match Texture+UI.
  function project(entries, packs, filters = A.defaults(), {metadata = () => ({}), activity, indexes} = {}) {
    const packById = new Map();
    for (const pack of packs || []) if (pack?.id && !packById.has(pack.id)) packById.set(pack.id, pack);
    const files = new Map();
    for (const entry of entries || []) if (entry?.id && !packById.has(entry.id) && !files.has(entry.id)) files.set(entry.id, entry);
    const matched = new Map(), ranks = new Map(), hasQuery = Boolean(A.normalize(filters.search));
    const evidence = (entry, meta, index) => ({
      score: hasQuery ? A.search(index || lookup(indexes, entry.id) || A.indexEntry(entry), filters.search, [meta?.note,...(meta?.art_tags||[])].join(' '), meta?.display_name).score : 0,
      attention: attention(meta), date: A.latestTimestamp(entry, lookup(activity, entry.id))
    });
    for (const entry of files.values()) {
      const meta = metadata(entry);
      if (!A.filter(entry, meta, filters, lookup(activity, entry.id))) continue;
      matched.set(entry.id, entry); ranks.set(entry, evidence(entry, meta));
    }
    let display = [...matched.values()], groupedFileCount = 0;
    if (!filters.individualImages) {
      const owners = new Map();
      // Catalog order is stable. Defensively give a repeated file to its first
      // pack so overlapping declarations never duplicate file counts or cards.
      for (const pack of packById.values()) for (const id of uniqueIds(pack.members)) if (!owners.has(id)) owners.set(id, pack.id);
      const grouped = new Set(), packEntries = [];
      const facetFilters = {...filters, search: '', statuses: [], attention: [], priorities: [], review_labels: [], art_tags: [], view: 'all'};
      for (const pack of packById.values()) {
        const declaredMembers = uniqueIds(pack.members);
        // Explicit user groupings remain searchable through every chosen image,
        // even when a documented pack also contains it. Totals use Sets below.
        const members = pack.pack_source === 'custom' ? declaredMembers : declaredMembers.filter(id => owners.get(id) === pack.id);
        // Ownership deduplicates file results, not a pack's independent identity:
        // an overlapping pack must remain searchable by its own title or notes.
        const known = declaredMembers.map(id => files.get(id)).filter(Boolean);
        const matchingIds = members.filter(id => matched.has(id));
        const meta = metadata(pack);
        const searchable = {...pack, note: [pack.note, pack.description].filter(Boolean).join(' ')};
        const ownIndex = A.indexEntry(searchable);
        // Empty retained packs can still be found by their own metadata. When
        // type/collection filters are set, missing children supply no evidence.
        const facetWitness = known.length ? known.some(entry => A.filter(entry, {}, facetFilters)) :
          declaredMembers.length > 0 && !filters.types?.length && !filters.collections?.length;
        const emptyPack = declaredMembers.length === 0;
        const selfMatches = (facetWitness || emptyPack && !filters.types?.length && !filters.collections?.length) &&
          A.filter(searchable, meta, filters, lookup(activity, pack.id));
        if (!matchingIds.length && !selfMatches) continue;
        const projected = {...pack, is_pack: true, matching_member_ids: matchingIds,
          matching_count: matchingIds.length, member_count: declaredMembers.length, matched_self: selfMatches};
        const sources = matchingIds.map(id => ranks.get(matched.get(id)));
        if (selfMatches) sources.push(evidence(searchable, meta, ownIndex));
        ranks.set(projected, {
          score: Math.max(0, ...sources.map(value => value.score)),
          attention: Math.max(0, ...sources.map(value => value.attention)),
          date: Math.max(0, ...sources.map(value => value.date))
        });
        packEntries.push(projected);
        for (const id of matchingIds) grouped.add(id);
      }
      groupedFileCount = grouped.size;
      display = [...packEntries, ...display.filter(entry => !grouped.has(entry.id))];
    }
    display.sort((a, b) => {
      const left = ranks.get(a), right = ranks.get(b);
      if (['recent', 'modified', 'recently-changed'].includes(filters.sort)) return right.date - left.date || nameOrder(a, b, metadata);
      if (filters.sort === 'attention') return right.attention - left.attention || nameOrder(a, b, metadata);
      if (filters.sort === 'relevance' && hasQuery) return right.score - left.score || nameOrder(a, b, metadata);
      return nameOrder(a, b, metadata);
    });
    return {entries: display, matchedFileCount: matched.size,
      matchedPackCount: display.filter(entry => entry.is_pack).length, groupedFileCount};
  }
  return {project};
});
