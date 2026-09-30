#!/usr/bin/env python3
"""Slow, resumable, metadata-only Sonolus Stack* corpus search (stdlib only).

Each cache directory is a frozen crawl, not an always-fresh application cache.
Use a NEW directory for a later catalog snapshot. Existing local chart/engine
JSON blobs can be imported with --seed. No audio or images are fetched.
"""

import argparse
import concurrent.futures
import datetime
import email.utils
import fcntl
import gzip
import hashlib
import http.client
import io
import json
import math
import os
from pathlib import Path
import random
import re
import signal
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


SERVERS = {
    "nanaon": "https://sonolus.milkbun.org/nanaon",
    "sekai": "https://sonolus.sekai.best",
    "llsif": "https://sonolus.milkbun.org/llsif",
}
# Cached metadata references chart/play data on these origins. Unknown
# destinations, including redirects, require explicit scope review.
ALLOWED_HOSTS = frozenset(("sonolus.milkbun.org", "sonolus.sekai.best"))
CALLBACKS = (
    "preprocess", "spawnOrder", "shouldSpawn", "initialize",
    "updateSequential", "touch", "updateParallel", "terminate",
)
MAX_BYTES = 64 * 1024 * 1024
MAX_JSON_BYTES = 256 * 1024 * 1024


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".part")
    with temporary.open("wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def resolve(base, url):
    if not isinstance(url, str) or not url:
        raise ValueError("Resource URL is missing")
    # Sonolus /sonolus/... locators are relative to a server's base directory,
    # including /nanaon or /llsif, rather than the origin's root.
    result = urllib.parse.urljoin(base.rstrip("/") + "/", url.lstrip("/"))
    parsed = urllib.parse.urlsplit(result)
    if (parsed.scheme not in ("https", "http") or not parsed.hostname
            or parsed.username or parsed.password or parsed.port not in (None, 80, 443)
            or parsed.hostname in ("localhost", "localhost.localdomain")
            or ":" in parsed.hostname
            or re.fullmatch(r"[0-9.]+", parsed.hostname)):
        raise ValueError("Only public HTTP(S) resource URLs are accepted")
    if parsed.hostname not in ALLOWED_HOSTS:
        raise ValueError("Resource hostname is outside the approved crawl scope: "
                         + parsed.hostname)
    return urllib.parse.urlunsplit(parsed._replace(fragment=""))


def decode_json(data):
    if data.startswith(b"\x1f\x8b"):
        with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
            data = stream.read(MAX_JSON_BYTES + 1)
    if len(data) > MAX_JSON_BYTES:
        raise ValueError("JSON resource exceeds the decompressed size limit")
    return json.loads(data)


def analyze_engine(document):
    nodes = document.get("nodes")
    if not isinstance(nodes, list):
        raise ValueError("Engine play data has no nodes array")
    roots = []
    for archetype in document.get("archetypes", []):
        for callback in CALLBACKS:
            value = archetype.get(callback)
            if isinstance(value, dict) and "index" in value:
                roots.append(value["index"])
    visited, pending, invalid = set(), list(roots), []
    while pending:
        index = pending.pop()
        if type(index) is not int or not 0 <= index < len(nodes):
            invalid.append(index)
            continue
        if index in visited:
            continue
        visited.add(index)
        pending.extend(nodes[index].get("args", []))
    calls = [
        {"index": index, "function": node["func"],
         "args": node.get("args", []),
         "callback_graph_reachable": index in visited}
        for index, node in enumerate(nodes)
        if isinstance(node.get("func"), str)
        and node["func"].startswith("Stack")
    ]
    return {"node_count": len(nodes), "callback_root_count": len(roots),
            "reachable_node_count": len(visited),
            "invalid_node_references": invalid, "stack_calls": calls}


def retry_after(value, now):
    if not value:
        return 0
    try:
        seconds = float(value)
        return max(0, seconds) if math.isfinite(seconds) else 0
    except ValueError:
        try:
            return max(0, email.utils.parsedate_to_datetime(value).timestamp() - now)
        except (TypeError, ValueError, OverflowError):
            return 0


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        return None


class RetryRequest(Exception):
    def __init__(self, message, delay=0):
        super().__init__(message)
        self.delay = delay


class Crawl:
    def __init__(self, directory, delay=(60, 120), request_limit=None):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.lock_file = (self.directory / "crawl.lock").open("a+")
        try:
            fcntl.flock(self.lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock_file.close()
            raise RuntimeError("A crawler already owns this cache directory")
        self.db = sqlite3.connect(self.directory / "crawl.sqlite3",
                                  check_same_thread=False)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript("""
          CREATE TABLE IF NOT EXISTS tasks (
            server TEXT, kind TEXT, url TEXT, expected TEXT, context TEXT,
            state TEXT DEFAULT 'pending', tries INTEGER DEFAULT 0,
            ready REAL DEFAULT 0, error TEXT, result TEXT,
            PRIMARY KEY (server, kind, url));
          CREATE TABLE IF NOT EXISTS responses (
            url TEXT PRIMARY KEY, digest TEXT, sha1 TEXT, fetched REAL);
          CREATE TABLE IF NOT EXISTS hosts (
            host TEXT PRIMARY KEY, ready REAL);
          CREATE TABLE IF NOT EXISTS charts (
            server TEXT, name TEXT, data_url TEXT, engine_url TEXT, metadata TEXT,
            PRIMARY KEY (server, name));
          CREATE TABLE IF NOT EXISTS item_failures (
            server TEXT, page_url TEXT, item_index INTEGER, name TEXT, error TEXT,
            PRIMARY KEY (server, page_url, item_index));
        """)
        self.mutex = threading.RLock()
        self.host_locks = {}
        self.resource_locks = {}
        self.delay = delay
        self.stop = threading.Event()
        self.request_limit = request_limit
        self.requests = 0
        self.opener = urllib.request.build_opener(NoRedirect())

    def close(self):
        self.db.close()
        self.lock_file.close()

    def wait_until(self, ready):
        while not self.stop.is_set():
            remaining = ready - time.time()
            if remaining <= 0:
                return False
            self.stop.wait(min(60, remaining))
        return True

    def seed(self, path):
        data = Path(path).read_bytes()
        if len(data) > MAX_BYTES:
            raise ValueError("Seed resource exceeds the download size limit")
        document = decode_json(data)
        if not isinstance(document, dict) or not (
                isinstance(document.get("nodes"), list)
                or isinstance(document.get("entities"), list)):
            raise ValueError("Seed must be chart data or engine play data")
        sha1 = hashlib.sha1(data).hexdigest()
        self.save_response("seed://" + sha1, data, sha1)
        self.log("seed", path=str(path), sha1=sha1)

    def log(self, event, **fields):
        with self.mutex:
            record = {"at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      "event": event, **fields}
            with (self.directory / "events.jsonl").open("a") as stream:
                stream.write(json.dumps(record, ensure_ascii=False) + "\n")
            print(json.dumps(record, ensure_ascii=False), flush=True)

    def enqueue(self, server, kind, url, expected=None, **context):
        if expected is not None and not re.fullmatch(r"[0-9a-fA-F]{40}", expected):
            raise ValueError("Resource hash must be SHA-1")
        with self.mutex, self.db:
            existing = self.db.execute(
                "SELECT expected FROM tasks WHERE server=? AND kind=? AND url=?",
                (server, kind, url)).fetchone()
            if existing and existing[0] != (expected.lower() if expected else None):
                raise ValueError("Resource hash changed during this catalog snapshot: " + url)
            self.db.execute(
                "INSERT OR IGNORE INTO tasks(server,kind,url,expected,context) "
                "VALUES(?,?,?,?,?)", (server, kind, url,
                                     expected.lower() if expected else None,
                                     json.dumps(context)))

    def cached(self, url, expected):
        with self.mutex:
            if expected:
                row = self.db.execute(
                    "SELECT digest FROM responses WHERE sha1=? LIMIT 1",
                    (expected,)).fetchone()
            else:
                row = self.db.execute(
                    "SELECT digest FROM responses WHERE url=?", (url,)).fetchone()
            if not row:
                return None
            path = self.directory / "blobs" / row[0]
            if not path.exists():
                return None
            data = path.read_bytes()
            if hashlib.sha256(data).hexdigest() != row[0]:
                raise ValueError("Cached blob is corrupt: " + str(path))
            if expected and hashlib.sha1(data).hexdigest() != expected:
                raise ValueError("Cached resource SHA-1 does not match metadata")
            return data

    def save_response(self, url, data, expected):
        sha1 = hashlib.sha1(data).hexdigest()
        if expected and sha1 != expected:
            raise RetryRequest("Resource SHA-1 does not match metadata")
        digest = hashlib.sha256(data).hexdigest()
        with self.mutex, self.db:
            atomic_write(self.directory / "blobs" / digest, data)
            self.db.execute("INSERT OR REPLACE INTO responses VALUES(?,?,?,?)",
                            (url, digest, sha1, time.time()))

    def request_once(self, url):
        url = resolve("https://sonolus.sekai.best", url)
        host = urllib.parse.urlsplit(url).hostname
        with self.mutex:
            lock = self.host_locks.setdefault(host, threading.Lock())
        with lock:
            with self.mutex:
                row = self.db.execute("SELECT ready FROM hosts WHERE host=?",
                                      (host,)).fetchone()
            if self.wait_until(row[0] if row else 0):
                raise InterruptedError("Crawler stopped")
            with self.mutex:
                if self.request_limit is not None and self.requests >= self.request_limit:
                    self.stop.set()
                    raise InterruptedError("Bounded request limit reached")
                self.requests += 1
            # Reserve before I/O as well: a hard kill during a request must not
            # permit an immediate unpaced retry when the process is restarted.
            self.set_host_ready(host, time.time() + 120 + self.delay[1])
            self.log("request", url=url)
            cooldown = random.uniform(*self.delay)
            try:
                request = urllib.request.Request(url, headers={
                    "User-Agent": "OpenRhythm-Compatibility-Audit/1.0",
                    "Accept": "*/*", "Accept-Encoding": "identity",
                    "Sonolus-Version": "1.1.2",
                })
                try:
                    response = self.opener.open(request, timeout=90)
                except urllib.error.HTTPError as error:
                    response = error
                with response:
                    status = response.status
                    headers = dict(response.headers)
                    if status == 429 or status >= 500:
                        cooldown = max(cooldown, retry_after(
                            response.headers.get("Retry-After"), time.time()))
                        raise RetryRequest("Server returned HTTP " + str(status),
                                           cooldown)
                    if status in (301, 302, 303, 307, 308):
                        location = response.headers.get("Location")
                        if not location:
                            raise ValueError("Redirect is missing Location")
                        return status, headers, location
                    if status != 200:
                        raise ValueError("Server returned HTTP " + str(status))
                    declared = response.headers.get("Content-Length")
                    encodings = response.headers.get("Transfer-Encoding", "").lower().split(",")
                    if "chunked" in [encoding.strip() for encoding in encodings]:
                        declared = None
                    length = int(declared) if declared is not None else None
                    if length is not None and not 0 <= length <= MAX_BYTES:
                        raise ValueError("Declared resource size exceeds the download limit")
                    data = response.read(MAX_BYTES + 1)
                    if len(data) > MAX_BYTES:
                        raise ValueError("Resource exceeds the download size limit")
                    # HTTPResponse.read(amt) can return short bytes at EOF
                    # without raising IncompleteRead for Content-Length bodies.
                    if length is not None and len(data) != length:
                        raise RetryRequest("Transfer ended before its declared Content-Length")
                    return status, headers, data
            except (urllib.error.URLError, TimeoutError, OSError,
                    http.client.HTTPException) as error:
                raise RetryRequest(str(error)) from error
            finally:
                self.set_host_ready(host, time.time() + cooldown)

    def set_host_ready(self, host, ready):
        with self.mutex, self.db:
            self.db.execute("INSERT OR REPLACE INTO hosts VALUES(?,?)", (host, ready))

    def fetch(self, url, expected=None):
        key = ("sha1", expected) if expected else ("url", url)
        with self.mutex:
            lock = self.resource_locks.setdefault(key, threading.Lock())
        with lock:
            return self.fetch_single(url, expected)

    def fetch_single(self, url, expected):
        cached = self.cached(url, expected)
        if cached is not None:
            return cached
        current, seen = url, set()
        for _ in range(6):
            if current in seen:
                raise ValueError("Redirect cycle")
            seen.add(current)
            status, _, body = self.request_once(current)
            if status == 200:
                self.save_response(url, body, expected)
                return body
            # HTTP redirects follow RFC relative resolution, unlike resource
            # locators in Sonolus metadata. Every hop is independently paced.
            current = resolve("https://invalid.invalid", urllib.parse.urljoin(current, body))
        raise ValueError("Too many redirects")

    def list_url(self, server, page, cursor=None):
        query = {"localization": "en", "page": page}
        if cursor is not None:
            query["cursor"] = cursor
        return SERVERS[server] + "/sonolus/levels/list?" + urllib.parse.urlencode(query)

    def process(self, server, kind, url, expected, context):
        document = decode_json(self.fetch(url, expected))
        if not isinstance(document, dict):
            raise ValueError("Resource JSON must be an object")
        if kind == "page":
            items = document.get("items")
            count = document.get("pageCount")
            if not isinstance(items, list) or type(count) is not int:
                raise ValueError("Catalog page is missing items or pageCount")
            for index, item in enumerate(items):
                try:
                    self.add_item(server, item)
                except (ValueError, TypeError, AttributeError) as error:
                    name = item.get("name") if isinstance(item, dict) else None
                    with self.mutex, self.db:
                        self.db.execute(
                            "INSERT OR REPLACE INTO item_failures VALUES(?,?,?,?,?)",
                            (server, url, index, name, str(error)))
                    self.log("item_failed", server=server, page_url=url,
                             item_index=index, name=name, error=str(error))
            page = context["page"]
            cursor = document.get("cursor")
            if count < 0 and cursor is not None:
                seen = context.get("seen_cursors", [])
                if not isinstance(cursor, str) or cursor in seen:
                    raise ValueError("Catalog pagination cursor repeats or is invalid")
                self.enqueue(server, "page", self.list_url(server, page + 1, cursor),
                             page=page + 1, seen_cursors=seen + [cursor])
            elif count >= 0 and page + 1 < count:
                self.enqueue(server, "page", self.list_url(server, page + 1),
                             page=page + 1)
            return {"items": len(items), "page_count": count, "page": page}
        if kind == "engine":
            return analyze_engine(document)
        entities = document.get("entities")
        if not isinstance(entities, list):
            raise ValueError("Chart data has no entities array")
        return {"entity_count": len(entities)}

    def add_item(self, server, item):
        engine, data = item.get("engine", {}), item.get("data", {})
        name = item.get("name")
        if not isinstance(name, str) or not isinstance(engine, dict):
            raise ValueError("Catalog item has no complete engine metadata")
        play = engine.get("playData", {})
        level_source = resolve(SERVERS[server], item.get("source") or SERVERS[server])
        engine_source = resolve(level_source, engine.get("source") or level_source)
        engine_url = resolve(engine_source, play.get("url"))
        data_url = resolve(level_source, data.get("url"))
        self.enqueue(server, "engine", engine_url, play.get("hash"),
                     name=engine.get("name"))
        self.enqueue(server, "level", data_url, data.get("hash"))
        with self.mutex, self.db:
            self.db.execute("INSERT OR REPLACE INTO charts VALUES(?,?,?,?,?)",
                            (server, name, data_url, engine_url, json.dumps(item)))

    def run_group(self, servers):
        # One worker per catalog hostname, alternating catalogs each task. This
        # prevents either of milkbun's catalogs monopolizing its request gate.
        for server in servers:
            self.enqueue(server, "page", self.list_url(server, 0), page=0)
        position = 0
        while not self.stop.is_set():
            candidates = []
            now = time.time()
            with self.mutex:
                for offset in range(len(servers)):
                    index = (position + offset) % len(servers)
                    server = servers[index]
                    row = self.db.execute(
                        "SELECT kind,url,expected,context,tries,ready FROM tasks "
                        "WHERE server=? AND state='pending' ORDER BY "
                        "CASE WHEN ready<=? THEN 0 ELSE 1 END, "
                        "CASE WHEN ready<=? THEN CASE kind WHEN 'engine' THEN 0 "
                        "WHEN 'page' THEN 1 ELSE 2 END ELSE 3 END, "
                        "CASE WHEN ready<=? THEN 0 ELSE ready END, rowid LIMIT 1",
                        (server, now, now, now)).fetchone()
                    if row:
                        candidates.append((max(now, row[5]), offset, index, row))
            if not candidates:
                break
            _, _, index, row = min(candidates)
            server = servers[index]
            position = (index + 1) % len(servers)
            kind, url, expected, context, tries, ready = row
            if self.wait_until(ready):
                break
            try:
                result = self.process(server, kind, url, expected, json.loads(context))
                with self.mutex, self.db:
                    self.db.execute("UPDATE tasks SET state='done',result=?,error=NULL "
                                    "WHERE server=? AND kind=? AND url=?",
                                    (json.dumps(result), server, kind, url))
                self.log("complete", server=server, kind=kind, url=url,
                         stack_call_count=len(result.get("stack_calls", [])))
            except InterruptedError:
                break
            except Exception as error:
                attempts = tries + 1
                retry = isinstance(error, RetryRequest) and attempts < 6
                delay = max(getattr(error, "delay", 0),
                            min(21600, 300 * 2 ** tries) + random.uniform(0, 120))
                with self.mutex, self.db:
                    self.db.execute("UPDATE tasks SET state=?,tries=?,ready=?,error=? "
                                    "WHERE server=? AND kind=? AND url=?",
                                    ("pending" if retry else "failed", attempts,
                                     time.time() + delay, str(error), server, kind, url))
                self.log("retry" if retry else "failed", server=server, kind=kind,
                         url=url, error=str(error), retry_delay=delay if retry else None)
            self.report()

    def report(self):
        with self.mutex:
            counts = [dict(zip(("server", "kind", "state", "count"), row))
                      for row in self.db.execute(
                          "SELECT server,kind,state,count(*) FROM tasks GROUP BY 1,2,3")]
            hits = []
            for server, url, result in self.db.execute(
                    "SELECT server,url,result FROM tasks WHERE kind='engine' AND state='done'"):
                result = json.loads(result)
                if result["stack_calls"]:
                    charts = [row[0] for row in self.db.execute(
                        "SELECT name FROM charts WHERE server=? AND engine_url=?",
                        (server, url))]
                    hits.append({"server": server, "engine_url": url,
                                 "charts": charts, **result})
            failures = [dict(zip(("server", "kind", "url", "error"), row))
                        for row in self.db.execute(
                            "SELECT server,kind,url,error FROM tasks WHERE state='failed'")]
            page_counts = {}
            for server, result in self.db.execute(
                    "SELECT server,result FROM tasks WHERE kind='page' AND state='done'"):
                page_counts.setdefault(server, set()).add(json.loads(result)["page_count"])
            item_failures = [dict(zip(
                ("server", "page_url", "item_index", "name", "error"), row))
                for row in self.db.execute("SELECT * FROM item_failures")]
            report = {"updated": time.time(), "counts": counts, "stack_hits": hits,
                      "observed_page_counts": {server: sorted(values)
                                               for server, values in page_counts.items()},
                      "pagination_changed": [server for server, values in page_counts.items()
                                             if len(values) > 1],
                      "failures": failures, "item_failures": item_failures,
                      "limits": "A paced catalog crawl is not an atomic server snapshot. "
                      "Reachable means graph reachability from every archetype callback, "
                      "including spawnable archetypes, not proof a chart executes a node."}
            atomic_write(self.directory / "report.json",
                         json.dumps(report, ensure_ascii=False, indent=2).encode())
            return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--servers", nargs="+", choices=SERVERS, default=list(SERVERS))
    parser.add_argument("--max-requests", type=int)
    parser.add_argument("--seed", type=Path, nargs="*", default=[])
    parser.add_argument("--status", action="store_true")
    args = parser.parse_args()
    if args.status:
        print((args.cache / "report.json").read_text())
        return
    crawl = Crawl(args.cache, request_limit=args.max_requests)
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: crawl.stop.set())
    try:
        for path in args.seed:
            crawl.seed(path)
        crawl.log("started", pid=os.getpid(), servers=args.servers,
                  minimum_delay=crawl.delay[0], maximum_delay=crawl.delay[1])
        groups = {}
        for server in dict.fromkeys(args.servers):
            host = urllib.parse.urlsplit(SERVERS[server]).hostname
            groups.setdefault(host, []).append(server)
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(groups)) as pool:
            list(pool.map(crawl.run_group, groups.values()))
        crawl.report()
        crawl.log("stopped", requests=crawl.requests)
    finally:
        crawl.close()


if __name__ == "__main__":
    main()
