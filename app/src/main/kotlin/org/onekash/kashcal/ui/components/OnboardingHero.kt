package org.onekash.kashcal.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.vectorResource
import androidx.compose.ui.graphics.vector.Group
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.RenderVectorGroup
import androidx.compose.ui.graphics.vector.VectorConfig
import androidx.compose.ui.graphics.vector.VectorGroup
import androidx.compose.ui.graphics.vector.VectorProperty
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.onekash.kashcal.ui.appicon.DayIcons
import java.time.LocalDate

/** Holds one icon card's offset from its resting place, in the icon's 88-unit viewport. */
internal data class CardPose(
    val translationX: Float,
    val translationY: Float,
    val rotation: Float,
    val scale: Float,
    val alpha: Float,
) {
    companion object {
        /** The card exactly where the launcher icon draws it. */
        val REST = CardPose(
            translationX = 0f,
            translationY = 0f,
            rotation = 0f,
            scale = 1f,
            alpha = 1f,
        )
    }
}

// Where each card starts, in the icon's drawing order: the back card from the right, the middle
// one from the left, the front (dated) card rising from below.
private val START_POSES = listOf(
    CardPose(translationX = 40f, translationY = 6f, rotation = 18f, scale = 1f, alpha = 0f),
    CardPose(translationX = -40f, translationY = 6f, rotation = -18f, scale = 1f, alpha = 0f),
    CardPose(translationX = 0f, translationY = 26f, rotation = 0f, scale = 0.9f, alpha = 0f),
)
private val CARD_DELAYS_MS = listOf(120L, 220L, 340L)
private const val CARD_DURATION_MS = 700

/** The entrance curve: a quick start that eases gently into place. */
internal val OnboardingEntranceEasing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)

/** Returns card [card]'s pose at [progress] (0 = start, 1 = [CardPose.REST]). */
internal fun onboardingCardPose(card: Int, progress: Float): CardPose {
    val start = START_POSES[card]
    val end = CardPose.REST
    val t = progress.coerceIn(0f, 1f)
    fun lerp(from: Float, to: Float) = from + (to - from) * t
    return CardPose(
        translationX = lerp(start.translationX, end.translationX),
        translationY = lerp(start.translationY, end.translationY),
        rotation = lerp(start.rotation, end.rotation),
        scale = lerp(start.scale, end.scale),
        alpha = lerp(start.alpha, end.alpha),
    )
}

/**
 * Returns where an entrance starts, from [initialHeroPhase]: at the beginning, or with motion off
 * already at rest.
 */
internal fun onboardingHeroStartProgress(motionEnabled: Boolean): Float =
    if (initialHeroPhase(motionEnabled) == HeroPhase.END) 1f else 0f

/**
 * Returns one progress value per entry of [delaysMs], each going from 0 to 1 over [durationMs]
 * after its delay. It plays once per sheet: a rotation mid-entrance shows the end, not a replay,
 * and with motion off every value starts at 1.
 */
@Composable
internal fun rememberEntranceProgress(
    delaysMs: List<Long>,
    durationMs: Int,
    motionEnabled: Boolean,
): List<Animatable<Float, AnimationVector1D>> {
    var played by rememberSaveable { mutableStateOf(false) }
    val start = if (played) 1f else onboardingHeroStartProgress(motionEnabled)
    val progress = remember { List(delaysMs.size) { Animatable(start) } }
    LaunchedEffect(Unit) {
        if (played || !motionEnabled) return@LaunchedEffect
        played = true
        progress.forEachIndexed { index, value ->
            launch {
                delay(delaysMs[index])
                value.animateTo(1f, tween(durationMs, easing = OnboardingEntranceEasing))
            }
        }
    }
    return progress
}

/** Returns whether entrances move, read once: false with "Remove animations" on. */
@Composable
internal fun rememberHeroMotionEnabled(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return remember(resolver) { heroMotionEnabled(resolver) }
}

/** Multiplies each path's own fill alpha by [alpha]; every other property keeps its value. */
private class CardFade(private val alpha: Float) : VectorConfig {
    @Suppress("UNCHECKED_CAST")
    override fun <T> getOrDefault(property: VectorProperty<T>, defaultValue: T): T =
        if (property == VectorProperty.FillAlpha) {
            ((defaultValue as Float) * alpha) as T
        } else {
            defaultValue
        }
}

/**
 * Draws the launcher icon's three stacked calendar cards with today's date and fans them in
 * once per sheet, settling on the icon's own pose. Decorative: it has no content description.
 *
 * The cards are the top-level groups of [DayIcons.foregroundFor] (`DayIconsTest` checks there are
 * three). If a foreground ever has another shape, the static icon shows instead.
 */
@Composable
fun OnboardingHero(
    motionEnabled: Boolean,
    modifier: Modifier = Modifier,
) {
    val foreground = remember { DayIcons.foregroundFor(LocalDate.now().dayOfMonth) }
    val image = ImageVector.vectorResource(foreground)
    val cards = remember(image) { image.root.filterIsInstance<VectorGroup>() }
    if (cards.size != START_POSES.size) {
        Image(painterResource(foreground), contentDescription = null, modifier = modifier)
        return
    }

    val progress = rememberEntranceProgress(CARD_DELAYS_MS, CARD_DURATION_MS, motionEnabled)

    val painter = rememberVectorPainter(
        defaultWidth = image.defaultWidth,
        defaultHeight = image.defaultHeight,
        viewportWidth = image.viewportWidth,
        viewportHeight = image.viewportHeight,
        autoMirror = false,
    ) { viewportWidth, viewportHeight ->
        cards.forEachIndexed { index, card ->
            val pose = onboardingCardPose(index, progress[index].value)
            Group(
                pivotX = viewportWidth / 2,
                pivotY = viewportHeight / 2,
                rotation = pose.rotation,
                scaleX = pose.scale,
                scaleY = pose.scale,
                translationX = pose.translationX,
                translationY = pose.translationY,
            ) {
                // RenderVectorGroup draws a group's children only, so the card's own placement
                // in the icon is applied here.
                Group(
                    rotation = card.rotation,
                    pivotX = card.pivotX,
                    pivotY = card.pivotY,
                    scaleX = card.scaleX,
                    scaleY = card.scaleY,
                    translationX = card.translationX,
                    translationY = card.translationY,
                    clipPathData = card.clipPathData,
                ) {
                    // The icon's paths have no names, so their config key is "".
                    RenderVectorGroup(card, configs = mapOf("" to CardFade(pose.alpha)))
                }
            }
        }
    }
    Image(painter, contentDescription = null, modifier = modifier)
}
