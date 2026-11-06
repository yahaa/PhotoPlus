package com.yahaa.photoplus.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.yahaa.photoplus.ui.devices.DevicesScreen
import com.yahaa.photoplus.ui.settings.SettingsScreen
import com.yahaa.photoplus.ui.timeline.TimelineScreen

private enum class TopDest(
    val route: String,
    val label: String,
    val icon: ImageVector,
) {
    Timeline("timeline", "Timeline", Icons.Outlined.PhotoLibrary),
    Devices("devices", "Devices", Icons.Outlined.Devices),
    Settings("settings", "Settings", Icons.Outlined.Settings),
}

@Composable
fun PhotoPlusNavHost() {
    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val current = backStack?.destination

    Scaffold(
        bottomBar = {
            NavigationBar {
                TopDest.entries.forEach { dest ->
                    NavigationBarItem(
                        selected = current?.hierarchy?.any { it.route == dest.route } == true,
                        onClick = {
                            navController.navigate(dest.route) {
                                popUpTo(navController.graph.startDestinationId) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Icon(dest.icon, contentDescription = dest.label) },
                        label = { Text(dest.label) },
                    )
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = TopDest.Timeline.route,
            modifier = Modifier.padding(padding),
        ) {
            composable(TopDest.Timeline.route) { TimelineScreen() }
            composable(TopDest.Devices.route) { DevicesScreen() }
            composable(TopDest.Settings.route) { SettingsScreen() }
        }
    }
}
