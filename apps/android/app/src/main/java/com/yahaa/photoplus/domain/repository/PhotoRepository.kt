package com.yahaa.photoplus.domain.repository

import com.yahaa.photoplus.domain.model.PhotoItem

interface PhotoRepository {
    suspend fun timeline(): List<PhotoItem>
}
