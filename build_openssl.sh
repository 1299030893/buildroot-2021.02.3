#!/bin/bash
################################################################################
# OpenSSL 自动编译脚本
# 基于 Buildroot 的 libopenssl.mk 构建逻辑
# 用法: ./build_openssl.sh [选项]
################################################################################

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 默认配置
# 注意：OpenSSL 1.1.1 系列已于 2023年9月停止维护（EOL），存在安全风险
# 推荐使用 OpenSSL 3.0.x (LTS) 或 3.1.x / 3.2.x 版本
OPENSSL_VERSION="3.0.16"  # LTS 版本，长期支持
# 备选版本：
# OPENSSL_VERSION="3.1.7"   # 稳定版本
# OPENSSL_VERSION="3.2.3"    # 最新版本（需要验证）
# OPENSSL_VERSION="1.1.1w"   # 最后维护版本（已停止更新，不推荐）
OPENSSL_SOURCE_URL="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
OPENSSL_SOURCE_FILE="openssl-${OPENSSL_VERSION}.tar.gz"
# SHA256 校验值（需要根据实际下载的版本更新）
OPENSSL_SHA256=""  # 留空则不验证，建议从官网获取对应版本的 SHA256

# 工作目录
WORK_DIR="${PWD}/openssl-build"
BUILD_DIR="${WORK_DIR}/build"
SOURCE_DIR="${WORK_DIR}/openssl-${OPENSSL_VERSION}"
STAGING_DIR="${WORK_DIR}/staging"
TARGET_DIR="${WORK_DIR}/target"

# 默认架构配置（可根据需要修改）
TARGET_ARCH="linux-armv4"  # 默认 ARM，可根据实际情况修改
PREFIX="/usr"
OPENSSLDIR="/etc/ssl"

# 编译选项
STATIC_BUILD=0
NO_MMU=0
USE_MUSL=0
NO_UCONTEXT=0
NO_ASM=0
NEED_LIBATOMIC=0
THREADS=1
ENABLE_CRYPTODEV=0

# 交叉编译工具链（需要根据实际情况设置）
CROSS_COMPILE="${CROSS_COMPILE:-}"
CC="${CC:-${CROSS_COMPILE}gcc}"
CXX="${CXX:-${CROSS_COMPILE}g++}"
AR="${AR:-${CROSS_COMPILE}ar}"
RANLIB="${RANLIB:-${CROSS_COMPILE}ranlib}"
STRIP="${STRIP:-${CROSS_COMPILE}strip}"

# 帮助信息
usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -h, --help              显示帮助信息
    -v, --version VERSION    指定 OpenSSL 版本 (默认: ${OPENSSL_VERSION})
                           推荐: 3.0.x (LTS), 3.1.x, 3.2.x
                           注意: 1.1.1 系列已停止维护，存在安全风险
    -a, --arch ARCH         指定目标架构 (默认: ${TARGET_ARCH})
                          支持: linux-armv4, linux-aarch64, linux-x86, linux-x86_64
                                linux-ppc, linux-ppc64, linux-ppc64le
                                linux-generic32, linux-generic64
    -s, --static            静态编译
    -d, --download-only     仅下载源码，不编译
    -c, --clean             清理构建目录
    --no-mmu                无 MMU 系统
    --musl                  使用 musl libc
    --no-ucontext           无 ucontext 支持
    --no-asm                禁用 ASM 优化
    --libatomic             需要链接 libatomic
    --no-threads            禁用线程支持
    --cryptodev             启用 cryptodev 支持
    --staging-dir DIR       指定暂存目录 (默认: ${STAGING_DIR})
    --target-dir DIR        指定目标目录 (默认: ${TARGET_DIR})
    --work-dir DIR          指定工作目录 (默认: ${WORK_DIR})

示例:
    # ARM 平台，动态库
    $0 -a linux-armv4

    # ARM64 平台，静态库
    $0 -a linux-aarch64 -s

    # 无 MMU 系统
    $0 -a linux-armv4 --no-mmu

    # 设置交叉编译工具链
    CROSS_COMPILE=arm-linux-gnueabihf- $0 -a linux-armv4

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                OPENSSL_VERSION="$2"
                OPENSSL_SOURCE_FILE="openssl-${OPENSSL_VERSION}.tar.gz"
                OPENSSL_SOURCE_URL="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
                shift 2
                ;;
            -a|--arch)
                TARGET_ARCH="$2"
                shift 2
                ;;
            -s|--static)
                STATIC_BUILD=1
                shift
                ;;
            -d|--download-only)
                DOWNLOAD_ONLY=1
                shift
                ;;
            -c|--clean)
                CLEAN_BUILD=1
                shift
                ;;
            --no-mmu)
                NO_MMU=1
                shift
                ;;
            --musl)
                USE_MUSL=1
                shift
                ;;
            --no-ucontext)
                NO_UCONTEXT=1
                shift
                ;;
            --no-asm)
                NO_ASM=1
                shift
                ;;
            --libatomic)
                NEED_LIBATOMIC=1
                shift
                ;;
            --no-threads)
                THREADS=0
                shift
                ;;
            --cryptodev)
                ENABLE_CRYPTODEV=1
                shift
                ;;
            --staging-dir)
                STAGING_DIR="$2"
                shift 2
                ;;
            --target-dir)
                TARGET_DIR="$2"
                shift 2
                ;;
            --work-dir)
                WORK_DIR="$2"
                SOURCE_DIR="${WORK_DIR}/openssl-${OPENSSL_VERSION}"
                BUILD_DIR="${WORK_DIR}/build"
                shift 2
                ;;
            *)
                echo -e "${RED}错误: 未知选项 $1${NC}"
                usage
                exit 1
                ;;
        esac
    done
}

# 打印信息
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查依赖
check_dependencies() {
    local missing=0
    
    for cmd in wget tar make sed; do
        if ! command -v $cmd &> /dev/null; then
            error "缺少命令: $cmd"
            missing=1
        fi
    done
    
    if [ "$missing" -eq 0 ]; then
        info "依赖检查通过"
    fi
}

# 清理构建目录
clean_build() {
    info "清理构建目录..."
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
        info "已清理: $WORK_DIR"
    fi
}

# 下载源码
download_source() {
    if [ -f "$WORK_DIR/$OPENSSL_SOURCE_FILE" ]; then
        info "源码文件已存在: $WORK_DIR/$OPENSSL_SOURCE_FILE"
        
        # 验证 SHA256（如果提供了校验值）
        if [ -n "$OPENSSL_SHA256" ] && command -v sha256sum &> /dev/null; then
            info "验证 SHA256 校验值..."
            echo "${OPENSSL_SHA256}  ${WORK_DIR}/${OPENSSL_SOURCE_FILE}" | sha256sum -c || \
                warn "SHA256 校验失败，但继续执行..."
        elif [ -z "$OPENSSL_SHA256" ]; then
            warn "未设置 SHA256 校验值，跳过验证"
        fi
        return
    fi
    
    info "下载 OpenSSL 源码..."
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    if ! wget -O "$OPENSSL_SOURCE_FILE" "$OPENSSL_SOURCE_URL"; then
        error "下载失败: $OPENSSL_SOURCE_URL"
    fi
    
    # 验证 SHA256（如果提供了校验值）
    if [ -n "$OPENSSL_SHA256" ] && command -v sha256sum &> /dev/null; then
        info "验证 SHA256 校验值..."
        echo "${OPENSSL_SHA256}  ${OPENSSL_SOURCE_FILE}" | sha256sum -c || \
            warn "SHA256 校验失败，但继续执行..."
    elif [ -z "$OPENSSL_SHA256" ]; then
        warn "未设置 SHA256 校验值，跳过验证"
        warn "建议从 https://www.openssl.org/source/ 获取对应版本的 SHA256 值"
    fi
    
    info "下载完成"
}

# 解压源码
extract_source() {
    if [ -d "$SOURCE_DIR" ]; then
        info "源码目录已存在: $SOURCE_DIR"
        return
    fi
    
    info "解压源码..."
    cd "$WORK_DIR"
    tar -xzf "$OPENSSL_SOURCE_FILE"
    info "解压完成: $SOURCE_DIR"
}

# 应用补丁
apply_patches() {
    # 如果有补丁目录，应用补丁
    if [ -d "patches" ]; then
        info "应用补丁..."
        cd "$SOURCE_DIR"
        for patch in ../patches/*.patch; do
            if [ -f "$patch" ]; then
                info "应用补丁: $(basename $patch)"
                patch -p1 < "$patch" || warn "补丁应用失败: $patch"
            fi
        done
    fi
}

# 准备编译标志
prepare_cflags() {
    local cflags="${TARGET_CFLAGS:-}"
    
    # 特殊架构处理
    case "$TARGET_ARCH" in
        *m68k*)
            cflags="$cflags -mxgot -DOPENSSL_SMALL_FOOTPRINT"
            ;;
    esac
    
    # 无 MMU 系统
    if [ "$NO_MMU" -eq 1 ]; then
        cflags="$cflags -DHAVE_FORK=0 -DOPENSSL_NO_MADVISE"
    fi
    
    # musl libc 或 无 ucontext
    if [ "$USE_MUSL" -eq 1 ] || [ "$NO_UCONTEXT" -eq 1 ]; then
        cflags="$cflags -DOPENSSL_NO_ASYNC"
    fi
    
    echo "$cflags"
}

# 配置编译
configure_build() {
    info "配置 OpenSSL 编译..."
    cd "$SOURCE_DIR"
    
    # 准备 Configure 参数
    local configure_args=(
        "$TARGET_ARCH"
        "--prefix=$PREFIX"
        "--openssldir=$OPENSSLDIR"
    )
    
    # 添加 libatomic（如果需要）
    if [ "$NEED_LIBATOMIC" -eq 1 ]; then
        configure_args+=("-latomic")
    fi
    
    # 线程支持
    if [ "$THREADS" -eq 1 ]; then
        configure_args+=("threads")
    else
        configure_args+=("no-threads")
    fi
    
    # 静态/动态库
    if [ "$STATIC_BUILD" -eq 1 ]; then
        configure_args+=("no-shared")
        configure_args+=("zlib")
        configure_args+=("no-dso")
    else
        configure_args+=("shared")
        configure_args+=("zlib-dynamic")
    fi
    
    # cryptodev 支持
    if [ "$ENABLE_CRYPTODEV" -eq 1 ]; then
        configure_args+=("enable-devcryptoeng")
    fi
    
    # 通用选项
    configure_args+=(
        "no-rc5"
        "enable-camellia"
        "enable-mdc2"
        "no-tests"
        "no-fuzz-libfuzzer"
        "no-fuzz-afl"
    )
    
    # 禁用 ASM 优化（如果需要）
    if [ "$NO_ASM" -eq 1 ]; then
        configure_args+=("no-asm")
    fi
    
    # 设置交叉编译环境变量
    export CC="$CC"
    export CXX="$CXX"
    export AR="$AR"
    export RANLIB="$RANLIB"
    export STRIP="$STRIP"
    
    # 运行 Configure
    info "运行 Configure: ${configure_args[*]}"
    ./Configure "${configure_args[@]}" || error "Configure 失败"
    
    # 修改 Makefile
    info "调整 Makefile..."
    
    # 移除架构特定的标志
    sed -i "s#-march=[-a-z0-9] ##" Makefile
    sed -i "s#-mcpu=[-a-z0-9] ##g" Makefile
    
    # 替换优化标志
    local cflags=$(prepare_cflags)
    if [ -n "$cflags" ]; then
        sed -i "s#-O[0-9sg]#$cflags#g" Makefile
    fi
    
    # 移除测试构建目标
    sed -i "s# build_tests##" Makefile
    
    # 静态编译时移除 libdl
    if [ "$STATIC_BUILD" -eq 1 ]; then
        sed -i 's#-ldl##g' Makefile
    fi
    
    info "配置完成"
}

# 编译
build_openssl() {
    info "开始编译 OpenSSL..."
    cd "$SOURCE_DIR"
    
    # 设置编译环境
    export CC="$CC"
    export CXX="$CXX"
    export AR="$AR"
    export RANLIB="$RANLIB"
    
    # 编译
    make -j$(nproc 2>/dev/null || echo 4) || error "编译失败"
    
    info "编译完成"
}

# 安装到暂存目录
install_staging() {
    info "安装到暂存目录: $STAGING_DIR"
    cd "$SOURCE_DIR"
    
    mkdir -p "$STAGING_DIR"
    
    make DESTDIR="$STAGING_DIR" install || error "安装到暂存目录失败"
    
    # 静态编译时修复 pkg-config 文件
    if [ "$STATIC_BUILD" -eq 1 ]; then
        info "修复静态编译的 pkg-config 文件..."
        for pc in libcrypto.pc libssl.pc openssl.pc; do
            if [ -f "$STAGING_DIR/usr/lib/pkgconfig/$pc" ]; then
                sed -i 's#-ldl##' "$STAGING_DIR/usr/lib/pkgconfig/$pc"
            fi
        done
    fi
    
    info "暂存目录安装完成"
}

# 安装到目标目录
install_target() {
    info "安装到目标目录: $TARGET_DIR"
    cd "$SOURCE_DIR"
    
    mkdir -p "$TARGET_DIR"
    
    make DESTDIR="$TARGET_DIR" install || error "安装到目标目录失败"
    
    # 清理不需要的文件
    info "清理不需要的文件..."
    rm -rf "$TARGET_DIR/usr/lib/ssl"
    rm -f "$TARGET_DIR/usr/bin/c_rehash"
    
    # 可选：移除 openssl 命令行工具
    # rm -f "$TARGET_DIR/usr/bin/openssl"
    # rm -f "$TARGET_DIR/etc/ssl/misc/{CA.*,c_*}"
    
    # 可选：移除 Perl 脚本
    # rm -f "$TARGET_DIR/etc/ssl/misc/{CA.pl,tsget}"
    
    # 可选：移除引擎
    # rm -rf "$TARGET_DIR/usr/lib/engines-1.1"
    
    info "目标目录安装完成"
}

# 显示安装信息
show_install_info() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}OpenSSL 编译安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "源码目录: $SOURCE_DIR"
    echo "暂存目录: $STAGING_DIR"
    echo "目标目录: $TARGET_DIR"
    echo ""
    echo "库文件位置:"
    echo "  - $STAGING_DIR/usr/lib/libssl.so*"
    echo "  - $STAGING_DIR/usr/lib/libcrypto.so*"
    echo ""
    echo "头文件位置:"
    echo "  - $STAGING_DIR/usr/include/openssl/"
    echo ""
    echo "pkg-config 文件:"
    echo "  - $STAGING_DIR/usr/lib/pkgconfig/libssl.pc"
    echo "  - $STAGING_DIR/usr/lib/pkgconfig/libcrypto.pc"
    echo ""
}

# 主函数
main() {
    parse_args "$@"
    
    info "OpenSSL 自动编译脚本"
    info "版本: $OPENSSL_VERSION"
    info "架构: $TARGET_ARCH"
    info "工作目录: $WORK_DIR"
    echo ""
    
    # 清理
    if [ "${CLEAN_BUILD:-0}" -eq 1 ]; then
        clean_build
        exit 0
    fi
    
    # 检查依赖
    check_dependencies
    
    # 下载源码
    download_source
    
    if [ "${DOWNLOAD_ONLY:-0}" -eq 1 ]; then
        info "仅下载模式，退出"
        exit 0
    fi
    
    # 解压源码
    extract_source
    
    # 应用补丁
    apply_patches
    
    # 配置编译
    configure_build
    
    # 编译
    build_openssl
    
    # 安装到暂存目录
    install_staging
    
    # 安装到目标目录
    install_target
    
    # 显示安装信息
    show_install_info
}

# 运行主函数
main "$@"
