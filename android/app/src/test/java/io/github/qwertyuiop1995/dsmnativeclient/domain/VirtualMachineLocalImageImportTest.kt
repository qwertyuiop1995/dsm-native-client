package io.github.qwertyuiop1995.dsmnativeclient.domain

import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VirtualMachineLocalImageImportTest {
    @Test
    fun `磁盘扩展逐项映射到官方 disk 类型`() {
        listOf("vmdk", "vdi", "vhd", "vhdx", "img", "qcow2").forEach { extension ->
            val accepted = accepted("machine.$extension", 1L)

            assertEquals(VirtualMachineImageType.DISK, accepted.imageType)
            assertEquals(extension, accepted.canonicalExtension)
            assertEquals(".$extension", accepted.safeTemporaryFileSuffix())
        }
    }

    @Test
    fun `ISO 与 PAT 映射到官方类型且扩展大小写被规范化`() {
        val iso = accepted(" INSTALL.ISO ", Long.MAX_VALUE)
        val vdsm = accepted("VirtualDSM.PaT", Long.MAX_VALUE)

        assertEquals(VirtualMachineImageType.ISO, iso.imageType)
        assertEquals("iso", iso.canonicalExtension)
        assertEquals(VirtualMachineImageType.VDSM, vdsm.imageType)
        assertEquals("pat", vdsm.canonicalExtension)
    }

    @Test
    fun `OVA 与未公开扩展保持拒绝`() {
        listOf("machine.ova", "machine.raw", "machine.qcow", "machine").forEach { name ->
            assertRejected(
                name,
                1L,
                VirtualMachineLocalImageRejection.UNSUPPORTED_EXTENSION,
            )
        }
    }

    @Test
    fun `大小未知以及零或负数均在提交前拒绝`() {
        assertRejected("machine.vmdk", null, VirtualMachineLocalImageRejection.SIZE_UNKNOWN)
        assertRejected("machine.vmdk", 0L, VirtualMachineLocalImageRejection.INVALID_SIZE)
        assertRejected("machine.vmdk", -1L, VirtualMachineLocalImageRejection.INVALID_SIZE)
    }

    @Test
    fun `磁盘映像接受二TiB并拒绝多一字节且无Long溢出`() {
        val twoTiB = 2_199_023_255_552L

        assertEquals(twoTiB, accepted("machine.vhdx", twoTiB).originalSizeBytes)
        assertRejected(
            "machine.vhdx",
            twoTiB + 1L,
            VirtualMachineLocalImageRejection.DISK_TOO_LARGE,
        )
        assertRejected(
            "machine.vhdx",
            Long.MAX_VALUE,
            VirtualMachineLocalImageRejection.DISK_TOO_LARGE,
        )
    }

    @Test
    fun `ISO 与 PAT 不臆造磁盘映像上限`() {
        assertEquals(Long.MAX_VALUE, accepted("installer.iso", Long.MAX_VALUE).originalSizeBytes)
        assertEquals(Long.MAX_VALUE, accepted("virtual-dsm.pat", Long.MAX_VALUE).originalSizeBytes)
    }

    @Test
    fun `显示名控制字符路径分隔符和空基名均拒绝`() {
        listOf("machine\n.vmdk", "/private/machine.vmdk", "folder\\machine.vmdk", ".iso").forEach {
            assertRejected(it, 1L, VirtualMachineLocalImageRejection.INVALID_DISPLAY_NAME)
        }
    }

    @Test
    fun `规范扩展只能生成白名单临时文件后缀`() {
        val accepted = accepted("archive.tar.QCOW2", 4_096L)

        assertEquals("qcow2", accepted.canonicalExtension)
        assertEquals(".qcow2", accepted.safeTemporaryFileSuffix())
        assertFalse(accepted.safeTemporaryFileSuffix().contains('/'))
        assertFalse(accepted.safeTemporaryFileSuffix().contains('\\'))
    }

    @Test
    fun `校验输出和字符串表示不保留本地路径或显示名`() {
        val privateName = "private-machine.vmdk"
        val privatePath = "/Users/example/Private/private-machine.vmdk"
        val result = validateVirtualMachineLocalImage(privateName, 8_192L)
        val accepted = (result as VirtualMachineLocalImageValidation.Accepted).value
        val rejectedPath = validateVirtualMachineLocalImage(privatePath, 8_192L)

        assertEquals(
            setOf("imageType", "originalSizeBytes", "canonicalExtension"),
            accepted::class.java.declaredFields
                .filterNot { it.isSynthetic || Modifier.isStatic(it.modifiers) }
                .map { it.name }
                .toSet(),
        )
        assertFalse(result.toString().contains(privateName))
        assertFalse(accepted.toString().contains(privateName))
        assertFalse(rejectedPath.toString().contains(privatePath))
        assertTrue(accepted.toString().contains("canonicalExtension=vmdk"))
    }

    private fun accepted(name: String, size: Long): ValidatedVirtualMachineLocalImage {
        val result = validateVirtualMachineLocalImage(name, size)
        return (result as VirtualMachineLocalImageValidation.Accepted).value
    }

    private fun assertRejected(
        name: String,
        size: Long?,
        reason: VirtualMachineLocalImageRejection,
    ) {
        assertEquals(
            VirtualMachineLocalImageValidation.Rejected(reason),
            validateVirtualMachineLocalImage(name, size),
        )
    }
}
