---
assignees:
- claude-code
position_column: done
position_ordinal: b480
title: 'HybridRanker: rank zero and negative cosine scores for embedded documents'
---
Request from FoundationModelsCodeContext (CodeContext task 01M6KHG55E3K73B27F5AJWFM9Y).

PROBLEM
HybridRanker ranks only cosine scores that are greater than 0.0 (rankingOfPositiveScores in HybridRanker.swift). CodeContext ranks every embedded chunk, also chunks with zero or negative cosine. A chunk with a negative cosine still gets a cosine rank in CodeContext. In HybridRanker it gets no cosine rank. The fused order can differ. CodeContext cannot delete its own fuseRankings until this is solved.

WHY POSITIVE-ONLY IS RIGHT FOR BM25 AND TRIGRAM
For BM25 and trigram, a score of 0.0 means "no match". It is correct to leave such a document out of the list. For cosine, 0.0 or a negative value is a real similarity value, not "no match". The only "no signal" case for cosine is "the document has no embedding". The current API cannot tell these two cases apart, because cosineScores is [Double] and 0.0 stands for "no embedding".

WORK
1. Add a way to mark a document as "no embedding" that is separate from a score of 0.0. Suggested: accept per-document optional scores (cosineScores: [Double?]), where nil means "no embedding". Choose the API shape that is simplest. Follow ARCHITECTURE.md (no backward compatibility, no layered interfaces).
2. Rank every document that has a non-nil cosine score, including zero and negative values. Documents with nil get no cosine rank.
3. Keep Hit.signals.cosine as 0.0 for nil (as documented now) and the raw value otherwise.
4. Decide the default: the new behavior should be the only behavior unless a test shows a reason to keep both. Update doc comments and the existing tests that assume positive-only ranking.
5. Add tests: negative cosine ranks below positive and above nil; zero cosine gets a rank; nil gets no rank; a document set with all-negative cosine still gives a cosine ranking.
6. Add an explicit stable tie-break inside each signal ranking (see below).

TIE-BREAK FINDING (answer for CodeContext)
- Final fused order: ties in the fused score break by ascending array index (sortByNormalizedScore). This is the position in the input documents array, not the id.
- Per-signal ranking (rankingOfPositiveScores): sorted by score descending with NO explicit tie-break. Equal scores keep an order that depends on the sort algorithm. Swift sort is stable in practice but not guaranteed by the documentation. Fix this in this task: break ties by ascending index.
- Result: the order is the same as "lower chunk id" if and only if the caller passes documents sorted ascending by chunk id. Otherwise the order can differ. CodeContext must pass documents (and ids, cosineScores) in ascending chunk id order.

SELECTIONTIER OVER HYBRIDRANKER CANDIDATES
CodeContext asks how to run SelectionTier over HybridRanker candidates for an index that changes per file (Searcher has a fixed catalog). Investigate in a follow-up task after this one. Likely approach: HybridRanker.topMatches already takes the documents per call, so no fixed catalog is needed; SelectionTier should accept a candidate list of (id, text) built from the Hit list.