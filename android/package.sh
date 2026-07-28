#!/bin/bash

# 构建 LanStash Android APK，运行单元测试并输出到 dist 目录。
# 无需命令行参数，所有打包选项都在交互菜单中选择。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRODUCT_NAME="LanStash"
DIST_DIR="$SCRIPT_DIR/dist"

CONFIGURATION="release"
RUN_TESTS=1
INSTALL_AFTER=0
SELECTED_CHOICE=""

fail() {
    echo "错误：$*" >&2
    exit 1
}

ask_choice() {
    local title="$1"
    local default_choice="$2"
    shift 2
    local options=("$@")
    local choice=""
    local index=0
    local suffix=""

    while true; do
        echo
        echo "$title"
        for ((index = 0; index < ${#options[@]}; index++)); do
            suffix=""
            if [[ $((index + 1)) -eq "$default_choice" ]]; then
                suffix=" [默认]"
            fi
            printf '  %d) %s%s\n' "$((index + 1))" "${options[$index]}" "$suffix"
        done
        printf '请选择 [%s]，输入 q 可退出：' "$default_choice"

        if ! IFS= read -r choice; then
            fail "没有读取到选择，打包已停止"
        fi
        choice="${choice:-$default_choice}"

        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            echo "已取消打包。"
            exit 0
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] \
            && [[ "$choice" -ge 1 ]] \
            && [[ "$choice" -le "${#options[@]}" ]]; then
            SELECTED_CHOICE="$choice"
            return
        fi

        echo "输入无效，请输入 1-${#options[@]}，或输入 q 退出。" >&2
    done
}

configure_package() {
    local confirmation=""

    while true; do
        echo
        echo "========================================"
        echo "  LanStash Android 打包工具"
        echo "========================================"
        echo "直接按回车会使用每一步的默认选项。"

        ask_choice "1/3 选择构建类型" 1 \
            "Release（推荐，运行更快）" \
            "Debug（用于开发调试）"
        case "$SELECTED_CHOICE" in
            1) CONFIGURATION="release" ;;
            2) CONFIGURATION="debug" ;;
        esac

        ask_choice "2/3 是否运行单元测试" 1 \
            "运行测试（推荐）" \
            "跳过测试，直接打包"
        case "$SELECTED_CHOICE" in
            1) RUN_TESTS=1 ;;
            2) RUN_TESTS=0 ;;
        esac

        local install_option="只生成安装包，不安装"
        if command -v adb >/dev/null 2>&1; then
            install_option="安装到已连接的设备（如果可用）"
        fi
        ask_choice "3/3 打包完成后" 1 \
            "$install_option" \
            "只生成安装包，不安装"
        case "$SELECTED_CHOICE" in
            1) INSTALL_AFTER=$(command -v adb >/dev/null 2>&1 && echo 1 || echo 0) ;;
            2) INSTALL_AFTER=0 ;;
        esac

        echo
        echo "打包设置"
        echo "  构建类型：$CONFIGURATION"
        if [[ "$RUN_TESTS" -eq 1 ]]; then
            echo "  单元测试：运行"
        else
            echo "  单元测试：跳过"
        fi
        if [[ "$INSTALL_AFTER" -eq 1 ]]; then
            echo "  完成操作：安装到设备"
        else
            echo "  完成操作：仅生成安装包"
        fi

        ask_choice "确认以上设置" 1 \
            "开始打包" \
            "重新选择" \
            "退出"
        confirmation="$SELECTED_CHOICE"
        case "$confirmation" in
            1) return ;;
            2) continue ;;
            3)
                echo "已取消打包。"
                exit 0
                ;;
        esac
    done
}

cleanup_old_packages() {
    local package=""
    local removed=0

    shopt -s nullglob
    for package in "$DIST_DIR/$PRODUCT_NAME-"*.apk; do
        if [[ "$package" == "$DIST_DIR/$PRODUCT_NAME-$VERSION-"*.apk ]]; then
            continue
        fi
        /bin/rm -f -- "$package"
        removed=$((removed + 1))
    done
    shopt -u nullglob

    if [[ "$removed" -gt 0 ]]; then
        echo "==> 已清理 $removed 个旧版本安装包"
    fi
}

# 非交互模式
if [[ -n "${LANSTASH_NON_INTERACTIVE:-}" ]]; then
    case "${LANSTASH_BUILD_TYPE:-release}" in
        release|debug) CONFIGURATION="${LANSTASH_BUILD_TYPE:-release}" ;;
        *) fail "不支持的构建类型：${LANSTASH_BUILD_TYPE}，请使用 release 或 debug" ;;
    esac
    case "${LANSTASH_RUN_TESTS:-1}" in
        0|1) RUN_TESTS="${LANSTASH_RUN_TESTS:-1}" ;;
        *) fail "LANSTASH_RUN_TESTS 只能是 0 或 1" ;;
    esac
    case "${LANSTASH_INSTALL_AFTER:-0}" in
        0|1) INSTALL_AFTER="${LANSTASH_INSTALL_AFTER:-0}" ;;
        *) fail "LANSTASH_INSTALL_AFTER 只能是 0 或 1" ;;
    esac
else
    [[ $# -eq 0 ]] || fail "无需命令行参数，请直接运行 ./package.sh 后按菜单选择"
    configure_package
fi

# 前置检查
[[ -f "$SCRIPT_DIR/gradlew" ]] || fail "找不到 gradlew：$SCRIPT_DIR/gradlew"
command -v java >/dev/null 2>&1 || fail "未找到 java，请安装 JDK 17"

JAVA_VERSION=$(java -version 2>&1 | head -1 | awk -F '"' '{print $2}')
echo "==> Java 版本：$JAVA_VERSION"

# 源码信息
SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse --verify HEAD)"
SOURCE_BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD || echo detached)"
SOURCE_STATE="clean"
if [[ -n "$(git -C "$REPO_ROOT" status --short)" ]]; then
    SOURCE_STATE="包含未提交改动"
fi
echo "==> 源码：$SOURCE_BRANCH @ ${SOURCE_COMMIT:0:12}（${SOURCE_STATE}）"

# 读取版本号
VERSION="$(grep -E '^\s*versionName\s*=' "$SCRIPT_DIR/app/build.gradle.kts" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
if [[ -z "$VERSION" ]]; then
    fail "无法从 app/build.gradle.kts 读取 versionName"
fi
echo "==> 版本：$VERSION"

# 构建
cd "$SCRIPT_DIR"

BUILD_TASK=""
APK_DIR=""
APK_SUFFIX=""

if [[ "$CONFIGURATION" == "release" ]]; then
    BUILD_TASK=":app:assembleRelease"
    APK_DIR="$SCRIPT_DIR/app/build/outputs/apk/release"
    APK_SUFFIX="release"
else
    BUILD_TASK=":app:assembleDebug"
    APK_DIR="$SCRIPT_DIR/app/build/outputs/apk/debug"
    APK_SUFFIX="debug"
fi

if [[ "$RUN_TESTS" -eq 1 ]]; then
    echo "==> 运行单元测试"
    ./gradlew :app:testDebugUnitTest --stacktrace
    echo "==> 单元测试通过"
fi

echo "==> 构建 ${PRODUCT_NAME}（${CONFIGURATION}）"
./gradlew "$BUILD_TASK" --stacktrace

# 查找并复制 APK
APK_FILE=""
shopt -s nullglob
for apk in "$APK_DIR"/*.apk; do
    APK_FILE="$apk"
    break
done
shopt -u nullglob

if [[ -z "$APK_FILE" ]]; then
    fail "构建完成但找不到 APK：$APK_DIR"
fi

mkdir -p "$DIST_DIR"
DEST_APK="$DIST_DIR/$PRODUCT_NAME-$VERSION-$APK_SUFFIX.apk"
cp "$APK_FILE" "$DEST_APK"

APK_SIZE="$(du -h "$DEST_APK" | awk '{print $1}')"
echo "==> APK 已生成：${DEST_APK}（${APK_SIZE}）"

# 清理旧版本
cleanup_old_packages

# 安装到设备
if [[ "$INSTALL_AFTER" -eq 1 ]]; then
    if command -v adb >/dev/null 2>&1; then
        DEVICE_COUNT="$(adb devices | grep -c 'device$' || true)"
        if [[ "$DEVICE_COUNT" -gt 0 ]]; then
            echo "==> 安装到已连接的设备"
            adb install -r "$DEST_APK"
            echo "==> 安装完成"
        else
            echo "==> 未检测到已连接的设备，跳过安装"
        fi
    else
        echo "==> 未找到 adb，跳过安装"
    fi
fi

# 完成
echo
echo "打包完成："
echo "  版本：$VERSION"
echo "  APK：$DEST_APK"
if [[ "$CONFIGURATION" == "release" ]]; then
    if [[ -f "$SCRIPT_DIR/keystore.properties" ]]; then
        echo "  签名：已使用 keystore.properties 配置的签名"
    else
        echo "  签名：调试签名（适合本机测试，不适合公开分发）"
    fi
fi
