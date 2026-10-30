package org.onekash.kashcal.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests [onboardingCardPose]: each of the icon's three cards starts away from its place and
 * settles exactly on the icon's resting pose.
 */
class OnboardingHeroTest {

    @Test
    fun `every card rests exactly on the icon's pose when its entrance ends`() {
        (0..2).forEach { card ->
            assertEquals("card $card", CardPose.REST, onboardingCardPose(card, progress = 1f))
        }
    }

    @Test
    fun `the back card enters from the right and the middle card from the left`() {
        val back = onboardingCardPose(0, progress = 0f)
        val middle = onboardingCardPose(1, progress = 0f)
        assertTrue(back.translationX > 0f)
        assertTrue(middle.translationX < 0f)
        assertEquals(0f, back.alpha)
        assertEquals(0f, middle.alpha)
    }

    @Test
    fun `the front card rises into place`() {
        val front = onboardingCardPose(2, progress = 0f)
        assertTrue(front.translationY > 0f)
        assertTrue(front.scale < 1f)
        assertEquals(0f, front.translationX)
    }

    @Test
    fun `with motion off the hero starts at its resting pose`() {
        assertEquals(1f, onboardingHeroStartProgress(motionEnabled = false))
        assertEquals(0f, onboardingHeroStartProgress(motionEnabled = true))
    }
}
