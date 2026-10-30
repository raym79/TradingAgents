"""Compare the reviewed upstream baseline with remote main and stable release tags."""

import argparse
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "deployment" / "upstream.json"


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def status(fetch: bool = False) -> dict:
    baseline = json.loads(MANIFEST.read_text(encoding="utf-8"))
    # Keep fetch destinations fixed; a manifest edit cannot change the source.
    repository = "https://github.com/TauricResearch/TradingAgents.git"
    if baseline["repository"] != repository or baseline["branch"] != "main":
        raise ValueError("Unexpected upstream repository or branch in manifest")
    if fetch:
        git(
            "fetch", "--no-recurse-submodules", "--tags", repository,
            "+refs/heads/main:refs/remotes/upstream/main",
        )
    installed = git("rev-parse", f"{baseline['commit']}^{{commit}}")
    latest = git("rev-parse", "refs/remotes/upstream/main^{commit}")
    behind = int(git("rev-list", "--count", f"{installed}..{latest}"))
    diverged = int(git("rev-list", "--count", f"{latest}..{installed}")) > 0
    tags = [
        tag for tag in git("tag", "--merged", latest).splitlines()
        if re.fullmatch(r"v\d+\.\d+\.\d+", tag)
    ]
    latest_tag = max(tags, key=lambda tag: tuple(map(int, tag[1:].split(".")))) if tags else None
    return {
        "baseline_version": baseline["version"],
        "baseline_commit": installed,
        "latest_main_commit": latest,
        "commits_available": behind,
        "history_diverged": diverged,
        "latest_stable_tag": latest_tag,
        "comparison": f"https://github.com/TauricResearch/TradingAgents/compare/{installed}...{latest}",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="Refresh remote refs before checking")
    parser.add_argument("--fail-if-behind", action="store_true", help="Exit 1 when updates are available")
    args = parser.parse_args()
    result = status(args.fetch)
    print(json.dumps(result, indent=2))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a", encoding="utf-8") as stream:
            stream.write(
                "## TradingAgents upstream status\n\n"
                f"Reviewed baseline: {result['baseline_version']} (`{result['baseline_commit']}`).\n\n"
                f"Latest stable tag: {result['latest_stable_tag']}. "
                f"Unreviewed main commits: {result['commits_available']}.\n\n"
                f"[Review upstream changes]({result['comparison']})\n"
            )
    if result["history_diverged"]:
        raise SystemExit("Upstream history diverged; inspect the comparison before updating.")
    if args.fail_if_behind and result["commits_available"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
