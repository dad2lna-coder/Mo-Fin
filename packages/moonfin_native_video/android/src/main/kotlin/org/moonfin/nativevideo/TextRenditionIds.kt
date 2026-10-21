package org.moonfin.nativevideo

import androidx.media3.common.TrackGroup
import androidx.media3.common.util.UnstableApi

/**
 * Identity of an HLS text rendition (WebVTT and the like), as opposed to a
 * CEA-608 caption. The id is the group key plus the index inside that group.
 * A flattened position would point at a different track the next time the
 * player rebuilt its groups, so selection looks the key up again.
 *
 * The same encoding lives in playback_core as [textRenditionId]. A group id
 * from HLS often contains colons, so the key is length-prefixed.
 */
@UnstableApi
internal object TextRenditionIds {
    fun groupKey(group: TrackGroup): String {
        if (group.id.isNotEmpty()) return group.id
        val format = if (group.length > 0) group.getFormat(0) else null
        return "fallback:${format?.id ?: ""}:${format?.language ?: ""}:${format?.sampleMimeType ?: ""}"
    }

    fun id(group: TrackGroup, trackIndex: Int): String {
        val key = groupKey(group)
        return idForKey(key, trackIndex)
    }

    fun idForKey(groupKey: String, trackIndex: Int): String =
        "${groupKey.length}:$groupKey:$trackIndex"

    fun parse(id: String): Pair<String, Int>? {
        val separator = id.indexOf(':')
        if (separator <= 0) return null
        val length = id.substring(0, separator).toIntOrNull() ?: return null
        if (length < 0) return null
        val keyStart = separator + 1
        val keyEnd = keyStart + length
        if (keyEnd >= id.length || id[keyEnd] != ':') return null
        val key = id.substring(keyStart, keyEnd)
        val index = id.substring(keyEnd + 1).toIntOrNull() ?: return null
        if (index < 0) return null
        return key to index
    }

    fun languageMatches(track: String?, preferred: String): Boolean {
        if (track.isNullOrBlank() || preferred.isBlank()) return false
        val left = track.trim().lowercase()
        val right = preferred.trim().lowercase()
        if (left == "und" || right == "und") return false
        return left == right || left.startsWith(right) || right.startsWith(left)
    }

    fun choose(languagesById: List<Pair<String, String>>, preferred: String): String? {
        val language = preferred.ifBlank { "en" }
        return languagesById.firstOrNull { languageMatches(it.second, language) }?.first
    }
}
