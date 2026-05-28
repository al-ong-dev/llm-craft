#!/usr/bin/env python3
"""
Daily Copilot browser automation via Playwright (Python).

This script is intentionally selector-configurable because Copilot web UI
selectors can change over time.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from playwright.sync_api import Page, TimeoutError as PlaywrightTimeoutError, sync_playwright


DEFAULT_CONFIG = {
    "target_url": "https://github.com/copilot",
    "selectors": {
        "input": "textarea, [contenteditable='true']",
        "send_button": "button:has-text('Send'), button[aria-label*='Send']",
        "response_blocks": "[data-testid*='message'], .markdown-body, article",
        "done_hint": "button:has-text('Stop generating'), button:has-text('Stop')",
    },
    "timing": {
        "navigation_timeout_ms": 60000,
        "response_timeout_ms": 180000,
        "settle_ms": 2000,
        "poll_interval_ms": 1000,
    },
}


@dataclass
class PromptTask:
    name: str
    prompt: str
    page_url: str | None = None


def load_json(path: pathlib.Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: pathlib.Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")


def read_tasks(path: pathlib.Path) -> list[PromptTask]:
    raw = load_json(path)
    tasks_raw = raw.get("tasks", [])
    tasks: list[PromptTask] = []
    for idx, item in enumerate(tasks_raw, start=1):
        prompt = str(item.get("prompt", "")).strip()
        if not prompt:
            continue
        name = str(item.get("name", f"task-{idx}")).strip() or f"task-{idx}"
        page_url = item.get("page_url")
        tasks.append(PromptTask(name=name, prompt=prompt, page_url=page_url))
    return tasks


def wait_for_manual_login(page: Page, timeout_ms: int) -> None:
    print("Waiting for authenticated Copilot page. Complete login manually if prompted...")
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    while time.monotonic() < deadline:
        url = page.url.lower()
        if "github.com/session" not in url and "login" not in url:
            return
        time.sleep(1.0)
    raise RuntimeError("Timed out waiting for manual login.")


def extract_latest_response(page: Page, response_selector: str) -> str:
    blocks = page.locator(response_selector)
    count = blocks.count()
    if count == 0:
        return ""
    text = blocks.nth(count - 1).inner_text().strip()
    return re.sub(r"\n{3,}", "\n\n", text)


def submit_prompt(page: Page, prompt: str, selectors: dict[str, str]) -> None:
    input_locator = page.locator(selectors["input"]).first
    input_locator.wait_for(state="visible")
    input_locator.click()
    input_locator.fill(prompt)

    send = page.locator(selectors["send_button"]).first
    if send.count() > 0:
        send.click()
    else:
        input_locator.press("Control+Enter")


def wait_for_response_complete(page: Page, selectors: dict[str, str], timing: dict[str, int]) -> str:
    timeout_ms = int(timing["response_timeout_ms"])
    poll_ms = int(timing["poll_interval_ms"])
    settle_ms = int(timing["settle_ms"])

    deadline = time.monotonic() + (timeout_ms / 1000.0)
    last_text = ""
    unchanged_since: float | None = None

    while time.monotonic() < deadline:
        text = extract_latest_response(page, selectors["response_blocks"])
        generating = page.locator(selectors["done_hint"]).first.count() > 0

        if text != last_text:
            last_text = text
            unchanged_since = time.monotonic()
        else:
            if unchanged_since is None:
                unchanged_since = time.monotonic()

        stable_for_ms = 0 if unchanged_since is None else int((time.monotonic() - unchanged_since) * 1000)

        if text and (not generating) and stable_for_ms >= settle_ms:
            return text

        time.sleep(poll_ms / 1000.0)

    raise PlaywrightTimeoutError("Timed out waiting for Copilot response completion.")


def run(args: argparse.Namespace) -> int:
    config_path = pathlib.Path(args.config).resolve()
    prompts_path = pathlib.Path(args.prompts).resolve()
    out_path = pathlib.Path(args.output).resolve()
    user_data_dir = pathlib.Path(args.user_data_dir).resolve()

    config = DEFAULT_CONFIG.copy()
    if config_path.exists():
        user_config = load_json(config_path)
        config = {
            **config,
            **user_config,
            "selectors": {**DEFAULT_CONFIG["selectors"], **user_config.get("selectors", {})},
            "timing": {**DEFAULT_CONFIG["timing"], **user_config.get("timing", {})},
        }

    tasks = read_tasks(prompts_path)
    if not tasks:
        print("No tasks found in prompts file.", file=sys.stderr)
        return 1

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    results: list[dict[str, Any]] = []

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(user_data_dir),
            headless=args.headless,
            viewport={"width": 1400, "height": 1000},
        )
        page = context.new_page()
        page.set_default_timeout(int(config["timing"]["navigation_timeout_ms"]))

        base_url = config["target_url"]
        page.goto(base_url, wait_until="domcontentloaded")
        wait_for_manual_login(page, int(config["timing"]["navigation_timeout_ms"]))

        for task in tasks:
            target = task.page_url or base_url
            print(f"Running task: {task.name} -> {target}")
            page.goto(target, wait_until="domcontentloaded")
            wait_for_manual_login(page, int(config["timing"]["navigation_timeout_ms"]))

            started = datetime.now(timezone.utc).isoformat()
            try:
                submit_prompt(page, task.prompt, config["selectors"])
                response = wait_for_response_complete(page, config["selectors"], config["timing"])
                status = "ok"
                error = ""
            except Exception as exc:  # broad for robust daily automation
                response = ""
                status = "error"
                error = str(exc)

            ended = datetime.now(timezone.utc).isoformat()
            result = {
                "name": task.name,
                "page_url": target,
                "status": status,
                "started_at": started,
                "ended_at": ended,
                "prompt": task.prompt,
                "response": response,
                "error": error,
            }
            results.append(result)

            if status != "ok":
                screenshot = out_path.parent / f"{run_id}-{task.name}-error.png"
                page.screenshot(path=str(screenshot), full_page=True)

        context.close()

    payload = {
        "run_id": run_id,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "task_count": len(tasks),
        "results": results,
    }
    save_json(out_path, payload)
    print(f"Wrote results to: {out_path}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Daily Copilot browser automation with Playwright.")
    parser.add_argument("--prompts", default="./copilot-prompts.json", help="JSON file with prompt tasks")
    parser.add_argument("--config", default="./copilot-config.json", help="JSON config with selectors/timing")
    parser.add_argument("--output", default="./runs/copilot-results.json", help="Output JSON file path")
    parser.add_argument("--user-data-dir", default="./.pw-user-data", help="Persistent browser profile directory")
    parser.add_argument("--headless", action="store_true", help="Run browser headless")
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(run(parse_args()))
