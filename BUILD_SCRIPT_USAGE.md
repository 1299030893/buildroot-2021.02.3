# OpenSSL 自动编译脚本使用说明

## 脚本功能

`build_openssl.sh` 是一个自动化编译脚本，基于 Buildroot 的构建逻辑，可以独立编译 OpenSSL，无需依赖 Buildroot 构建系统。

## 快速开始

### 基本用法

```bash
# 1. 给脚本添加执行权限（如果还没有）
chmod +x build_openssl.sh

# 2. ARM 平台，动态库编译
./build_openssl.sh -a linux-armv4

# 3. ARM64 平台，静态库编译
./build_openssl.sh -a linux-aarch64 -s

# 4. 设置交叉编译工具链
CROSS_COMPILE=arm-linux-gnueabihf- ./build_openssl.sh -a linux-armv4
```

## 常用场景示例

### 场景 1: ARM Cortex-A 平台（动态库）

```bash
CROSS_COMPILE=arm-linux-gnueabihf- \
./build_openssl.sh -a linux-armv4
```

### 场景 2: ARM64 平台（静态库）

```bash
CROSS_COMPILE=aarch64-linux-gnu- \
./build_openssl.sh -a linux-aarch64 -s
```

### 场景 3: 无 MMU 系统

```bash
CROSS_COMPILE=arm-linux-gnueabihf- \
./build_openssl.sh -a linux-armv4 --no-mmu
```

### 场景 4: 使用 musl libc

```bash
CROSS_COMPILE=arm-linux-musleabihf- \
./build_openssl.sh -a linux-armv4 --musl
```

### 场景 5: x86_64 平台

```bash
./build_openssl.sh -a linux-x86_64
```

### 场景 6: 仅下载源码，不编译

```bash
./build_openssl.sh -d
```

### 场景 7: 清理构建目录

```bash
./build_openssl.sh -c
```

## 完整参数说明

| 参数 | 说明 | 示例 |
|------|------|------|
| `-h, --help` | 显示帮助信息 | `./build_openssl.sh -h` |
| `-v, --version VERSION` | 指定 OpenSSL 版本 | `./build_openssl.sh -v 1.1.1m` |
| `-a, --arch ARCH` | 指定目标架构 | `./build_openssl.sh -a linux-aarch64` |
| `-s, --static` | 静态编译 | `./build_openssl.sh -s` |
| `-d, --download-only` | 仅下载源码 | `./build_openssl.sh -d` |
| `-c, --clean` | 清理构建目录 | `./build_openssl.sh -c` |
| `--no-mmu` | 无 MMU 系统 | `./build_openssl.sh --no-mmu` |
| `--musl` | 使用 musl libc | `./build_openssl.sh --musl` |
| `--no-ucontext` | 无 ucontext 支持 | `./build_openssl.sh --no-ucontext` |
| `--no-asm` | 禁用 ASM 优化 | `./build_openssl.sh --no-asm` |
| `--libatomic` | 需要链接 libatomic | `./build_openssl.sh --libatomic` |
| `--no-threads` | 禁用线程支持 | `./build_openssl.sh --no-threads` |
| `--cryptodev` | 启用 cryptodev 支持 | `./build_openssl.sh --cryptodev` |
| `--staging-dir DIR` | 指定暂存目录 | `./build_openssl.sh --staging-dir /tmp/staging` |
| `--target-dir DIR` | 指定目标目录 | `./build_openssl.sh --target-dir /tmp/target` |
| `--work-dir DIR` | 指定工作目录 | `./build_openssl.sh --work-dir /tmp/openssl-work` |

## 支持的架构

| 架构参数 | 说明 |
|----------|------|
| `linux-armv4` | ARM 32位（支持 ARM 指令） |
| `linux-aarch64` | ARM64 (AArch64) |
| `linux-x86` | x86 32位 |
| `linux-x86_64` | x86_64 64位 |
| `linux-ppc` | PowerPC 32位 |
| `linux-ppc64` | PowerPC 64位大端 |
| `linux-ppc64le` | PowerPC 64位小端 |
| `linux-generic32` | 通用 32位（无 ASM 优化） |
| `linux-generic64` | 通用 64位（无 ASM 优化） |

## 环境变量

可以通过环境变量设置交叉编译工具链：

```bash
# 设置交叉编译前缀
export CROSS_COMPILE=arm-linux-gnueabihf-

# 或者单独设置各个工具
export CC=arm-linux-gnueabihf-gcc
export AR=arm-linux-gnueabihf-ar
export RANLIB=arm-linux-gnueabihf-ranlib
export STRIP=arm-linux-gnueabihf-strip

# 然后运行脚本
./build_openssl.sh -a linux-armv4
```

## 输出目录结构

脚本执行后，会在工作目录（默认 `openssl-build/`）下创建以下目录：

```
openssl-build/
├── openssl-1.1.1k/          # 源码目录
├── build/                    # 构建目录（如果需要）
├── staging/                  # 暂存目录（开发用）
│   └── usr/
│       ├── include/
│       │   └── openssl/      # 头文件
│       ├── lib/
│       │   ├── libssl.so*    # SSL 库
│       │   ├── libcrypto.so* # 加密库
│       │   └── pkgconfig/    # pkg-config 文件
│       └── bin/
└── target/                   # 目标目录（运行时用）
    └── usr/
        ├── lib/
        └── bin/
```

## 使用编译好的库

### 编译其他程序时链接 OpenSSL

```bash
# 设置环境变量
export PKG_CONFIG_PATH=/path/to/openssl-build/staging/usr/lib/pkgconfig

# 编译你的程序
gcc your_program.c \
    -I/path/to/openssl-build/staging/usr/include \
    -L/path/to/openssl-build/staging/usr/lib \
    -lssl -lcrypto \
    -o your_program
```

### 使用 pkg-config

```bash
# 设置 pkg-config 路径
export PKG_CONFIG_PATH=/path/to/openssl-build/staging/usr/lib/pkgconfig

# 获取编译标志
CFLAGS=$(pkg-config --cflags openssl)
LIBS=$(pkg-config --libs openssl)

# 编译
gcc your_program.c $CFLAGS $LIBS -o your_program
```

## 常见问题

### Q1: 如何确定应该使用哪个架构参数？

**A**: 
- ARM 32位（Cortex-A 系列）: `linux-armv4`
- ARM64: `linux-aarch64`
- 不确定时，可以先用 `linux-generic32` 或 `linux-generic64`（但性能可能较差）

### Q2: 编译时提示找不到 zlib

**A**: 确保 zlib 已安装，或使用交叉编译的 zlib：
```bash
# 先编译安装 zlib 到暂存目录
# 然后确保 zlib 在系统路径中或设置相关环境变量
```

### Q3: 如何验证编译是否成功？

**A**: 检查输出文件：
```bash
ls -lh openssl-build/staging/usr/lib/libssl.so*
ls -lh openssl-build/staging/usr/lib/libcrypto.so*
ls -la openssl-build/staging/usr/include/openssl/
```

### Q4: 如何应用到实际项目？

**A**: 
1. 将 `staging/usr/lib/` 中的库文件复制到你的项目库目录
2. 将 `staging/usr/include/openssl/` 中的头文件复制到你的项目头文件目录
3. 在编译时指定库路径和头文件路径

## 脚本执行流程

脚本会自动执行以下步骤：

1. ✅ 检查依赖工具（wget, tar, make, sed）
2. ✅ 下载 OpenSSL 源码（如果不存在）
3. ✅ 验证 SHA256 校验值
4. ✅ 解压源码
5. ✅ 应用补丁（如果有 patches 目录）
6. ✅ 运行 Configure 配置
7. ✅ 修改 Makefile（调整编译标志）
8. ✅ 编译源码
9. ✅ 安装到暂存目录
10. ✅ 安装到目标目录
11. ✅ 显示安装信息

## 与 Buildroot 的关系

这个脚本提取了 Buildroot 中 `package/libopenssl/libopenssl.mk` 的构建逻辑，使其可以独立运行，无需完整的 Buildroot 环境。

## 注意事项

1. **依赖 zlib**: 确保系统已安装 zlib 开发库，或先交叉编译 zlib
2. **工具链路径**: 确保交叉编译工具链在 PATH 中，或使用 `CROSS_COMPILE` 环境变量
3. **权限问题**: 某些操作可能需要 root 权限，特别是在安装到系统目录时
4. **磁盘空间**: 确保有足够的磁盘空间（至少 200MB）
