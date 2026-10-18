#!/usr/bin/env bash
# Đẩy BolaClone lên GitHub rồi lấy IPA từ workflow macOS.
#
#   gh auth login          # một lần, tài khoản GitHub của bạn
#   ./tools/make_ipa_via_github.sh [ten-repo]
#
# Kết quả: build/BolaClone-unsigned-ipa/BolaClone-unsigned.ipa
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${1:-bola-clone-ipa}"

if ! command -v gh >/dev/null 2>&1; then
  echo "!! cần GitHub CLI: https://cli.github.com/" >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "!! chưa đăng nhập. Chạy: gh auth login" >&2
  exit 1
fi

if [ ! -d .git ]; then
  git init -b main
fi
git add -A
git commit -m "BolaClone: build IPA" >/dev/null 2>&1 || true

if ! git remote get-url origin >/dev/null 2>&1; then
  gh repo create "$REPO" --private --source=. --remote=origin --push
else
  git push -u origin HEAD
fi

echo "[*] chờ workflow…"
sleep 5
run_id="$(gh run list --workflow=build-ipa.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
[ -n "$run_id" ] || { echo "!! không thấy run nào" >&2; exit 1; }
gh run watch "$run_id" --interval 15 --exit-status

rm -rf build/BolaClone-unsigned-ipa
gh run download "$run_id" -n BolaClone-unsigned-ipa -D build/BolaClone-unsigned-ipa
echo "[+] IPA: $(find build/BolaClone-unsigned-ipa -name '*.ipa' | head -1)"
