#import "@preview/ilm:1.2.1": *

= Lab: Copy-on-Write Fork for xv6 <cow>

== 实验概述

虚拟内存提供了一种间接性：内核可以将 PTE 标记为无效 (invalid) 或者只读 (read-only) 来阻止内存引用，并且导致页面故障 (page faults) 。在计算机系统中有一个说法，任何系统问题都能通过一定的间接性来解决。本次实验探索了一个例子：写时复制 copy-on write fork。

xv6 中的 `fork()` 系统调用会将父进程的所有用户空间内存复制到子进程中。如果父进程很大，拷贝可能需要很长时间。更糟糕的是，这些工作往往会被浪费掉：例如，子进程中的 `fork()` 之后紧跟的 `exec()` 会导致子进程丢弃复制的内存。

因此，可以采取更加高效的策略，即推迟复制的时机，只有子进程实际需要物理内存拷贝时再进行分配和复制物理内存页面。

COW fork() 只为子进程创建一个分页表，用户内存的 PTE 指向父进程的物理页面。父进程和子进程中的所有 `PTE` 都被标记为不可写。当任一进程试图写入其中一个 `COW` 页时，CPU 将强制产生页面错误。内核页面错误处理程序检测到这种情况时，将为出错进程分配一页物理内存，将原始页复制到新页中，并修改出错进程中的相关 `PTE` 指向新的页面，将 PTE 标记为可写。这样就完成了复制的延迟，也即写时拷贝。

开始实验前需要使用 ```bash git checkout cow``` 先切换到 `cow` 分支，将代码复制到 cow 目录下。

== 实现 Copy-on Write 

=== 实验目的

+ 了解如何通过写时复制技术优化进程的 `fork` 操作。
+ 在 xv6 操作系统中实现写时复制的 `fork` 功能。
+ 不同于传统的 `fork()` 系统调用，COW 版的 `fork()` 使用延迟分配和复制物理内存页面，只在需要时才进行复制，提高性能节省资源。

#pagebreak()

=== 实验步骤

+ 查看 `kernel/riscv.h` ，了解对于页表标志 (page table flags) 有用的宏和定义。在 `kernel/riscv.h` 中设置新的 PTE 标记位，标记一个页面是否采用 COW 机制。可以使用 RISC-V PTE 第 8 位的 `RSW` 位来指示：
  #blockquote[
  ```c
  #define PTE_COW (1L << 8) // 使用 RSW 位作为 COW 标识位
  ```
  ]
+ 修改` kernel/vm.c `中的` uvmcopy()` 函数，将父进程的物理页映射到子进程，并清除子进程和父进程的 PTE 中的`PTE_W` 标志：
   + `fork` 会首先调用 `uvmcopy()` 给子进程分配内存空间。但是如果要实现 COW 机制，就需要在 fork 时不分配内存空间，让子进程和父进程同时共享父进程的内存页，并将其设置为只读，使用 `PTE_RSW` 位标记 COW 页。这样子进程没有使用到某些页的时候，系统就不会真正的分配物理内存。此时需要将对应的引用计数加一。\ 
      但如果原本页就是只读的，就不必要将它修改为 COW 页。
    #blockquote[
    ```c
    if (*pte & PTE_W) {
      // 设为只读
      *pte &= ~PTE_W;
      // 设置 COW 位
      *pte |= PTE_COW;
    }
    ...
    // if((mem = kalloc()) == 0)
    //   goto err;
    // memmove(mem, (char*)pa, PGSIZE);
    if(mappages(new, i, PGSIZE, (uint64)pa, flags) != 0){
      // kfree(mem);
      goto err;
    }

    // 索引计数加1
    if (add_pgref_count((void *)pa)) {
      goto err;
    }
    ```
    ]
+ 为使用引用计数，需要在 `kernel/kalloc.c` 中添加一个结构体用于维护物理页的引用数，`kernel/kalloc.c` 中的定义如下：
  #blockquote[
  ```c
  struct refcnt {
    struct spinlock lock;
    int count[PHYSTOP / PGSIZE];
  } pg_ref_count;
  ```
  ]
  还需要添加一个函数 `add_pgref_count` 为页表引用计数加一：
  #blockquote[
  ```c
  int
  add_pgref_count(void *pa)
  {
    if ((uint64)pa % PGSIZE)
      return -1;
    if ((char*)pa < end || (uint64)pa >= PHYSTOP)
      return -1;
  
    acquire(&pg_ref_count.lock);
    pg_ref_count.count[(uint64)pa / PGSIZE]++;
    release(&pg_ref_count.lock);
    return 0;
  }
  ```
  ]
  添加函数 `get_pgref_count` 用于获取引用数：
  #blockquote[
  ```c
  int
  get_pgref_count(void *pa)
  {
    return pg_ref_count.count[(uint64)pa / PGSIZE];
  }
  ```
  ]

+ 修改 `kalloc.c` 中的 `kinit()` 函数，对 `pg_ref_count` 的锁初始化：
  #blockquote[
  ```c
  void
  kinit()
  {
    initlock(&kmem.lock, "kmem");
    // 初始化 pg_ref_count 锁
    initlock(&pg_ref_count.lock, "pg_ref_count");
    freerange(end, (void*)PHYSTOP);
  }
  ```
  ]
+ 然后在 `kalloc()` 函数中初始化新分配的物理页的引用计数：
  #blockquote[
  ```c
  if(r) {
    acquire(&pg_ref_count.lock);
    pg_ref_count.count[(uint64)r / PGSIZE] = 1;
    release(&pg_ref_count.lock);
  }
  ```
  ]
+ 接着修改 `kfree()` 函数，仅当引用计数小于等于 0 的时候，才回收对应的页：
  #blockquote[
  ```c
  int temp;

  acquire(&pg_ref_count.lock);
  pg_ref_count.count[(uint64)pa / PGSIZE]--;
  temp = pg_ref_count.count[(uint64)pa / PGSIZE];
  release(&pg_ref_count.lock);

  if (temp > 0)
    return;
  ```
  ]

+ 修改 `kernel/trap.c` 下的 `usertrap()` 函数，使其能够识别页面故障（page fault）。当发生 COW 页面的页面故障时，使用 `kalloc()` 分配一个新的页面，将旧页面复制到新页面中，然后在父进程和子进程的 PTE 中设置 `PTE_W` 标志，允许写入。如果发生了 COW 页错误，并且没有剩余可用内存，那么就应该杀死该进程。
  #blockquote[
  ```c
  ...
  else if (r_scause() == 15) {
    // 缺页错误
    uint64 va = r_stval();
    if (va >= p->sz || is_cowpg(p->pagetable, va) != 1 || alloc_cowpg(p->pagetable, va) == 0)
      p->killed = 1;
  } else if((which_dev = devintr()) != 0){
    // ok
  ...
  ```
  ]
  + 要完成上述工作，需要首先使用 `is_cowpg` 函数判断当前页表是否为 COW 页表：
    #blockquote[
    ```c
    int
    is_cowpg(pagetable_t pg, uint64 va)
    {
      if (va > MAXVA)
        return -1;
    
      pte_t *pte = walk(pg, va, 0);
      if (pte == 0)
        return 0;
      if ((*pte & PTE_V) == 0 || (*pte & PTE_U) == 0 || (*pte & PTE_V) == 0)
        return 0;
      if ((*pte & PTE_COW))
        return 1;
      return 0;
    }
    ```
    ]
  + 然后使用 `alloc_cowpg` 函数分配物理页并复制内容：
    + `pagetable_t pagetable, uint64 va` 两个参数分别是页表和出现页面故障的虚拟地址。
    + 首先检查虚拟地址是否超出了最大虚拟地址。如果超出了，即操作失败。
    + 使用给定的页表和虚拟地址调用 `walk` 函数来获取页面的页表项（PTE）。如果 PTE 为 0，则表示页面不存在。
    + 然后查看有多少进程在使用当前页：如果只有一个进程在使用当前页，设置为可写并将 COW 标志位复位；如果有多个进程在使用当前页，则需要分配新的物理页。
    + 在分配新的内存页面后，不再需要旧的物理页面，使用 `kfree()` 函数来释放旧的页面，以便将其返回到内存池中，递减其引用计数，
    #blockquote[
    ```c
    void*
    alloc_cowpg(pagetable_t pg, uint64 va)
    {
      va = PGROUNDDOWN(va);
      if (va % PGSIZE != 0 || va > MAXVA)
        return 0;
    
      uint64 pa = walkaddr(pg, va);
      if (pa == 0)
        return 0;
    
      pte_t *pte = walk(pg, va, 0);
      if (pte == 0)
        return 0;
    
      int count = get_pgref_count((void*)pa);
      if (count == 1) {
        // 只有一个进程在使用当前页
        *pte = (*pte & ~PTE_COW) | PTE_W;
        return (void*)pa;
      }
      else {
        // 有多个进程在使用当前页
        char *mem = kalloc();
        if (mem == 0)
          return 0;
    
        memmove(mem, (char*)pa, PGSIZE);
    
        *pte = (*pte) & ~PTE_V;
    
        if (mappages(pg, va, PGSIZE, (uint64)mem, (PTE_FLAGS(*pte) & ~PTE_COW) | PTE_W) != 0) {
          kfree(mem);
          *pte = (*pte) | PTE_V;
          return 0;
        }
    
        kfree((void*)PGROUNDDOWN(pa));
        return (void*)mem;
      }
    }
    ```
    ]
+ 修改 `kernel/vm.c` 中的 `copyout()` 函数，使之在传递时可以正确传出物理页：
  #blockquote[
  ```c
  // 如果是 COW 页，则要分配新的物理页再复制
  if (is_cowpg(pagetable, va0) == 1)
    pa0 = (uint64)alloc_cowpg(pagetable, va0);
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行 `cowtest` 可以得到如下结果：

#figure(
  image("..\assets\cowtest.png", width: 25%),
  caption: [`cowtest` 运行结果],
) <fig-cowtest>

运行 `usertests` 可以得到如下结果：

#figure(
  image("..\assets\usertests-cow.png", width: 37%),
  caption: [`usertests` 部分运行结果],
) <fig-usertests-cow>

运行 `./grade-lab-cow` 进行评测，得到如下结果：

#figure(
  image("..\assets\cow-grade.png", width: 37%),
  caption: [`COW` 评测结果],
) <fig-cow-grade>

=== 实验小结

实验过程中处理页面故障时，我遇到了确定页面故障及获取异常代码和地址信息的问题。通过查阅 RISC-V 架构规范和相关文档，我逐步理解了异常处理的流程，并成功地在 `usertrap()` 函数中添加了对页面故障的处理逻辑。通过对异常代码、异常类型以及相关寄存器作用的深入理解，我能够正确识别和处理存储访问异常。

在运行 `usertests` 时，我还遇到了虚拟地址越界的错误问题。通过定位问题，发现是在 `is_cowpg()` 函数中没有正确处理越界的情况，导致错误的发生。通过添加适当的边界检查，解决了这个问题。

在本次实验中，我主要实现了写时复制的 `fork()` 功能，通过延迟分配和复制物理内存页面的过程，显著提高了 `fork()` 的效率，并在此过程中深化了对内存管理和异常处理的理解。在实验过程中，我学会了如何在 xv6 内核中实现 COW 技术，并深刻理解了 COW 技术的机制以及如何处理页面错误中断和正确管理物理页面引用计数。我认识到采用延迟分配的方法是一种有效提高性能的方法，核心思想是在真正需要时才分配资源。通过本次实验，我对操作系统内核的内存管理以及性能优化等方面有了更深刻的认识。
