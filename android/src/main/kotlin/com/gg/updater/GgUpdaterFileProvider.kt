package com.gg.updater

import androidx.core.content.FileProvider

/// Own FileProvider subclass to avoid manifest conflicts with other plugins
/// that also declare androidx.core.content.FileProvider.
class GgUpdaterFileProvider : FileProvider()
