package com.yahaa.photoplus.domain.model

/** Timeline item: local cache and/or NAS object. */
data class PhotoItem(
    val id: String,
    val takenAtEpochMs: Long,
    val isLocalOriginalPresent: Boolean,
    val nasObjectKey: String? = null,
)
