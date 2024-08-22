#import "@preview/ilm:1.2.1": *

= Lab: Page Tables <pgtbl>

== 实验概述

本实验将探索页表并对其进行修改，以加快某些系统调用的速度，并检测已哪些页已被访问。

开始编码之前，阅读 #link("https://pdos.csail.mit.edu/6.828/2021/xv6/book-riscv-rev2.pdf")[xv6 book] 的第 3 章以及相关源文件：

+ `kern/mlayout.h`：用于捕捉内存布局。
+ `kern/vm.c`：包含大部分虚拟内存（VM）代码。
+ `kernel/kalloc.c`：包含分配和释放物理内存的代码。

此外还需要查阅 #link("https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMFDQC-and-Priv-v1.11/riscv-privileged-20190608.pdf")[RISC-V privileged architecture manual]。

开始实验前需要使用 ```bash git checkout pgtbl``` 先切换到 `pgtbl` 分支，将代码复制到 pgtbl 目录下。

== 加速系统调用

=== 实验目的

+ 一些操作系统会在用户空间和内核之间共享只读区域中的数据来加快某些系统调用的速度，以减少用户态到内核态之间的消耗。
+ 本实验旨在学习如何将映射插入到页表中，首先需要在 xv6 中的 `getpid()` 系统调用中实现这一优化。

=== 实验步骤

+ 本次实验中，`ugetpid()` 已经在 `user/ulib.c` 中定义了，并自动使用 `USYSCALL` 映射来获取进程的 `PID`。当各进程被创建时，会在 `USYSCALL`（`kernel/memlayout.h` 中定义的虚拟地址）处映射一个只读页面。在该页的开头，会存放一个 `struct usyscall`（也在 `kernel/memlayout.h` 中定义），并将其初始化为存储当前进程的 `PID`。

+ 首先在 `kernel/proc.h` 的 `proc` 结构体中定义物理存储空间的指针，在进程创建时初始化这样一个指针，保存共享页面的地址：

  #blockquote[
  ```c
  struct usyscall *usyscallpage;
  ```
  ]

+ 在 `kernel/proc.h` 的 `proc_pagetable()` 中执行映射操作。我们使用 `mappages()` 函数将该页面映射到用户空间的地址 `USYSCALL` 上，并设置权限为只读，这样就可以在用户空间的 `ugetpid()` 函数中直接读取这个页面获取当前进程的 PID：

  #blockquote[
  ```c
  pagetable_t
  proc_pagetable(struct proc *p)
  {
    ...
    if(mappages(pagetable, USYSCALL, PGSIZE, 
                (uint64)(p->usyscallpage), PTE_R | PTE_U) < 0) {
      // 如果映射失败，则恢复上述页
      uvmunmap(pagetable, TRAMPOLINE, 1, 0);
      uvmunmap(pagetable, TRAPFRAME, 1, 0);
      uvmfree(pagetable, 0);
      return 0;
    }

    return pagetable;
  }
  ```
  ]

+ 当页释放时也应该解除上述映射关联：

  #blockquote[
  ```c
   void
   proc_freepagetable(pagetable_t pagetable, uint64 sz)
   {
       uvmunmap(pagetable, TRAMPOLINE, 1, 0);
       uvmunmap(pagetable, TRAPFRAME, 1, 0);
       uvmunmap(pagetable, USYSCALL, 1, 0);
       uvmfree(pagetable, sz);
   }
  ```
  ]

+ 在 `allocproc()` 函数中，为每个新进程的进程分配一个只读页：

  #blockquote[
  ```c
  // 为新进程分配一个只读页
  if ((p->usyscallpage = (struct usyscall *)kalloc()) == 0) {
    freeproc(p);
    release(&p->lock);
    return 0;
  }
  // 将 pid 移至共享页中
  memmove(p->usyscallpage, &p->pid, sizeof(int));
  ```
  ]

+ 在 `kernel/proc.c` 的 `freeproc()` 函数中释放之前分配的只读页：

  #blockquote[
  ```c
  if(p->usyscallpage)
    kfree((void*)p->usyscallpage);
  p->usyscallpage = 0;
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行 `./grade-lab-pgtbl ugetpid` 进行评测，得到如下结果：

#figure(
  image("..\assets\ugetpid-grade.png", width: 80%),
  caption: [`ugetpid` 评测结果],
) <fig-ugetpid-grade>

=== 实验小结

实验过程中，最初由于权限设置错误，未在 `proc_pagetable()` 中映射 PTE 时仅将权限设置为 `PTE_R`，使得用户空间尝试写入只读页时导致错误。

#figure(
  image("..\assets\ugetpid-error.png", width: 80%),
  caption: [测试过程中的报错],
) <fig-ugetpid-error>

经过查阅文档和调试后，允许用户空间访问页表，将权限设置为 `PTE_R | PTE_U` 即可。此外值得注意的是，xv6 中代码或数据段由操作系统负责，用户程序不应该直接写入，因此这里不能设置 `PTE_W` 权限。

通过本次实验，我了解了如何通过在用户空间和内核之间共享只读数据区域的方式，来加快系统调用的执行速度。这种方式减少了内核和黔江空间之间数据传输的次数，优化了系统调用。并且通过动手实现这种优化，理解了如何在进程创建时进行页面映射并正确设置权限位，让我更加深入地理解了系统调用的工作原理，更加清晰地理解了操作系统的工作流程，也极大增强了我解决问题的能力。

== 打印页表

=== 实验目的

+ 编写一个 `vmprint()` 函数，用于打印 RISC-V 页表内容。
+ 通过该实验，实现页表布局的可视化，并在这个过程中了解页表的三级结构。

=== 实验步骤

+ 在 `kernel/defs.h` 中定义 `vmprint` 的原型，后续将在 `exec.c` 中调用。该函数接受一个页表和页表层级作为参数，并按要求的格式打印该页表：

  #blockquote[
  ```c
  void vmprint(pagetable_t, int);
  ```
  ]

+ 参考 `freewalk` 函数，在 `kernel/vm.c` 中编写 `vmprint` 函数。函数中循环遍历各页表的各个级别，并打印每个 PTE 的信息，然后使用 `PTE2PA` 宏从页表项中提取出 PTE 的物理地址，递归调用 `vmprint` 函数打印下一级页表的信息：

  #blockquote[
  ```c
  void
  vmprint(pagetable_t pgtbl, int level)
  {
    if (level == 0)
      printf("page table %p\n", pgtbl);
  
    for (int i = 0; i < 512; i++) {
      pte_t pte = pgtbl[i];
      if (pte & PTE_V) {
        for (int j = 0; j <= level; j++)
          printf("..");
        printf("%d: pte %p pa %p\n", i, (uint64)pte, (uint64) PTE2PA(pte));
      }
  
      if ((pte & PTE_V) && (pte & (PTE_R | PTE_W | PTE_X)) == 0) {
        uint64 child = PTE2PA(pte);
        vmprint((pagetable_t) child, level + 1);
      }
    }
  }
  ```
  ]

+ 最后，在 `kernel/exec.c` 中 `exec()` 函数的 `return argc;` 语句之前调用 `vmprint`，以在执行 `init` 进程时打印第一个进程的页表：

  #blockquote[
  ```c
  if (p->pid == 1)
    vmprint(p->pagetable, 0);
  ```
  ]

+ 启动 qemu 模拟器即可查看到 `vmprint()` 的调用结果。

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行测试结果如下：

#figure(
  image("..\assets\vmprint-test.png", width: 80%),
  caption: [`vmprint` 调用结果],
) <fig-vmprint-test>

运行 `./grade-lab-pgtbl xargs` 进行评测，得到如下结果：

#figure(
  image("..\assets\vmprint-grade.png", width: 80%),
  caption: [`vmprint` 评测结果],
) <fig-vmprint-grade>

=== 实验小结

实验过程中，由于程序逻辑上的问题，输出的格式并不符合题目要求。而后通过修改调试，使得 `vmprint` 函数可以按题目要求格式输出页表信息。

通过本次实验，我成功实现了可以打印页表信息的 `vmprint` 函数，可以按照格式输出 PTE 索引和物理地址等信息。通过这些信息，我更加清晰直观地理解了 xv6 的页表结构和层次关系。在这个过程中，我学会了如何在内核中使用位操作和相关宏定义，能够通过递归遍历页表的方式打印出整个页表的内容。

== 检测哪些页已访问

=== 实验目的

+ 一些垃圾回收器可以从哪些页已被访问的信息中获益。在本次实验中，将为 xv6 添加一个 `pgaccess()` 系统调用，通过检查 RISC-V 页表中的访问位来检测并向用户空间报告这些信息。
+ 该系统调用需要三个参数：需要检查的用户页面的起始虚拟地址、要检查的页面数、一个缓冲区的用户地址用于将结果存储到位掩码中。

=== 实验步骤

+ 首先需要在 `kernel/riscv.h` 中定义 `PTE_A` 访问位。先查阅 RISC-V 手册，可以找到如下结构图：

  #figure(
    image("../assets/risc-v-address.png", width: 80%),
  ) <fig-risc-v-address>
  根据结构图可以知道，在 RISC-V 架构中，页表项的第 6 位用于表示访问位，指示是否访问过对应的物理页。因此可以在 `riscv.h` 中做出如下设置：

  #blockquote[
  ```c
  #define PTE_A (1L << 6) // access bit
  ```
  ]

+ 由于添加到系统调用、用户内核接口等已经完成，我们只需要在 `kernel/sysproc.c` 中实现 `sys_pgaccess()` 函数即可：
  + 首先使用 `argaddr()` 和 `argint()` 获取并解析参数。系统调用需要的三个参数的类型应该分别为 `uint64`、`int` 和 `uint64`。

    #blockquote[
    ```c
    uint64 va;            // 需要检查的用户页面的起始虚拟地址
    int pgnum;            // 要检查的页面数
    uint64 bitmask_addr;  // 缓冲区的用户地址，用于将结果存储到位掩码中

    argaddr(0, &va);
    argint(1, &pgnum);
    argaddr(2, &bitmask_addr);
    ```
    ]
  + 接着使用 `walk()` 找到正确的 PTE。
  + 在内核中创建一个临时缓冲区 `bitmask`，然后遍历页将 PTE_A 访问位被设置过的页相应的位设置为 1。
  + 检查过 PTE_A 访问位后清除 `PTE_A`，否则就无法确定上次调用 `pgaccess()` 后是否访问过该页。

    #blockquote[
    ```c
    uint64 bitmask = 0;
    pte_t *pte;
    struct proc *p = myproc();

    for (int i = 0; i < pgnum; i++) {
      if (va >= MAXVA)
        return -1;

      pte = walk(p->pagetable, va, 0);
      if (pte == 0)
        return -1;

      if (*pte & PTE_A) {
        bitmask |= (1L << i);
        *pte &= (~PTE_A);
      }
      va += PGSIZE;
    }
    ```
    ]
  + 使用 `copyout()` 将内核中的位掩码缓冲区的内容复制到用户空间指定位置：
    #blockquote[
    ```c
    if (copyout(p->pagetable, bitmask_addr, (char*)&bitmask, sizeof(bitmask)) < 0)
      return -1;
    ```
    ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行 `./grade-lab-pgtbl pgtbltest` 进行评测，得到如下结果：

#figure(
  image("..\assets\pgaccess-grade.png", width: 80%),
  caption: [`pgaccess` 系统调用评测结果],
) <fig-pgaccess-grade>

#pagebreak()

=== 实验小结

在本次实验中，我成功实现了 `pgaccess()` 系统调用，可以检查并打印用户访问的页。在实验过程中，我深入了解了内核代码的组织结构和运行方式，以及如何将用户态的请求转换为内核态的操作，并了解了如何从用户空间传递参数到内核空间。这些加深了我对于操作系统内存管理机制的理解，使得我对上层算法与底层硬件逻辑之间的联系有了更深的认识。

