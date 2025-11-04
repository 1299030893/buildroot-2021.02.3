# OpenSSL 移植步骤指南

本文档基于 Buildroot 项目中的 OpenSSL 集成方式，详细说明如何手动移植 OpenSSL 到嵌入式系统。

## 基本信息

- **OpenSSL 版本**: 1.1.1k
- **源码下载地址**: https://www.openssl.org/source/openssl-1.1.1k.tar.gz
- **SHA256 校验值**: `892a0875b9872acd04a9fde79b1f943075d5ea162415de3047c327df33fbaee5`
- **依赖项**: zlib

---

## 第一步：下载源码并解压

```bash
# 下载 OpenSSL 源码
wget https://www.openssl.org/source/openssl-1.1.1k.tar.gz

# 验证 SHA256 校验值（可选但推荐）
echo "892a0875b9872acd04a9fde79b1f943075d5ea162415de3047c327df33fbaee5  openssl-1.1.1k.tar.gz" | sha256sum -c

# 解压源码
tar -xzf openssl-1.1.1k.tar.gz
cd openssl-1.1.1k
```

---

## 第二步：确定目标架构

根据你的目标平台选择对应的架构配置：

| 架构 | Configure 参数 |
|------|----------------|
| ARM (32位, 支持ARM指令) | `linux-armv4` |
| ARM64 (AArch64) | `linux-aarch64` |
| x86 (32位) | `linux-x86` |
| x86_64 (64位) | `linux-x86_64` |
| PowerPC (64位大端) | `linux-ppc64` |
| PowerPC (64位小端) | `linux-ppc64le` |
| PowerPC (32位, 非4xx系列) | `linux-ppc` |
| 通用64位架构 (无ASM优化) | `linux-generic64 no-asm` |
| 通用32位架构 (无ASM优化) | `linux-generic32 no-asm` |

**示例**：如果是 ARM Cortex-A 系列，使用 `linux-armv4`；如果是通用的 64 位架构，使用 `linux-generic64 no-asm`。

---

## 第三步：配置编译选项

### 3.1 设置编译环境变量

```bash
# 设置交叉编译工具链路径（根据你的实际情况修改）
export CC=arm-linux-gnueabihf-gcc
export CXX=arm-linux-gnueabihf-g++
export AR=arm-linux-gnueabihf-ar
export RANLIB=arm-linux-gnueabihf-ranlib
export STRIP=arm-linux-gnueabihf-strip

# 设置目标架构
export TARGET_ARCH=linux-armv4  # 根据你的平台修改
```

### 3.2 准备编译标志

根据系统特性设置 CFLAGS：

```bash
# 基础编译标志
TARGET_CFLAGS="-Os -Wall"

# 特殊架构处理
# 如果是 m68k ColdFire
if [ "$ARCH" = "m68k_cf" ]; then
    TARGET_CFLAGS="$TARGET_CFLAGS -mxgot -DOPENSSL_SMALL_FOOTPRINT"
fi

# 如果系统没有 MMU（无内存管理单元）
if [ "$NO_MMU" = "1" ]; then
    TARGET_CFLAGS="$TARGET_CFLAGS -DHAVE_FORK=0 -DOPENSSL_NO_MADVISE"
fi

# 如果使用 musl libc 或没有 ucontext 支持
if [ "$USE_MUSL" = "1" ] || [ "$NO_UCONTEXT" = "1" ]; then
    TARGET_CFLAGS="$TARGET_CFLAGS -DOPENSSL_NO_ASYNC"
fi
```

---

## 第四步：运行 Configure 脚本

### 4.1 基本配置命令

```bash
./Configure \
    $TARGET_ARCH \
    --prefix=/usr \
    --openssldir=/etc/ssl \
    threads \                    # 如果工具链支持线程，否则使用 no-threads
    shared \                     # 动态库，如果静态编译使用 no-shared
    enable-camellia \
    enable-mdc2 \
    no-rc5 \
    no-tests \
    no-fuzz-libfuzzer \
    no-fuzz-afl \
    zlib-dynamic                 # 如果静态编译使用 zlib，动态编译使用 zlib-dynamic
```

### 4.2 完整配置示例（ARM 平台，动态库）

```bash
./Configure \
    linux-armv4 \
    --prefix=/usr \
    --openssldir=/etc/ssl \
    threads \
    shared \
    enable-camellia \
    enable-mdc2 \
    no-rc5 \
    no-tests \
    no-fuzz-libfuzzer \
    no-fuzz-afl \
    zlib-dynamic \
    no-asm                     # 如果架构不支持 ASM 优化，添加此选项
```

### 4.3 静态库配置示例

```bash
./Configure \
    linux-armv4 \
    --prefix=/usr \
    --openssldir=/etc/ssl \
    threads \
    no-shared \
    enable-camellia \
    enable-mdc2 \
    no-rc5 \
    no-tests \
    no-fuzz-libfuzzer \
    no-fuzz-afl \
    zlib \
    no-dso                     # 静态编译时需要禁用 DSO
```

### 4.4 如果工具链需要 libatomic

```bash
# 如果工具链需要链接 libatomic（某些架构如 ARM 需要）
./Configure \
    linux-armv4 \
    --prefix=/usr \
    --openssldir=/etc/ssl \
    -latomic \
    threads \
    shared \
    # ... 其他选项
```

---

## 第五步：修改 Makefile（如需要）

Configure 完成后，可能需要手动修改生成的 Makefile：

### 5.1 修正编译标志

```bash
# 替换默认的优化标志为自定义的 CFLAGS
sed -i "s#-O[0-9sg]#$TARGET_CFLAGS#g" Makefile
```

### 5.2 移除架构特定的标志（如果工具链不支持）

```bash
# 移除可能不兼容的 -march 和 -mcpu 标志
sed -i "s#-march=[-a-z0-9] ##" Makefile
sed -i "s#-mcpu=[-a-z0-9] ##g" Makefile
```

### 5.3 静态编译时移除 libdl 依赖

```bash
# 如果静态编译，移除 -ldl 链接选项
sed -i 's#-ldl##g' Makefile
```

### 5.4 移除测试构建目标（可选）

```bash
# 移除测试相关的构建目标
sed -i "s# build_tests##" Makefile
```

---

## 第六步：编译

```bash
# 设置编译环境变量
export CROSS_COMPILE=arm-linux-gnueabihf-  # 根据你的工具链修改

# 编译
make -j$(nproc)  # 使用多核并行编译，或指定数字如 make -j4
```

如果遇到编译错误，可能需要：
- 检查依赖库（特别是 zlib）是否正确安装
- 确认交叉编译工具链配置正确
- 查看错误信息，可能需要添加额外的编译标志

---

## 第七步：安装到暂存目录（Staging）

```bash
# 设置安装目录（用于交叉编译到目标系统）
STAGING_DIR=/path/to/staging  # 你的暂存目录路径

# 安装到暂存目录
make DESTDIR=$STAGING_DIR install
```

安装后，文件会安装到：
- 头文件：`$STAGING_DIR/usr/include/openssl/`
- 库文件：`$STAGING_DIR/usr/lib/`
- pkg-config 文件：`$STAGING_DIR/usr/lib/pkgconfig/`

### 7.1 修复静态编译的 pkg-config 文件（如需要）

如果是静态编译，需要从 pkg-config 文件中移除 `-ldl`：

```bash
sed -i 's#-ldl##' $STAGING_DIR/usr/lib/pkgconfig/libcrypto.pc
sed -i 's#-ldl##' $STAGING_DIR/usr/lib/pkgconfig/libssl.pc
sed -i 's#-ldl##' $STAGING_DIR/usr/lib/pkgconfig/openssl.pc
```

---

## 第八步：安装到目标系统

```bash
# 设置目标系统根目录
TARGET_DIR=/path/to/target  # 你的目标系统根目录

# 安装到目标系统
make DESTDIR=$TARGET_DIR install

# 清理不需要的文件
rm -rf $TARGET_DIR/usr/lib/ssl
rm -f $TARGET_DIR/usr/bin/c_rehash

# 如果不需要 openssl 命令行工具，可以删除
# rm -f $TARGET_DIR/usr/bin/openssl
# rm -f $TARGET_DIR/etc/ssl/misc/{CA.*,c_*}

# 如果不需要 Perl 脚本（且系统没有 Perl）
# rm -f $TARGET_DIR/etc/ssl/misc/{CA.pl,tsget}

# 如果不需要额外的引擎
# rm -rf $TARGET_DIR/usr/lib/engines-1.1
```

---

## 第九步：验证安装

### 9.1 检查库文件

```bash
# 检查库文件是否存在
ls -lh $STAGING_DIR/usr/lib/libssl.so*
ls -lh $STAGING_DIR/usr/lib/libcrypto.so*

# 检查库文件架构（如果是 ELF 文件）
file $STAGING_DIR/usr/lib/libssl.so.1.1
file $STAGING_DIR/usr/lib/libcrypto.so.1.1
```

### 9.2 检查头文件

```bash
ls -la $STAGING_DIR/usr/include/openssl/
```

### 9.3 测试链接（可选）

创建一个简单的测试程序：

```c
// test_openssl.c
#include <openssl/ssl.h>
#include <stdio.h>

int main() {
    printf("OpenSSL version: %s\n", OpenSSL_version(OPENSSL_VERSION));
    return 0;
}
```

编译测试：

```bash
arm-linux-gnueabihf-gcc test_openssl.c \
    -I$STAGING_DIR/usr/include \
    -L$STAGING_DIR/usr/lib \
    -lssl -lcrypto -o test_openssl
```

---

## 第十步：应用补丁（如需要）

根据你的系统特性，可能需要应用以下补丁：

### 10.1 禁用 madvise（无 MMU 系统）

如果系统没有 MMU，需要应用 `0003-Introduce-the-OPENSSL_NO_MADVISE-to-disable-call-to-.patch`：

```bash
# 在解压源码后、Configure 之前应用
patch -p1 < 0003-Introduce-the-OPENSSL_NO_MADVISE-to-disable-call-to-.patch
```

### 10.2 其他补丁

根据 Buildroot 源码，还有以下补丁可能需要：
- `0001-Dont-waste-time-building-manpages-if-we-re-not-going.patch` - 禁用 man 手册构建
- `0002-Reproducible-build-do-not-leak-compiler-path.patch` - 可重现构建
- 架构特定的补丁（如 PowerPC 相关）

---

## 常见问题处理

### Q1: 编译时出现 "undefined reference to `getcontext'" 错误

**解决方案**：添加 `-DOPENSSL_NO_ASYNC` 到 CFLAGS，并在 Configure 命令中添加相应的宏定义。

### Q2: 静态编译时出现 libdl 相关错误

**解决方案**：从 Makefile 和 pkg-config 文件中移除 `-ldl` 链接选项。

### Q3: 某些架构不支持 ASM 优化

**解决方案**：在 Configure 命令中添加 `no-asm` 选项。

### Q4: 需要链接 libatomic

**解决方案**：在 Configure 命令中添加 `-latomic` 选项。

### Q5: 交叉编译时找不到 zlib

**解决方案**：
- 确保 zlib 已正确交叉编译并安装到暂存目录
- 使用 `zlib-dynamic` 或 `zlib` 选项（根据静态/动态链接选择）
- 检查 `PKG_CONFIG_PATH` 环境变量是否正确设置

---

## 总结

OpenSSL 移植的关键步骤：

1. ✅ **下载并解压源码**
2. ✅ **确定目标架构配置**
3. ✅ **设置交叉编译环境变量**
4. ✅ **运行 Configure 脚本配置编译选项**
5. ✅ **修改 Makefile（如需要）**
6. ✅ **编译源码**
7. ✅ **安装到暂存目录（用于开发）**
8. ✅ **安装到目标系统**
9. ✅ **验证安装**
10. ✅ **应用必要的补丁**

建议在移植过程中，先在一个小范围测试环境中验证，确认无误后再应用到生产环境。

---

## 参考资源

- OpenSSL 官方文档：https://www.openssl.org/docs/
- Buildroot OpenSSL 包配置：`package/libopenssl/libopenssl.mk`
- Buildroot OpenSSL 配置文件：`package/libopenssl/Config.in`
