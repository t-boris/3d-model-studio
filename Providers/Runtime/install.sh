#!/bin/bash
# Invoked by Settings in a new, private staging directory with a clean environment.
set -euo pipefail
umask 077
provider=$1
resources=$2
arch=$3
case "$arch" in
    arm64) triple=aarch64-apple-darwin ;;
    x86_64) triple=x86_64-apple-darwin ;;
    *) exit 10 ;;
esac

# Pinned npm SHA-512 (base64) or CPython release SHA-256 (hex).
url=""
while IFS=$'\t' read -r name platform source checksum; do
    if [[ "$provider" == "$name" && "$arch" == "$platform" ]]; then
        url=$source
        expected=$checksum
        break
    fi
done < "$resources/artifacts.tsv"
[[ -n "$url" ]] || exit 10

/usr/bin/curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 30 --max-time 600 --retry 2 --output archive "$url" || exit 11
if [[ "$provider" == Antigravity ]]; then
    actual=$(/usr/bin/shasum -a 256 archive)
    [[ "${actual%% *}" == "$expected" ]] || exit 12
else
    actual=$(/usr/bin/openssl dgst -sha512 -binary archive | /usr/bin/base64)
    [[ "$actual" == "$expected" ]] || exit 12
fi

case "$provider" in
    Codex)
        /usr/bin/tar -xzf archive "package/vendor/$triple"
        /bin/mv "package/vendor/$triple" native ;;
    Claude)
        /usr/bin/tar -xzf archive package/claude
        /bin/mv package/claude claude ;;
    Antigravity)
        /usr/bin/tar -xzf archive
        python/bin/python3 -I -m pip --isolated --disable-pip-version-check install \
            --no-cache-dir --no-compile --no-index --no-deps --require-hashes --only-binary=:all: \
            -r "$resources/requirements-$arch.txt" || exit 13
        /bin/cp "$resources/antigravity.py" antigravity.py ;;
esac
/bin/rm archive
