package org.onekash.kashcal.ui.screens.settings

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.onekash.kashcal.data.calendar_provider.DeviceCalendar
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Tests the Device calendars screen: its copy, the main switch's state, the hint until a calendar
 * is picked, and the calendar list (tapping a calendar routes its id and new value; no enabled
 * count and no reminders switch, since device reminders are switched in the Calendar
 * notifications sheet). Run the class alone: Robolectric runs of more than one class hit a native
 * crash.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "en-rUS-w360dp-h2000dp-mdpi")
class DeviceCalendarsScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private val calendars = listOf(
        DeviceCalendar(
            id = 100, displayName = "Calendar", color = 0xFF2196F3.toInt(), accountName = "alex@gmail.example",
            accountType = "org.example", visible = true, accessLevel = 700
        ),
        DeviceCalendar(
            id = 101, displayName = "Phone", color = 0xFF607D8B.toInt(), accountName = "",
            accountType = "LOCAL", visible = true, accessLevel = 700
        ),
    )

    private val toggled = mutableListOf<Pair<Long, Boolean>>()

    private fun show(
        isEnabled: Boolean = true,
        hasReadPermission: Boolean = true,
        deviceCalendars: List<DeviceCalendar> = calendars,
        enabledCalendarIds: Set<Long> = setOf(100L),
    ) {
        composeTestRule.setContent {
            MaterialTheme {
                DeviceCalendarsScreen(
                    isEnabled = isEnabled,
                    hasReadPermission = hasReadPermission,
                    deviceCalendars = deviceCalendars,
                    enabledCalendarIds = enabledCalendarIds,
                    onNavigateBack = {},
                    onToggle = {},
                    onToggleCalendar = { id, enabled -> toggled += id to enabled },
                )
            }
        }
    }

    @Test
    fun `the list shows the calendars without an enabled count or a reminders switch`() {
        show()

        composeTestRule.onNodeWithText("Calendar").assertExists()
        composeTestRule.onNodeWithText("Phone").assertExists()
        composeTestRule.onNodeWithText("1 / 2 enabled").assertDoesNotExist()
        composeTestRule.onNodeWithText("Reminders").assertDoesNotExist()
        composeTestRule.onNodeWithText("Get notified for device calendar events").assertDoesNotExist()
    }

    @Test
    fun `tapping a calendar routes its id and new value`() {
        show()

        composeTestRule.onNodeWithText("Phone").performClick()

        assertEquals(listOf(101L to true), toggled)
    }

    @Test
    fun `the screen names the sources and the switch says what it shows`() {
        show()

        composeTestRule.onNodeWithText("Device calendars").assertExists()
        composeTestRule.onNodeWithText(
            "Show calendars from Google, Outlook, and sync apps on this device."
        ).assertExists()
        composeTestRule.onNodeWithText("Show device calendars").assertExists()
        composeTestRule.onNodeWithTag(DEVICE_CALENDARS_SWITCH_TAG).assertIsOn()
    }

    @Test
    fun `the switch shows off while calendar access is missing`() {
        show(isEnabled = true, hasReadPermission = false)

        composeTestRule.onNodeWithTag(DEVICE_CALENDARS_SWITCH_TAG).assertIsOff()
        composeTestRule.onNodeWithText("Calendar permission required. Tap Enable to grant access.")
            .assertDoesNotExist()
    }

    @Test
    fun `the pick hint shows until a calendar is picked`() {
        show(enabledCalendarIds = emptySet())

        composeTestRule.onNodeWithText("Pick calendars to show.").assertExists()
    }

    @Test
    fun `the pick hint is gone once a calendar is picked`() {
        show(enabledCalendarIds = setOf(101L))

        composeTestRule.onNodeWithText("Pick calendars to show.").assertDoesNotExist()
    }

    @Test
    fun `an empty list says nothing was found`() {
        show(deviceCalendars = emptyList(), enabledCalendarIds = emptySet())

        composeTestRule.onNodeWithText("No calendars found.").assertExists()
        composeTestRule.onNodeWithText("Pick calendars to show.").assertDoesNotExist()
    }

    @Test
    fun `there is no view-only row and no permission read-only label`() {
        show()

        composeTestRule.onNodeWithText("Read-only access").assertDoesNotExist()
        composeTestRule.onNodeWithText("Read only (no write permission)").assertDoesNotExist()
    }

    @Test
    fun `a read-only calendar is labelled as such`() {
        val readOnly = calendars[0].copy(accessLevel = 200)
        show(deviceCalendars = listOf(readOnly))

        composeTestRule.onNodeWithText("Read only (calendar is read-only)").assertExists()
    }
}
