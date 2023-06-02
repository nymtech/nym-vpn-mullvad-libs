package net.mullvad.mullvadvpn.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import net.mullvad.mullvadvpn.compose.state.SettingsUiState
import net.mullvad.mullvadvpn.lib.theme.DarkThemeState
import net.mullvad.mullvadvpn.lib.theme.ThemeRepository
import net.mullvad.mullvadvpn.model.DeviceState
import net.mullvad.mullvadvpn.repository.DeviceRepository
import net.mullvad.mullvadvpn.ui.serviceconnection.ServiceConnectionManager

class SettingsViewModel(
    deviceRepository: DeviceRepository,
    serviceConnectionManager: ServiceConnectionManager,
    private val themeRepository: ThemeRepository,
    isPlayBuild: Boolean
) : ViewModel() {

    val uiState: StateFlow<SettingsUiState> =
        combine(
                deviceRepository.deviceState,
                serviceConnectionManager.connectionState,
                themeRepository.useMaterialYouTheme(),
                themeRepository.useDarkTheme(),
            ) { deviceState, versionInfo, useMaterialYouTheme, darkThemeState ->
                val cachedVersionInfo = versionInfo.readyContainer()?.appVersionInfoCache
                SettingsUiState(
                    isLoggedIn = deviceState is DeviceState.LoggedIn,
                    appVersion = cachedVersionInfo?.version ?: "",
                    isUpdateAvailable =
                        cachedVersionInfo?.let { it.isSupported.not() || it.isOutdated } ?: false,
                    isPlayBuild = isPlayBuild,
                    isMaterialYouTheme = useMaterialYouTheme,
                    darkThemeState = darkThemeState
                )
            }
            .stateIn(
                viewModelScope,
                SharingStarted.WhileSubscribed(),
                SettingsUiState(
                    appVersion = "",
                    isLoggedIn = false,
                    isUpdateAvailable = false,
                    isPlayBuild = isPlayBuild,
                    isMaterialYouTheme = false,
                    darkThemeState = DarkThemeState.ON
                )
            )

    fun setUseMaterialYouTheme(useMaterialYouTheme: Boolean) {
        viewModelScope.launch { themeRepository.setUseMaterialYouTheme(useMaterialYouTheme) }
    }

    fun onDarkThemeStateSelected(darkThemeState: DarkThemeState) {
        viewModelScope.launch { themeRepository.setUseDarkTheme(darkThemeState) }
    }
}
