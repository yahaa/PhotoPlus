package com.yahaa.photoplus

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.yahaa.photoplus.ui.navigation.PhotoPlusNavHost
import com.yahaa.photoplus.ui.theme.PhotoPlusTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            PhotoPlusTheme {
                PhotoPlusNavHost()
            }
        }
    }
}
