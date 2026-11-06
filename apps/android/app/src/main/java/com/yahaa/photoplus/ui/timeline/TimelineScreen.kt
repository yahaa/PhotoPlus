package com.yahaa.photoplus.ui.timeline

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yahaa.photoplus.ui.upload.UploadQueueCard

/**
 * Photos-like rolling timeline. TODO: MediaStore placeholders + NAS originals.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimelineScreen() {
    Scaffold(
        topBar = { TopAppBar(title = { Text("PhotoPlus") }) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Timeline placeholder",
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                "Local MediaStore thumbs stay on device; older originals archive to NAS.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            UploadQueueCard()
        }
    }
}
