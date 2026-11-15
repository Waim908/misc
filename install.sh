#!/usr/bin/env bash
# 把 chroot-utils 装到 ~/.local/bin（普通用户目录，不需要 root）。
# 只做复制和加执行权限，不碰 /usr、不写 PATH 文件。
#
# 用法:
#   ./install.sh              装到 ~/.local/bin/chroot-utils
#   PREFIX=/some/where ./install.sh
#   ./install.sh --uninstall  删掉装进去的那份
#   ./install.sh --help

set -euo pipefail

PREFIX="${PREFIX:-${HOME}/.local}"
BINDIR="${PREFIX}/bin"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${HERE}/chroot-utils"
TARGET="${BINDIR}/chroot-utils"

usage() {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1-}" in
    --help | -h)
        usage
        exit 0
        ;;
    --uninstall)
        if [ -e "$TARGET" ]; then
            rm -f -- "$TARGET"
            echo "removed: ${TARGET}"
        else
            echo "not installed: ${TARGET}"
        fi
        exit 0
        ;;
    "")
        ;;
    *)
        echo "error: unknown option $1" >&2
        usage >&2
        exit 1
        ;;
esac

[ -f "$SRC" ] || {
    echo "error: chroot-utils not found next to this script (${SRC})" >&2
    exit 1
}

mkdir -p "$BINDIR"
install -m 0755 "$SRC" "$TARGET"
echo "installed: ${TARGET} ($("$TARGET" --version))"

case ":${PATH}:" in
    *":${BINDIR}:"*) ;;
    *)
        echo "warning: ${BINDIR} is not in PATH, add this to your shell profile:" >&2
        echo "  export PATH=\"${BINDIR}:\$PATH\"" >&2
        ;;
esac
