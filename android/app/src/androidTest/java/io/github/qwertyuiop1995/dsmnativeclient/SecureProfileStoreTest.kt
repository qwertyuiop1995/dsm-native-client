package io.github.qwertyuiop1995.dsmnativeclient

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.storage.SecureProfileStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SecureProfileStoreTest {
    private val store = SecureProfileStore(ApplicationProvider.getApplicationContext())

    @After
    fun cleanup() {
        store.clearAll()
    }

    @Test
    fun passwordAndAutoLoginAreProtectedPerProfile() {
        val profile = NasProfile(
            id = "secure-store-test",
            name = "测试 NAS",
            address = "test-nas",
            username = "tester",
        )

        store.saveProfile(profile)
        store.savePassword(profile.id, "test-password")
        store.setAutoLoginEnabled(profile.id, true)
        store.setLastProfileId(profile.id)

        assertEquals("test-password", store.password(profile.id))
        assertTrue(store.isAutoLoginEnabled(profile.id))
        assertEquals(profile.id, store.lastProfileId())

        store.clearPassword(profile.id)

        assertNull(store.password(profile.id))
        assertFalse(store.isAutoLoginEnabled(profile.id))
    }
}
