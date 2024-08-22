#import "@preview/ilm:1.2.1": *

= Lab: System Calls <syscall>

== 实验概述

在 @util 中，我使用系统调用编写了一些实用程序。在 Lab 2 中，我们将为 xv6 添加一些新的系统调用，这将帮助我理解它们是如何工作的，并让我接触到 xv6 内核的一些内部特性。

开始编码之前，阅读 #link("https://pdos.csail.mit.edu/6.828/2021/xv6/book-riscv-rev2.pdf")[xv6 book] 的第 2 章、第 4 章的 4.3 节和 4.4 节以及相关源文件：

+ 系统调用的用户空间代码在 `user/user.h` 和 `user/usys.pl` 中。
+ 内核空间代码是 `kernel/syscall.h` 和 `kernel/syscall.c` 。
+ 与进程相关的代码是 `kernel/proc.h` 和 `kernel/proc.c` 。

开始实验前需要使用 ```bash git checkout syscall``` 先切换到 `syscall` 分支，将代码复制到 syscall 目录下。

== System call tracing

=== 实验目的

+ 本实验旨在实现一个系统调用跟踪功能，该功能将有助于后续实验室任务的调试工作。
+ 我们将开发新的跟踪系统调用，设计并实现一个新的系统调用 `trace`，该系统调用接受一个整数参数 `mask`。`mask` 中被设置的位将指示哪些系统调用需要被跟踪。
+ 我们需要修改 xv6 内核，使得每当一个系统调用即将返回时，如果该系统调用的编号在 `mask` 中被设置，内核会打印出一行信息，包括进程 ID、系统调用的名称及其返回值（无需打印系统调用参数）。
+ 此外需要使跟踪递归生效，确保 `trace` 系统调用能够为调用它的进程以及其后续通过 `fork` 创建的所有子进程启用跟踪功能，同时不影响其他未调用此功能的进程。

=== 实验步骤

+ 阅读 `user/trace.c`，了解其逻辑。
+ 在 `Makefile` 的 `UPROGS` 中添加 `$U/_trace`。
+ 在 `user/user.h` 中添加系统调用的原型：

  #blockquote[
  ```c
  int trace(int);
  ```
  ]

+ 在 `user/usys.pl` 中添加存根，这个文件会被汇编为 `usys.S`：

  #blockquote[
  ```perl
  entry("trace");
  ```
  ]

+ 在 `kernel/syscall.h` 中添加系统调用编号：

  #blockquote[
  ```c
  #define SYS_trace 22
  ```
  ]

+ 在 `kernel/proc.h` 中定义的 `proc` 结构记录着进程的状态，在这里需要向 `proc` 中添加 `int` 型变量 `mask` 用于记录掩码。
+ 在 `kernel/sysproc.c` 中添加从用户态到内核态系统调用的参数传递入口，使用 `argint()` 函数获取用户态的系统调用命令的参数，将参数存储在 `proc` 的新变量中：

  #blockquote[
  ```c
  uint64
  sys_trace(void)
  {
    int mask;
    if (argint(0, &mask) < 0)
      return -1;
    myproc()->mask = mask;
    return 0;
  }
  ```
  ]

+ 在 `kernel/syscall.c` 中新建一个系统调用号到名称的索引（系统调用号从 1 开始，因此第一个名称为空），实现在 `syscall()` 函数中输出 `trace` 信息的功能：

  #blockquote[
  ```c
  ...
   extern uint64 sys_trace(void);

   char *syscalls_names[30] = {
       "",     "fork",  "exit",   "wait", "pipe",  "read",  "kill",   "exec", "fstat", "chdir", "dup",   "getpid",
       "sbrk", "sleep", "uptime", "open", "write", "mknod", "unlink", "link", "mkdir", "close", "trace", "sysinfo",
   };

  static uint64 (*syscalls[])(void) = {
  ...
    [SYS_trace]   sys_trace,
    [SYS_sysinfo]   sys_sysinfo,
  }
  ```
  ]

+ 修改 `kernel/proc.c` 中的 `fork()` 函数，使 `fork()` 在复制时同时将父进程的掩码复制到子进程中，以跟踪子进程的特定系统调用：

  #blockquote[
  ```c
  np->mask = p->mask;
  ```
  ]

+ 在 `syscall()` 函数中实现输出逻辑，需要输出 `pid`、系统调用名和返回值（存储在 `trapframe->a0` 中）：

  #blockquote[
  ```c
  void
  syscall(void)
  {
    int num;
    struct proc *p = myproc();

    num = p->trapframe->a7;
    if(num > 0 && num < NELEM(syscalls) && syscalls[num]) {
      p->trapframe->a0 = syscalls[num]();

      // 打印调用信息
      if ((1 << num) & p->mask) {
        printf("%d: syscall %s -> %d\n", p->pid, syscalls_names[num], p->trapframe->a0);
      }
    } else {
      printf("%d %s: unknown sys call %d\n",
              p->pid, p->name, num);
      p->trapframe->a0 = -1;
    }
  }
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行测试结果如下：

#figure(
  image("../assets/trace-test.png", width: 80%),
  caption: [`trace` 测试结果],
) <fig-trace-test>

运行 `./grade-lab-syscall trace` 进行评测，得到如下结果：

#figure(
  image("../assets/trace-grade.png", width: 80%),
  caption: [`trace` 评测结果],
) <fig-trace-grade>

=== 实验小结

在本次实验中，我学会了如何在 xv6 内核中添加新的系统调用，并修改进程控制块以支持系统调用跟踪功能，这将在后续实验中提供更便利的调试功能，也理解了如何在内核中实现系统调用的功能。并且通过添加这个系统调用，我了解了如何在用户级程序中调用系统调用，通过 `syscall()` 函数调用系统调用，调用后转到 `kernel/sysproc.c` 中 `sys_*()` 的相关函数。加深了我对于操作系统的系统调用流程的了解。

== Sysinfo

=== 实验目的

+ 在本实验中，将添加一个系统调用 `sysinfo`，用于收集运行系统的信息。系统调用需要一个参数：指向 `struct sysinfo` 的指针（参见 `kernel/sysinfo.h`）。内核应填写该结构体的字段：`freemem` 字段应设置为可用内存的字节数，`nproc` 字段应设置为状态不是 `UNUSED` 的进程数。

=== 实验步骤

+ 在 `Makefile` 的 `UPROGS` 中添加 `$U/_sysinfotest`。
+ 在 `user/user.h` 中要预先声明 `struct sysinfo`，然后再声明 `sysinfo()` 的原型：

  #blockquote[
  ```c
  struct sysinfo;
  int sysinfo(struct sysinfo *);
  ```
  ]

+ 类似地，在 `user/usys.pl` 中添加存根 ```perl entry("sysinfo")```。
+ 在 `kernel/syscall.h` 中添加系统调用编号：

  #blockquote[
  ```c
  #define SYS_sysinfo 23
  ```
  ]

+ 在 `kernel/sysproc.c` 中添加 `sys_sysinfo` 函数：

  #blockquote[
  ```c
  uint64
  sys_sysinfo(void)
  {
    uint64 addr;
    struct sysinfo info;
    struct proc *p = myproc();
  
    if (argaddr(0, &addr) < 0)
      return -1;
  
    info.freemem = getfreemem();
    info.nproc = getnproc();
  
    if (copyout(p->pagetable, addr, (char*)&info, sizeof(info)) < 0)
      return -1;
  
    return 0;
  }
  ```
  ]

+ 参考 `kernel/sysfile.c` 的 `sys_fstat()` 和 `kernel/file.c` 中的 `filestat()`，用 `copyout()` 函数将 `struct sysinfo` 复制到用户空间。`copyout()` 函数定义见 `kernel/vm.c`。

+ 为收集可用内存数量，在 `kernel/kalloc.c` 中添加一个函数 `getfreemem` 函数。参考 `kernel/kalloc.c` 的 `kalloc()` 等函数，可以知道内核使用链表维护未使用的内存，链表的每个结点对应一个页表，计算该链表的结点数再乘页表大小 4KB 即可得到空闲内存字节数：

  #blockquote[
  ```c
  uint64
  getfreemem(void)
  {
    struct run *r;
    uint64 num = 0;
    acquire(&kmem.lock);
    r = kmem.freelist;
    while (r) {
      num++;
      r = r->next;
    }
    release(&kmem.lock);
    return num * PGSIZE;
  }
  ```
  ]

+ 为收集进程数量，在 `kernel/proc.c` 中添加一个函数 `getnproc` 函数。参考 `kernel/proc.c` 的 `allocproc()` 等函数，可以知道内核使用数组 `proc[NPROC]` 维护进程，计算该数组大小即可得到进程数量：

  #blockquote[
  ```c
  uint64
  getnproc(void)
  {
    struct proc *p;
    uint64 num = 0;
    for (p = proc; p < &proc[NPROC]; p++) {
      acquire(&p->lock);
      if (p->state != UNUSED)
        num++;
      release(&p->lock);
    }
    return num;
  }
  ```
  ]

+ 在 `kernel/defs.h` 中添加上述两个函数的原型。

+ 在 xv6 shell 中运行程序进行测试。

#pagebreak()

=== 评测结果

运行测试结果如下：

#figure(
  image("..\assets\sysinfo-test.png", width: 40%),
  caption: [`sysinfo` 测试结果],
) <fig-sysinfo-test>

运行 `./grade-lab-syscall sysinfo` 进行评测，得到如下结果：

#figure(
  image("..\assets\sysinfo-grade.png", width: 80%),
  caption: [`sysinfo` 评测结果],
) <fig-sysinfo-grade>

=== 实验小结

本次实验中，我成功为 xv6 系统添加了一个新的的系统调用 `sysinfo`，实现了运行系统信息的收集功能，可以获得可用内存数与进程数等信息。实验过程中，通过阅读源码，我了解到了 xv6 系统使用的 `kmem` 链表等基础数据结构，并基于对这些基础数据的认识，针对性地追踪这些信息，完成了系统信息的收集。让我更加深刻地理解了内核的功能和实现。

