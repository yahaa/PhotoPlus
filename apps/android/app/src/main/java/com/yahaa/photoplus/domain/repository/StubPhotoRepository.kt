package com.yahaa.photoplus.domain.repository

import com.yahaa.photoplus.domain.model.PhotoItem

class StubPhotoRepository : PhotoRepository {
    override suspend fun timeline(): List<PhotoItem> = emptyList()
}
