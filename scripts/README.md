# Cached Stack call search

`cached_stack_crawl.py` is a stdlib-only, resumable corpus crawler for the
three user-authorized catalogs: 22/7, Project SEKAI, and LLSIF. It downloads
paginated level metadata, chart data, and engine **play** data only. It does
not download music, covers, skins, effects, or particles.

Run offline tests:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_cached_stack_crawl.py' -v
```

Start or resume a crawl (the same command resumes its durable checkpoint):

```sh
python3 -u scripts/cached_stack_crawl.py --cache tmp/cached-stack-crawl
```

For a bounded initial probe, add `--max-requests 3`. There is **no CLI option
to reduce pacing**. Every actual HTTP request, redirect hop, and retry waits
for a 60–120 second randomized gap after the preceding response on that
hostname. The two milkbun catalogs alternate tasks on one worker; SEKAI can
run concurrently. Redirects to a shared hostname also share the request gate.
HTTP 429/5xx responses respect `Retry-After`; transient failures use additional
exponential backoff, failing visibly after six attempts. A hard-killed request
leaves a conservative persisted cooldown. SIGINT/SIGTERM stops gracefully.
Only the two explicitly approved server hostnames may be contacted, including
redirects. Existing local metadata uses those hosts for chart and play data.
Unknown destinations fail visibly for scope review; they are never followed
automatically. Referenced level/engine source prefixes are preserved.

An exclusive cache-directory process lock prevents duplicate crawl workers.
Do not start a second directory against these servers while a crawl is live:
the lock and pacing state are intentionally local to one crawl directory.
Do not delete a lock file to bypass a live worker.

Existing local gzip/plain JSON chart or engine blobs can be imported using
`--seed path/to/engine.gz path/to/level.gz`. The crawler validates their shape
and indexes their actual SHA-1. A fetched resource with a matching declared
SHA-1 reuses those bytes even when its URL differs. Every cache read verifies
the stored SHA-256; declared SHA-1 hashes are also verified. Hashless resources
and catalog responses are cached by URL for **this dated crawl only**. Use a
new directory for an intentionally new catalog snapshot, only after stopping
the old worker. This is not application cache freshness/invalidation logic.

Status is safe to read while the worker runs:

```sh
python3 scripts/cached_stack_crawl.py --cache tmp/cached-stack-crawl --status
```

The cache contains atomic content-addressed files in `blobs/`, SQLite
checkpoint/catalog associations in `crawl.sqlite3`, an append-only request
log in `events.jsonl`, and an atomically replaced `report.json`. Chart names
and full metadata remain associated with engine resources even when the
engine bytes are shared. Each engine report distinguishes Stack-prefixed
function nodes reachable from archetype callbacks from orphan nodes. This
includes all callbacks, lazy branches, and potentially spawned archetypes;
it is **not proof of execution by a particular chart**. Ordinary level entity
data is also downloaded/validated, but Stack calls belong to engine play data.

Do not claim a complete corpus when tasks are pending/failed, item failures
are reported, pagination changed, or a run stopped early. A catalog crawled
over days can change between pages; this cannot establish an atomic snapshot
without a server snapshot contract. Inspect raw cached pages and the log to
resolve omissions. A repeated cursor is an explicit failure. Malformed items
are recorded separately without preventing enumeration of later pages.
Permanent failures remain visible on resume instead of being retried forever.

Keep all downloaded material under ignored `tmp/`; commit only this utility,
its offline tests, and documentation. No physical device is involved.
