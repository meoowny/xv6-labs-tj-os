#import "@preview/ilm:1.2.1": *

= Lab: File System

== 实验概述

本实验将为 xv6 的文件系统添加大文件与符号链接。

开始编码之前，阅读 #link("https://pdos.csail.mit.edu/6.828/2021/xv6/book-riscv-rev2.pdf")[xv6 book] 的第 8 章“文件系统”的内容。

开始实验前需要使用 ```bash git checkout fs``` 先切换到 `fs` 分支，将代码复制到 fs 目录下。

== Large files

=== 实验目的

+ 扩展 xv6 文件系统以提高最大文件的大小。
+ 目前 xv6 文件的 `inode` 包含 12 个“直接”块号和一个“单间接”块号，因此只能有 268 个块，即 $268 * "BSIZE"$ 字节。
+ 修改 `bmap()` 以实现二级间接块。这样的话将只有 11 个直接块，为二级间接块留出空间。改进后文件总大小将可以达到 $11 + 256 + 256 * 256 = 65803$ 个块。

=== 实验步骤

+ 修改 `kernel/fs.h` 中的相关定义，将直接块的个数 `NDIRECT` 改为 11，同步修改最大文件大小并修改 `dinode` 的 `addrs` 数组大小为 `NDIRECT+2`：
  #blockquote[
  ```c
  #define NDIRECT 11
  #define NINDIRECT (BSIZE / sizeof(uint))
  #define MAXFILE (NDIRECT + NINDIRECT + NINDIRECT * NINDIRECT)

  struct dinode {
    ...
    uint addrs[NDIRECT+2];   // Data block addresses
  };
  ```
  ]
+ 修改 `kernel/file.h` 中 `inode` 的 `addrs` 数组大小为 `NDIRECT+2`
  #blockquote[
  ```c
  struct inode {
    ...
    uint addrs[NDIRECT+2];
  };
  ```
  ]
+ 接下来修改 `kernel/fs.c` 的 `bmap()` 函数，以支持二级间接块。参考该函数查询块表的过程，重复一次查询操作即可：
  #blockquote[
  ```c
  bn -= NINDIRECT;

  if (bn < NINDIRECT * NINDIRECT) {
    int id1 = bn / NINDIRECT;  // 一级索引
    int id2 = bn % NINDIRECT;  // 二级索引
    if ((addr = ip->addrs[NDIRECT + 1]) == 0)
      ip->addrs[NDIRECT + 1] = addr = balloc(ip->dev);
    bp = bread(ip->dev, addr);
    a = (uint*)bp->data;
    if ((addr = a[idx]) == 0) {
      a[idx] = addr = balloc(ip->dev);
      log_write(bp);
    }
    brelse(bp);

    bp = bread(ip->dev, addr);
    a = (uint*)bp->data;
    if ((addr = a[off]) == 0) {
      a[off] = addr = balloc(ip->dev);
      log_write(bp);
    }
    brelse(bp);
    return addr;
  }

  panic("bmap: out of range");
  ```
  ]
+ 修改 `itrunc()` 函数，使其能够释放二级间接块。还是参考原间接块的处理：
  #blockquote[
  ```c
  if (ip->addrs[NDIRECT + 1]) {
    bp = bread(ip->dev, ip->addrs[NDIRECT + 1]);
    a = (uint*)bp->data;

    struct buf *bpd;
    uint* b;
    for (j = 0; j < NINDIRECT; j++) {
      if (a[j]) {
        bpd = bread(ip->dev, a[j]);
        b = (uint*)bpd->data;
        for (int k = 0; k < NINDIRECT; k++) {
          if (b[k])
            bfree(ip->dev, b[k]);
        }
        brelse(bpd);
        bfree(ip->dev, a[j]);
      }
    }
    brelse(bp);
    bfree(ip->dev, ip->addrs[NDIRECT + 1]);
    ip->addrs[NDIRECT + 1] = 0;
  }

  ip->size = 0;
  iupdate(ip);
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行 `bigfile` 可以得到如下结果：

#figure(
  image("..\assets\bigfile-test.png", width: 80%),
  caption: [`bigfile` 运行结果],
) <fig-bigfile-test>

运行 `usertests` 可以得到如下结果：

#figure(
  image("..\assets\largefile-usertests.png", width: 30%),
  caption: [`usertests` 部分运行结果],
) <fig-largefile-usertests>

运行 `./grade-lab-fs bigfile` 进行评测，得到如下结果：

#figure(
  image("..\assets\bigfile-grade.png", width: 80%),
  caption: [`bigfile` 评测结果],
) <fig-bigfile-grade>

=== 实验小结

通过本次实验，我成功扩展了 xv6 文件系统，提高了最大文件的大小。通过为 `inode` 增加一个二级间接块，成功将最大文件的大小从 268 个块扩展到了 65803 个块。实验过程中，我通过阅读文档与源码，深入了解了 xv6 操作系统的文件系统，知道了 xv6 文件系统的数据结构，并通过修改 `bmap()` 函数实现了文件的逻辑块与物理块之间的映射。通过本次实验，我更加深入地理解了文件系统的内部结构与工作原理。

== Symbolic links

=== 实验目的

+ 本次实验将向 xv6 添加符号链接（软链接） `symlink(char *target, char *path)` 系统调用。
+ 符号链接通过路径名引用链接的文件。不同于硬链接只能指向同一磁盘上的文件，符号链接跨越不同的磁盘设备。
+ 通过实现该系统调用，了解使用路径名进行查找的工作原理。

=== 实验步骤

+ 在 `Makefile` 的 `UPROGS` 中添加 `$U/_symlinktest`。
+ 在 `user/user.h` 中添加系统调用的原型：```c int symlink(char*, char*); ```
+ 在 `user/usys.pl` 中添加存根：```perl entry("symlink"); ```
+ 在 `kernel/syscall.h` 中添加系统调用编号：```c #define SYS_symlink 22 ```
+ 在 `kernel/syscall.c` 中新建一个系统调用号到名称的索引：
  #blockquote[
  ```c
  extern uint64 sys_symlink(void);

  static uint64 (*syscalls[])(void) = {
    ...
  [SYS_symlink] sys_symlink,
  };
  ```
  ]
+ 在 `kernel/stat.h` 中添加一个新文件类型 `T_SYMLINK`，用于标识一个文件是否为符号链接：```c #define T_SYMLINK 4 ```
+ 在 `kernel/fcntl.h` 中添加新标志位 `O_NOFOLLOW`，用于 `open()` 系统调用。这里的标志使用按位或运算进行组合，因此新增标志不应与已有标志重叠：```c #define O_NOFOLLOW 0x004 ```

+ 在 `kernel/sysfile.c` 中实现系统调用 `sys_symlink()`：
  + 先创建一个 `inode` 并设置类型为 `T_SYMLINK`：
  #blockquote[
  ```c
  struct inode *ip;

  begin_op();
  if ((ip = create(path, T_SYMLINK, 0, 0)) == 0) {
    end_op();
    return -1;
  }
  ```
  ]
  + 然后向这个 `inode` 中写入目标文件的路径：
  #blockquote[
  ```c
  if (writei(ip, 0, (uint64)target, 0, MAXPATH) != MAXPATH) {
    iunlockput(ip);
    end_op();
    return -1;
  }
  ```
  ]
+ 在 `kernel/fs.h` 中定义符号链接的最大递归深度 `NSYMLINK` 为 10：
  #blockquote[
  ```c
  #define NSYMLINK 10  // 符号链接最大递归深度
  ```
  ]
+ 然后修改 `open()` 系统调用，在 `sys_open` 中添加对符号链接的处理：
  + 对于符号链接，需要打开它所指向的目标文件。
  + 如果目标文件也为符号链接，则需要递归地打开链接，直到一个非链接文件为止。
  #blockquote[
  ```c
  if (ip->type == T_SYMLINK && !(omode & O_NOFOLLOW)) {
    int cycle = 0;
    char target[MAXPATH];
    // 递归打开符号链接
    while (ip->type == T_SYMLINK) {
      // 递归深度大于 NSYMLINK 时终止递归
      if (cycle == NSYMLINK) {
        iunlock(ip);
        end_op();
        return -1;
      }
      cycle++;
      readi(ip, 0, (uint64)target, 0, MAXPATH);
      iunlockput(ip);
      if ((ip = namei(target)) == 0) {
        end_op();
        return -1;
      }
      ilock(ip);
    }
  }
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行 `symlinktest` 可以得到如下结果：

#figure(
  image("..\assets\symlinktest.png", width: 40%),
  caption: [`symlinktest` 运行结果],
) <fig-symlinktest>

运行 `usertests` 可以得到如下结果：

#figure(
  image("..\assets\symlink-usertests.png", width: 45%),
  caption: [`usertests` 部分运行结果],
) <fig-symlink-usertests>

运行 `./grade-lab-fs symlinktest` 进行评测，得到如下结果：

#figure(
  image("..\assets\symlink-grade.png", width: 80%),
  caption: [`symlink` 评测结果],
) <fig-symlink-grade>

=== 实验小结

通过本次实验，我成功实现向 xv6 操作系统添加了符号链接的系统调用，使它支持创建符号链接文件，从而可以跨越设备通过路径名引用其他文件。实验过程中，我学会了如何基于路径名进行查找，并递归打开符号链接直到非链接文件。此外，为避免符号链接文件成环，我设置了符号链接的最大深度，从而提高程序的效率，保障了程序的安全性。这让我对符号链接的原理与实现有了更加深入的理解，也加深了我对 xv6 的文件系统的了解。

