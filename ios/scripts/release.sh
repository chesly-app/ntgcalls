#!/usr/bin/env bash
# iOS port (Chesly fork, 2026-11).
#
# Draft releases as the store for iOS build outputs: the deps bundle and each framework build.
# Drafts are visible to the repository's writers only, and GITHUB_TOKEN with contents: write can
# read and write them. Needs GH_TOKEN and GITHUB_REPOSITORY in the environment.
#
#   release.sh ensure <tag> <title> <notes file>   prints the draft's id, creating it if needed
#   release.sh asset-id <tag> <name>                prints the asset's id, or nothing
#   release.sh upload <tag> <file> [name]           replaces an asset of that name
#   release.sh download <tag> <name> <output>       fails if there is no such asset
set -euo pipefail

api="https://api.github.com/repos/${GITHUB_REPOSITORY}"
auth=(-H "Authorization: Bearer ${GH_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28")

release_json() {
    # Drafts have no tag yet, so they are found by listing, not by /releases/tags/<tag>.
    local page=1
    while :; do
        local body
        body="$(curl -fsS "${auth[@]}" "${api}/releases?per_page=100&page=${page}")"
        local found
        found="$(echo "$body" | jq -c --arg tag "$1" '[.[] | select(.tag_name == $tag)][0] // empty')"
        if [ -n "$found" ]; then
            echo "$found"
            return
        fi
        [ "$(echo "$body" | jq 'length')" -lt 100 ] && return
        page=$((page + 1))
    done
}

case "$1" in
    ensure)
        found="$(release_json "$2")"
        if [ -n "$found" ]; then
            id="$(echo "$found" | jq -r .id)"
            jq -n --arg name "$3" --rawfile body "$4" '{name: $name, body: $body}' \
                | curl -fsS "${auth[@]}" -X PATCH "${api}/releases/${id}" --data @- >/dev/null
            echo "$id"
        else
            jq -n --arg tag "$2" --arg name "$3" --rawfile body "$4" --arg target "${GITHUB_SHA:-}" \
                '{tag_name: $tag, name: $name, body: $body, draft: true, prerelease: true}
                 + (if $target == "" then {} else {target_commitish: $target} end)' \
                | curl -fsS "${auth[@]}" -X POST "${api}/releases" --data @- | jq -r .id
        fi
        ;;
    asset-id)
        release_json "$2" | jq -r --arg name "$3" '.assets[]? | select(.name == $name) | .id'
        ;;
    upload)
        name="${4:-$(basename "$3")}"
        # A draft made a moment ago can take a few seconds to reach the listing.
        found=""
        for _ in 1 2 3 4 5 6 7 8; do
            found="$(release_json "$2")"
            [ -n "$found" ] && break
            sleep 5
        done
        [ -n "$found" ] || { echo "no release $2" >&2; exit 1; }
        id="$(echo "$found" | jq -r .id)"
        old="$(echo "$found" | jq -r --arg name "$name" '.assets[]? | select(.name == $name) | .id')"
        if [ -n "$old" ]; then
            curl -fsS "${auth[@]}" -X DELETE "${api}/releases/assets/${old}"
        fi
        curl -fsS "${auth[@]}" -H "Content-Type: application/octet-stream" --data-binary @"$3" \
            "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${id}/assets?name=${name}" >/dev/null
        echo "uploaded $name to $2"
        ;;
    download)
        asset="$("$0" asset-id "$2" "$3")"
        [ -n "$asset" ] || { echo "no asset $3 in $2" >&2; exit 1; }
        curl -fsSL "${auth[@]}" -H "Accept: application/octet-stream" -o "$4" "${api}/releases/assets/${asset}"
        ;;
    *)
        echo "unknown command $1" >&2
        exit 1
        ;;
esac
