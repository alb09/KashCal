package org.onekash.kashcal.ui.components

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import org.onekash.kashcal.R

// The rows rise in after the icon cards have mostly settled, one after another.
private const val ROWS_DELAY_MS = 520L
private const val ROW_STAGGER_MS = 60L
private const val ROW_DURATION_MS = 420
private const val ROW_RISE_DP = 14f

/**
 * Lays out a full-height sheet the way the first-run sheet does: [body] as one group centered in
 * the space above [footer], which stays pinned at the bottom. At large font sizes the group
 * scrolls and the footer stays put.
 */
@Composable
internal fun CenteredSheetLayout(
    footer: @Composable () -> Unit,
    body: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        BoxWithConstraints(modifier = Modifier.weight(1f).fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .heightIn(min = maxHeight)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
                content = body,
            )
        }
        footer()
    }
}

/**
 * Holds one row's icon, its two texts and what a tap does. [opensBrowser] swaps the chevron for
 * the open-in-new glyph and has TalkBack say the row opens the browser.
 */
internal class SheetRowSpec(
    val icon: ImageVector,
    @StringRes val title: Int,
    @StringRes val detail: Int,
    val onClick: () -> Unit,
    val opensBrowser: Boolean = false,
)

/** Shows [rows], rising in one after another once per sheet. */
@Composable
internal fun RisingRows(rows: List<SheetRowSpec>, motionEnabled: Boolean) {
    val progress = rememberEntranceProgress(
        delaysMs = rows.indices.map { ROWS_DELAY_MS + it * ROW_STAGGER_MS },
        durationMs = ROW_DURATION_MS,
        motionEnabled = motionEnabled,
    )
    val risePx = with(LocalDensity.current) { ROW_RISE_DP.dp.toPx() }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEachIndexed { index, row ->
            SheetRow(
                icon = row.icon,
                title = stringResource(row.title),
                detail = stringResource(row.detail),
                onClick = row.onClick,
                opensBrowser = row.opensBrowser,
                modifier = Modifier.graphicsLayer {
                    val t = progress[index].value
                    alpha = t
                    translationY = (1f - t) * risePx
                },
            )
        }
    }
}

/** Shows one tappable row: an icon tile, a title and a detail line. */
@Composable
private fun SheetRow(
    icon: ImageVector,
    title: String,
    detail: String,
    onClick: () -> Unit,
    opensBrowser: Boolean,
    modifier: Modifier = Modifier,
) {
    val opensInBrowser = stringResource(R.string.cd_opens_in_browser)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .clickable(role = Role.Button, onClick = onClick)
            // The open-in-new glyph is the only "leaves the app" cue and TalkBack skips it, so
            // the row's label says it.
            .semantics(mergeDescendants = true) {
                if (opensBrowser) contentDescription = "$title, $detail, $opensInBrowser"
            }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.primaryContainer),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            Text(
                text = detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            imageVector = if (opensBrowser) Icons.AutoMirrored.Filled.OpenInNew
            else Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
