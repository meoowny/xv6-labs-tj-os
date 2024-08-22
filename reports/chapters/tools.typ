#import "@preview/ilm:1.2.1": *

= 实验环境配置

== 启用虚拟化并安装 WSL

+ 启用虚拟化命令：以管理员打开powershell输入：

  #blockquote[
  ```bash
  dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
  ```
  ]

+ 实验所有项目均在 Windows11 的 WSL 下完成，因此可以直接使用 ```bash wsl --install -d Ubuntu``` 安装 Ubuntu 子系统。

== 准备运行环境

启动 Ubuntu，使用如下指令安装本项目所需的所有软件：

  #blockquote[
  ```bash
  $ sudo apt-get update && sudo apt-get upgrade
  $ sudo apt-get install git build-essential gdb-multiarch qemu-system-misc gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu
  ```
]

== 拉取源码并编译内核

+ 下载 xv6 内核源码及文档：

  #blockquote[
  ```bash
  $ git clone git://github.com/mit-pdos/xv6-riscv.git
  $ git clone git://github.com/mit-pdos/xv6-riscv-book.git
  ```
  ]

+ 进入内核仓库目录，然后输入以下指令涫并运行 xv6 内核（按 `Ctrl-a x` 以退出 qemu）：

  #blockquote[
  ```bash
  $ make qemu
  # ... lots of output ...
  init: starting sh
  $
  ```
]

+ 如果编译失败，则需要查看各组件是否正常安装。这包括 QEMU 和至少一个 RISC-V 版本的 GCC：

  #blockquote[
  ```bash
  $ qemu-system-riscv64 --version
  $ riscv64-linux-gnu-gcc --version
  $ riscv64-unknown-elf-gcc --version
  $ riscv64-unknown-linux-gnu-gcc --version
  ```
]

