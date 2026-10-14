#!/bin/sh
# Xcode passes resolved xcconfig values as environment variables to this phase.
# An archive without either backend looks healthy until every network action fails.
set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
    exit 0
fi

validate_host() {
    name=$1
    value=$2
    case "$value" in
        https://* ) ;;
        * ) echo "error: $name must be a deployed HTTPS URL for Release. Set it in Roam/Config/Release.local.xcconfig or the build environment." >&2; exit 1 ;;
    esac
    authority=${value#https://}
    authority=${authority%%/*}
    case "$authority" in
        ""|localhost|localhost:*|127.0.0.1|127.0.0.1:*|*YOUR_*|*'$('*|*' '* )
            echo "error: $name has an invalid or placeholder Release host." >&2
            exit 1
            ;;
    esac
}

validate_host API_BASE_URL "${API_BASE_URL:-}"
validate_host DATA_API_BASE_URL "${DATA_API_BASE_URL:-}"
