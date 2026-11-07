#!/usr/bin/env bash
# iOS port (Chesly fork, 2026-11).
#
# Draft releases as the store for iOS build outputs: the deps bundle and each framework build.
# Drafts are visible to the repository's writers only, and GITHUB_TOKEN with contents: write can
# read and write them. Needs GH_TOKEN and GITHUB_REPOSITORY in the environment.
#
# A draft's tag_name is not stable (GitHub reports untagged-... for it), so a draft is found by
# its title, which is always the tag it will take.
#
#   release.sh ensure <tag> <notes file>     prints the draft's id, creating it if needed
#   release.sh asset-id <tag> <name>         prints the asset's id, or nothing
#   release.sh upload <tag> <file> [name]    replaces an asset of that name
#   release.sh download <tag> <name> <output>  fails if there is no such asset
#   release.sh keep <commit>                 tags the commit ios-build-<first 12 hex digits>
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
        found="$(echo "$body" | jq -c --arg tag "$1" '[.[] | select(.name == $tag)][0] // empty')"
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
            # The target moves with each build, so publishing the draft tags the commit it holds.
            jq -n --arg tag "$2" --rawfile body "$3" --arg target "${GITHUB_SHA:-}" \
                '{tag_name: $tag, body: $body}
                 + (if $target == "" then {} else {target_commitish: $target} end)' \
                | curl -fsS "${auth[@]}" -X PATCH "${api}/releases/${id}" --data @- >/dev/null
            echo "$id"
        else
            jq -n --arg tag "$2" --rawfile body "$3" --arg target "${GITHUB_SHA:-}" \
                '{tag_name: $tag, name: $tag, body: $body, draft: true, prerelease: true}
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
    keep)
        # SOURCE.txt in a published framework names its commit as the LGPL corresponding source.
        # A tag keeps that commit reachable whatever later happens to the branch.
        ref="tags/ios-build-${2:0:12}"
        have="$(curl -fsS "${auth[@]}" "${api}/git/ref/${ref}" 2>/dev/null | jq -r '.object.sha // empty' || true)"
        if [ -z "$have" ]; then
            jq -n --arg ref "refs/${ref}" --arg sha "$2" '{ref: $ref, sha: $sha}' \
                | curl -fsS "${auth[@]}" -X POST "${api}/git/refs" --data @- >/dev/null
        elif [ "$have" != "$2" ]; then
            echo "${ref} names ${have}, not $2" >&2
            exit 1
        fi
        echo "kept $2 as ${ref}"
        ;;
    *)
        echo "unknown command $1" >&2
        exit 1
        ;;
esac
