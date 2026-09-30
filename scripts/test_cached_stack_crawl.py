#!/usr/bin/env python3
"""Offline crawler regression tests; never contact a server."""

import gzip
import hashlib
import http.client
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
import urllib.error
from unittest.mock import patch

from cached_stack_crawl import (
    Crawl, RetryRequest, SERVERS, analyze_engine, decode_json, resolve, retry_after,
)


def encoded(value):
    return gzip.compress(json.dumps(value).encode(), mtime=0)


def item(name="song-hard", engine_hash=None):
    play = {"url": "/engine.gz"}
    if engine_hash:
        play["hash"] = engine_hash
    return {"name": name, "data": {"url": "/" + name + ".gz"},
            "engine": {"name": "test", "playData": play},
            "bgm": {"url": "/must-not-fetch.mp3"},
            "cover": {"url": "/must-not-fetch.png"}}


class CrawlTests(unittest.TestCase):
    def setUp(self):
        self.allowed = patch("cached_stack_crawl.ALLOWED_HOSTS", {
            "sonolus.milkbun.org", "sonolus.sekai.best", "example.com",
            "other.example", "levels.example", "engines.example",
            "first.example", "second.example",
        })
        self.allowed.start()
        self.temporary = tempfile.TemporaryDirectory()
        self.crawl = Crawl(self.temporary.name, delay=(0, 0))
        self.crawl.log = lambda *args, **kwargs: None

    def tearDown(self):
        self.crawl.close()
        self.temporary.cleanup()
        self.allowed.stop()

    def run_catalog(self, documents, servers=("nanaon",)):
        calls = []

        def request(url):
            calls.append(url)
            self.assertIn(url, documents)
            return 200, {}, encoded(documents[url])

        with patch.object(self.crawl, "request_once", side_effect=request):
            self.crawl.run_group(servers)
        return calls

    def test_numbered_pages_dedup_engine_preserve_difficulties_no_media(self):
        base = SERVERS["nanaon"]
        documents = {
            self.crawl.list_url("nanaon", 0): {
                "pageCount": 2, "items": [item("easy"), item("hard")]},
            self.crawl.list_url("nanaon", 1): {
                "pageCount": 2, "items": [item("expert")]},
            base + "/engine.gz": {"nodes": [], "archetypes": []},
            **{base + "/" + name + ".gz": {"entities": []}
               for name in ("easy", "hard", "expert")},
        }
        calls = self.run_catalog(documents)
        self.assertEqual(len(calls), 6)
        self.assertEqual(calls.count(base + "/engine.gz"), 1)
        self.assertEqual(self.crawl.db.execute("SELECT count(*) FROM charts").fetchone()[0], 3)
        self.assertEqual(self.run_catalog({}), [])
        self.assertFalse(self.crawl.report()["failures"])

    def test_cursor_loop_is_reported_not_repeated_forever(self):
        calls = self.run_catalog({
            self.crawl.list_url("nanaon", 0): {
                "pageCount": -1, "cursor": "next", "items": []},
            self.crawl.list_url("nanaon", 1, "next"): {
                "pageCount": -1, "cursor": "next", "items": []},
        })
        self.assertEqual(len(calls), 2)
        self.assertIn("cursor repeats", self.crawl.report()["failures"][0]["error"])

    def test_cursor_terminal_and_page_count_drift(self):
        self.run_catalog({
            self.crawl.list_url("nanaon", 0): {
                "pageCount": 3, "items": []},
            self.crawl.list_url("nanaon", 1): {
                "pageCount": 2, "items": []},
        })
        self.assertEqual(self.crawl.report()["observed_page_counts"], {"nanaon": [2, 3]})
        self.assertEqual(self.crawl.report()["pagination_changed"], ["nanaon"])

    def test_sources_and_malformed_item_do_not_block_later_pages(self):
        valid = item()
        valid["source"] = "https://levels.example/custom"
        valid["engine"]["source"] = "https://engines.example/custom"
        calls = self.run_catalog({
            self.crawl.list_url("nanaon", 0): {
                "pageCount": 2, "items": [{"name": "broken"}, valid]},
            self.crawl.list_url("nanaon", 1): {"pageCount": 2, "items": []},
            "https://engines.example/custom/engine.gz": {"nodes": []},
            "https://levels.example/custom/song-hard.gz": {"entities": []},
        })
        self.assertEqual(len(calls), 4)
        self.assertEqual(len(self.crawl.report()["item_failures"]), 1)
        self.assertIn(self.crawl.list_url("nanaon", 1), calls)

    def test_same_host_catalogs_alternate(self):
        documents = {}
        for server in ("nanaon", "llsif"):
            for page in range(3):
                documents[self.crawl.list_url(server, page)] = {
                    "pageCount": 3, "items": []}
        calls = self.run_catalog(documents, ("nanaon", "llsif"))
        self.assertEqual(calls, [self.crawl.list_url(server, page)
                                 for page in range(3) for server in ("nanaon", "llsif")])

    def test_hash_verified_cache_reuses_bytes_across_urls_and_restart(self):
        data = encoded({"nodes": []})
        expected = hashlib.sha1(data).hexdigest()
        self.crawl.save_response("https://example.com/old", data, expected)
        self.crawl.close()
        self.crawl = Crawl(self.temporary.name)
        with patch.object(self.crawl, "request_once", side_effect=AssertionError("network")):
            self.assertEqual(self.crawl.fetch("https://example.com/new", expected), data)

    def test_hash_mismatch_not_cached_and_corruption_detected(self):
        with self.assertRaises(RetryRequest):
            self.crawl.save_response("https://example.com/data", b"wrong", "0" * 40)
        self.assertIsNone(self.crawl.cached("https://example.com/data", None))
        self.crawl.save_response("https://example.com/data", b"right", None)
        blob = next((Path(self.temporary.name) / "blobs").iterdir())
        blob.write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "corrupt"):
            self.crawl.cached("https://example.com/data", None)

    def test_concurrent_shared_hash_download_is_single_flight(self):
        data = encoded({"nodes": []})
        expected = hashlib.sha1(data).hexdigest()
        requests, results = [], []

        def request(url):
            requests.append(url)
            time.sleep(0.04)
            return 200, {}, data

        with patch.object(self.crawl, "request_once", side_effect=request):
            workers = [threading.Thread(target=lambda url=url: results.append(
                self.crawl.fetch(url, expected))) for url in (
                    "https://first.example/data", "https://second.example/data")]
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join(timeout=3)
        self.assertEqual(len(requests), 1)
        self.assertEqual(results, [data, data])

    def test_snapshot_hash_change_is_not_silently_deduplicated(self):
        self.crawl.enqueue("nanaon", "engine", "https://example.com/data", "0" * 40)
        with self.assertRaisesRegex(ValueError, "changed"):
            self.crawl.enqueue("nanaon", "engine", "https://example.com/data", "1" * 40)

    def test_exclusive_process_lock(self):
        with self.assertRaisesRegex(RuntimeError, "already owns"):
            Crawl(self.temporary.name)

    def test_retry_is_persisted_and_does_not_hot_loop(self):
        with patch.object(self.crawl, "request_once", side_effect=RetryRequest("busy", 900)):
            original_report = self.crawl.report

            def report_then_stop():
                self.crawl.stop.set()
                return original_report()

            with patch.object(self.crawl, "report", side_effect=report_then_stop):
                self.crawl.run_group(["nanaon"])
        state, tries, ready = self.crawl.db.execute(
            "SELECT state,tries,ready FROM tasks").fetchone()
        self.assertEqual((state, tries), ("pending", 1))
        self.assertGreaterEqual(ready, time.time() + 899)

    def test_due_engine_retry_precedes_new_level_downloads(self):
        base = SERVERS["nanaon"]
        engine_url, level_url = base + "/engine.gz", base + "/level.gz"
        self.crawl.enqueue("nanaon", "engine", engine_url)
        self.crawl.enqueue("nanaon", "level", level_url)
        with self.crawl.db:
            self.crawl.db.execute(
                "UPDATE tasks SET tries=1,ready=? WHERE kind='engine'", (time.time() - 1,))
        page_url = self.crawl.list_url("nanaon", 0)
        calls = self.run_catalog({
            engine_url: {"nodes": []}, level_url: {"entities": []},
            page_url: {"pageCount": 0, "items": []},
        })
        self.assertEqual(calls, [engine_url, page_url, level_url])

    def test_due_level_retry_is_not_starved_by_fresh_levels(self):
        base = SERVERS["nanaon"]
        retry_url, fresh_url = base + "/retry.gz", base + "/fresh.gz"
        self.crawl.enqueue("nanaon", "level", retry_url)
        self.crawl.enqueue("nanaon", "level", fresh_url)
        with self.crawl.db:
            self.crawl.db.execute(
                "UPDATE tasks SET tries=1,ready=? WHERE url=?", (time.time() - 1, retry_url))
        page_url = self.crawl.list_url("nanaon", 0)
        calls = self.run_catalog({
            retry_url: {"entities": []}, fresh_url: {"entities": []},
            page_url: {"pageCount": 0, "items": []},
        })
        self.assertEqual(calls, [page_url, retry_url, fresh_url])

    def test_redirects_pass_through_request_gate(self):
        requests = []

        def request(url):
            requests.append(url)
            return (302, {}, "../blob") if len(requests) == 1 else (200, {}, b"data")

        with patch.object(self.crawl, "request_once", side_effect=request):
            self.assertEqual(self.crawl.fetch("https://example.com/folder/start"), b"data")
        self.assertEqual(requests, ["https://example.com/folder/start", "https://example.com/blob"])

    def test_host_gate_waits_and_never_overlaps(self):
        self.crawl.delay = (0.03, 0.03)
        self.crawl.set_host_ready("example.com", time.time() + 0.03)
        starts, ends = [], []

        class Response:
            status = 200
            headers = {}

            def __enter__(self):
                starts.append(time.time())
                return self

            def __exit__(self, *args):
                ends.append(time.time())

            def read(self, size):
                time.sleep(0.02)
                return b"ok"

        before = time.time()
        with patch.object(self.crawl.opener, "open", side_effect=lambda *a, **kw: Response()):
            workers = [threading.Thread(target=self.crawl.request_once,
                                        args=("https://example.com/data",)) for _ in range(2)]
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join()
        self.assertEqual(len(starts), 2)
        self.assertGreaterEqual(starts[0] - before, 0.025)
        self.assertGreaterEqual(starts[1] - ends[0], 0.025)

    def test_retry_after_reserves_host_for_other_catalogs_and_headers(self):
        error = urllib.error.HTTPError("https://example.com/data", 429, "busy",
                                      {"Retry-After": "900"}, None)
        with patch.object(self.crawl.opener, "open", side_effect=error) as opening:
            with self.assertRaises(RetryRequest) as caught:
                self.crawl.request_once("https://example.com/data")
        self.assertEqual(caught.exception.delay, 900)
        ready = self.crawl.db.execute(
            "SELECT ready FROM hosts WHERE host='example.com'").fetchone()[0]
        self.assertGreaterEqual(ready, time.time() + 899)
        request = opening.call_args.args[0]
        self.assertEqual(request.get_header("Sonolus-version"), "1.1.2")

    def test_different_hosts_can_request_concurrently(self):
        barrier = threading.Barrier(2)
        results = []

        class Response:
            status = 200
            headers = {}

            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

            def read(self, size):
                barrier.wait(timeout=3)
                return b"ok"

        def run(host):
            try:
                results.append(self.crawl.request_once("https://" + host + "/data"))
            except Exception as error:
                results.append(error)

        with patch.object(self.crawl.opener, "open", side_effect=lambda *a, **kw: Response()):
            workers = [threading.Thread(target=run, args=(host,))
                       for host in ("first.example", "second.example")]
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join(timeout=5)
        self.assertEqual(results, [(200, {}, b"ok"), (200, {}, b"ok")])

    def test_request_limit_does_not_allow_extra_network_call(self):
        self.crawl.request_limit = 0
        with patch.object(self.crawl.opener, "open", side_effect=AssertionError("network")):
            with self.assertRaises(InterruptedError):
                self.crawl.request_once("https://example.com/data")

    def test_incomplete_transfer_retries_and_never_caches_partial_bytes(self):
        class Response:
            status = 200
            headers = {}

            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

            def read(self, size):
                raise http.client.IncompleteRead(b"partial", 100)

        with patch.object(self.crawl.opener, "open", return_value=Response()):
            with self.assertRaises(RetryRequest):
                self.crawl.fetch("https://example.com/data")
        self.assertIsNone(self.crawl.cached("https://example.com/data", None))

    def test_unknown_or_loopback_host_never_reaches_network(self):
        with patch.object(self.crawl.opener, "open", side_effect=AssertionError("network")):
            for host in ("localhost.", "unexpected.example", "127.0.0.1.nip.io",
                         "sonolus.milkbun.org."):
                with self.assertRaisesRegex(ValueError, "approved crawl scope"):
                    self.crawl.request_once("https://" + host + "/data")

    def test_short_content_length_body_retries_before_cache_write(self):
        class Response:
            status = 200
            headers = {"Content-Length": "100"}

            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

            def read(self, size):
                return b"partial"

        with patch.object(self.crawl.opener, "open", return_value=Response()):
            with self.assertRaisesRegex(RetryRequest, "Content-Length"):
                self.crawl.fetch("https://example.com/data")
        self.assertIsNone(self.crawl.cached("https://example.com/data", None))

    def test_chunked_takes_precedence_and_oversized_length_is_rejected_early(self):
        class Response:
            status = 200
            headers = {"Content-Length": "100", "Transfer-Encoding": "chunked"}

            def __enter__(self):
                return self

            def __exit__(self, *args):
                pass

            def read(self, size):
                return b"ok"

        with patch.object(self.crawl.opener, "open", return_value=Response()):
            self.assertEqual(self.crawl.fetch("https://example.com/data"), b"ok")
        response = Response()
        response.headers = {"Content-Length": str(128 * 1024 * 1024)}
        with patch.object(self.crawl.opener, "open", return_value=response):
            with patch.object(response, "read", side_effect=AssertionError("body read")):
                with self.assertRaisesRegex(ValueError, "Declared resource size"):
                    self.crawl.fetch("https://example.com/large")

    def test_stack_reachability_includes_all_callbacks_and_orphans(self):
        result = analyze_engine({
            "archetypes": [{"touch": {"index": 0}}, {"initialize": {"index": 4}}],
            "nodes": [{"func": "If", "args": [1, 2]}, {"value": 0},
                      {"func": "StackGet", "args": [1]},
                      {"func": "StackInit", "args": []},
                      {"func": "StackEnter", "args": [99]}],
        })
        self.assertEqual([(x["function"], x["callback_graph_reachable"])
                          for x in result["stack_calls"]],
                         [("StackGet", True), ("StackInit", False), ("StackEnter", True)])
        self.assertEqual(result["invalid_node_references"], [99])

    def test_locator_and_retry_after_and_gzip(self):
        self.assertEqual(resolve(SERVERS["nanaon"], "/sonolus/a"),
                         SERVERS["nanaon"] + "/sonolus/a")
        self.assertEqual(resolve(SERVERS["nanaon"], "https://other.example/a"),
                         "https://other.example/a")
        for invalid in ("file:///etc/passwd", "https://127.0.0.1"):
            with self.assertRaises(ValueError):
                resolve(SERVERS["nanaon"], invalid)
        self.assertEqual(retry_after("120", 0), 120)
        self.assertEqual(retry_after("Thu, 01 Jan 1970 00:02:00 GMT", 30), 90)
        self.assertEqual(retry_after("invalid", 0), 0)
        self.assertEqual(retry_after("inf", 0), 0)
        self.assertEqual(retry_after("nan", 0), 0)
        self.assertEqual(decode_json(encoded({"ok": True})), {"ok": True})

    def test_seed_only_accepts_chart_or_engine_json(self):
        path = Path(self.temporary.name) / "seed.gz"
        data = encoded({"nodes": []})
        path.write_bytes(data)
        self.crawl.seed(path)
        self.assertEqual(self.crawl.cached("https://example.com/engine",
                                         hashlib.sha1(data).hexdigest()), data)
        path.write_bytes(encoded({"sprites": []}))
        with self.assertRaisesRegex(ValueError, "chart data or engine"):
            self.crawl.seed(path)


if __name__ == "__main__":
    unittest.main()
