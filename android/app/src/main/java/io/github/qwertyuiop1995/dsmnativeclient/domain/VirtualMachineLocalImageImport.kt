package io.github.qwertyuiop1995.dsmnativeclient.domain

import java.util.Locale

/** 本地映像在上传前可确认的最小元数据，不保存显示名、URI 或本地路径。 */
data class ValidatedVirtualMachineLocalImage internal constructor(
    val imageType: VirtualMachineImageType,
    val originalSizeBytes: Long,
    val canonicalExtension: String,
)

enum class VirtualMachineLocalImageRejection {
    INVALID_DISPLAY_NAME,
    UNSUPPORTED_EXTENSION,
    SIZE_UNKNOWN,
    INVALID_SIZE,
    DISK_TOO_LARGE,
}

sealed interface VirtualMachineLocalImageValidation {
    data class Accepted(val value: ValidatedVirtualMachineLocalImage) :
        VirtualMachineLocalImageValidation

    data class Rejected(val reason: VirtualMachineLocalImageRejection) :
        VirtualMachineLocalImageValidation
}

/**
 * 将系统文件选择器提供的显示名和大小转换为官方 VMM 映像类型。
 *
 * 规范扩展来自固定白名单，可安全作为临时文件后缀；本函数不生成 NAS 路径、UUID 或本地文件名。
 */
fun validateVirtualMachineLocalImage(
    displayName: String,
    sizeBytes: Long?,
): VirtualMachineLocalImageValidation {
    val normalizedName = displayName.trim()
    if (normalizedName.isEmpty() || normalizedName.startsWith('.') ||
        normalizedName.any(Char::isISOControl) ||
        '/' in normalizedName || '\\' in normalizedName
    ) {
        return VirtualMachineLocalImageValidation.Rejected(
            VirtualMachineLocalImageRejection.INVALID_DISPLAY_NAME,
        )
    }

    val separator = normalizedName.lastIndexOf('.')
    if (separator <= 0 || separator == normalizedName.lastIndex) {
        return VirtualMachineLocalImageValidation.Rejected(
            VirtualMachineLocalImageRejection.UNSUPPORTED_EXTENSION,
        )
    }
    val extension = normalizedName.substring(separator + 1).lowercase(Locale.ROOT)
    val imageType = when (extension) {
        "vmdk", "vdi", "vhd", "vhdx", "img", "qcow2" -> VirtualMachineImageType.DISK
        "iso" -> VirtualMachineImageType.ISO
        "pat" -> VirtualMachineImageType.VDSM
        else -> null
    } ?: return VirtualMachineLocalImageValidation.Rejected(
        VirtualMachineLocalImageRejection.UNSUPPORTED_EXTENSION,
    )

    if (sizeBytes == null) {
        return VirtualMachineLocalImageValidation.Rejected(
            VirtualMachineLocalImageRejection.SIZE_UNKNOWN,
        )
    }
    if (sizeBytes <= 0L) {
        return VirtualMachineLocalImageValidation.Rejected(
            VirtualMachineLocalImageRejection.INVALID_SIZE,
        )
    }
    if (imageType == VirtualMachineImageType.DISK && sizeBytes > MAX_DISK_IMAGE_BYTES) {
        return VirtualMachineLocalImageValidation.Rejected(
            VirtualMachineLocalImageRejection.DISK_TOO_LARGE,
        )
    }

    return VirtualMachineLocalImageValidation.Accepted(
        ValidatedVirtualMachineLocalImage(
            imageType = imageType,
            originalSizeBytes = sizeBytes,
            canonicalExtension = extension,
        ),
    )
}

/** 固定白名单扩展转成供临时文件 API 使用的安全后缀。 */
fun ValidatedVirtualMachineLocalImage.safeTemporaryFileSuffix(): String = ".$canonicalExtension"

private const val MAX_DISK_IMAGE_BYTES = 2_199_023_255_552L
