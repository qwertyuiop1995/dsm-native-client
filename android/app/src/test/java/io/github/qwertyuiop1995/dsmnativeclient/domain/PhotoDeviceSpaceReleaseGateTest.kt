package io.github.qwertyuiop1995.dsmnativeclient.domain

import org.junit.Assert.assertEquals
import org.junit.Test

class PhotoDeviceSpaceReleaseGateTest {
    @Test
    fun `五项门禁穷举中只有全部满足才允许释放设备空间`() {
        val conditionCount = 5
        val allConditionsSatisfied = (1 shl conditionCount) - 1

        for (mask in 0..allConditionsSatisfied) {
            val conditions = PhotoDeviceSpaceReleaseConditions(
                isEveryNasItemReadBackConfirmed = mask.hasBit(0),
                isBackupStateStable = mask.hasBit(1),
                hasUserSecondConfirmation = mask.hasBit(2),
                isBehaviorEnabled = mask.hasBit(3),
                canDeleteDeviceMedia = mask.hasBit(4),
            )

            assertEquals(
                "门禁组合 $mask 的结果不符合 fail-closed 规则",
                mask == allConditionsSatisfied,
                conditions.allowsDeviceSpaceRelease(),
            )
        }
    }

    private fun Int.hasBit(index: Int): Boolean = this and (1 shl index) != 0
}
