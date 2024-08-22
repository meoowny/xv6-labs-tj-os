#import "@preview/ilm:1.2.1": *

= Lab: Mmap

== 实验概述

`mmap` 与 `munmap` 系统调用允许 UNIX 程序对其他地址空间进行细致的控制。它们可以用于在进程间共享内存、将文件映射到进程地址空间等，并作为用户级页面错误方案一部分。本实验将向 xv6 添加这两个系统调用。

开始实验前需要使用 ```bash git checkout mmap``` 先切换到 `mmap` 分支，将代码复制到 mmap 目录下。

== 实验目的

+ 实现 `mmap` 和 `munmap` 系统调用。

== 实验步骤

+ 在 `Makefile` 的 `UPROGS` 中添加 `$U/_mmaptest`。
+ 在 `user/user.h` 中添加系统调用的原型：
  #blockquote[
  ```c
  void *mmap(void*, int, int, int, int, uint);
  int munmap(void*, int);
  ```
  ]
+ 在 `user/usys.pl` 中添加存根：
  #blockquote[
  ```perl
  entry("mmap");
  entry("munmap");
  ```]
+ 在 `kernel/syscall.h` 中添加系统调用编号：
  #blockquote[
  ```c
  #define SYS_mmap 22
  #define SYS_munmap 23
  ```
  ]
+ 在 `kernel/syscall.c` 中新建一个系统调用号到名称的索引：
  #blockquote[
  ```c
  extern uint64 sys_mmap(void);
  extern uint64 sys_munmap(void);

  static uint64 (*syscalls[])(void) = {
    ...
  [SYS_mmap]    sys_mmap,
  [SYS_munmap]  sys_munmap,
  };
  ```
  ]
+ 在 `kernel/proc.h` 中定义 `vma` 结构体，用于保存内存映射信息，并在 `proc` 结构体中加入 `vma` 数组，用于记录映射的内存：
  #blockquote[
  ```c
  #define NVMA 16

  struct vma {
    uint64 addr;
    int len;
    int prot;
    int flags;
    int offset;
    int active;
    struct file *file;
  };

  struct proc {
    ...
    struct vma vma[NVMA];
  };
  ```
  ]
+ 在 `kernel/riscv.h` 中定义脏页标志位 `PTE_D`，表示页面已被修改：```c #define PTE_D (1L << 7) ```
+ 然后在 `kernel/vm.c` 中实现 `uvmgetdirty()` 和 `uvmsetdirtywrite()` 两个函数，用于读取和设置脏页标志位：
  #blockquote[
  ```c
  int
  uvmgetdirty(pagetable_t pagetable, uint64 va)
  {
    pte_t *pte = walk(pagetable, va, 0);
    if(pte == 0) {
      return 0;
    }
    return (*pte & PTE_D);
  }

  int
  uvmsetdirtywrite(pagetable_t pagetable, uint64 va)
  {
    pte_t *pte = walk(pagetable, va, 0);
    if(pte == 0) {
      return -1;
    }
    *pte |= PTE_D | PTE_W;
    return 0;
  }
  ```
  ]
+ 修改 `kernel/trap.c` 的 `usertrap()` 函数以实现物理页的懒加载，确保 `mmap` 不会分配物理内存或读取文件，出现缺页错误时才分配物理页：
  #blockquote[
  ```c
  ...
  } else if (r_scause() == 13 || r_scause() == 15) {
    // 缺页异常
    char *pa;
    uint64 va = PGROUNDDOWN(r_stval());
    struct vma *vma = 0;
    int flags = PTE_U;

    // 查找 VMA
    for (int i = 0; i < NVMA; i++) {
      if (p->vma[i].addr && va >= p->vma[i].addr && va < p->vma[i].addr + p->vma[i].len) {
        vma = &p->vma[i];
        break;
      }
    }
    if (vma == 0)
      goto err;

    // 设置映射页的 PTE
    if (r_scause() == 15 && (vma->prot & PROT_WRITE) && walkaddr(p->pagetable, va)) {
      if (uvmsetdirtywrite(p->pagetable, va))
        goto err;
    }
    else {
      if ((pa = kalloc()) == 0)
        goto err;

      memset(pa, 0, PGSIZE);
      ilock(vma->file->ip);
      if (readi(vma->file->ip, 0, (uint64)pa, va - vma->addr + vma->offset, PGSIZE) < 0) {
        iunlock(vma->file->ip);
        goto err;
      }
      iunlock(vma->file->ip);
      if (vma->prot & PROT_READ)
        flags |= PTE_R;
      if (r_scause() == 15 && (vma->prot & PROT_WRITE))
        flags |= PTE_W | PTE_D;
      if ((vma->prot & PROT_EXEC))
        flags |= PTE_X;
      if (mappages(p->pagetable, va, PGSIZE, (uint64) pa, flags) != 0) {
        kfree(pa);
        goto err;
      }
    }
  } else if((which_dev = devintr()) != 0){
    // ok
  } else {
  err:
  ...
  ```
  ]
+ 接下来在 `kernel/sysfile.c` 中实现系统调用 `sys_mmap()`：
  + 先解析调用的参数，并对参数进行检查：
    #blockquote[
    ```c
    struct proc *p = myproc();
    if (argaddr(0, &addr) < 0
      || argint(1, &len) < 0
      || argint(2, &prot) < 0
      || argint(3, &flags) < 0
      || argfd(4, 0, &file) < 0
      || argint(5, &offset) < 0)
      return -1;
  if (flags != MAP_SHARED && flags != MAP_PRIVATE)
    return -1;

    if (!(file->writable) && (prot & PROT_WRITE) && (flags == MAP_SHARED))
      // 无法写入
      return -1;

    if (len < 0 || offset < 0 || offset % PGSIZE)
      return -1;
    ```
    ]
  + 然后将传入的地址映射到对应地址，不过由于使用了懒加载，只有实际需要写入物理页时才会触发中断申请到物理页，因此这里仅仅是找到空闲 `VMA` 并写入相应参数：
    #blockquote[
    ```c
    for (int i = 0; i < NVMA; i++) {
      if (p->vma[i].addr == 0) {
        vma = &p->vma[i];
        break;
      }
    }
    if (!vma)
      return -1;

    addr = TRAPFRAME - 10 * PGSIZE;
    for (int i = 0; i < NVMA; i++) {
      if (p->vma[i].addr)
        addr = max(addr, p->vma[i].addr + p->vma[i].len);
    }
    addr = PGROUNDUP(addr);
    if (addr + len > TRAPFRAME)
      return -1;
    vma->addr = addr;   
    vma->len = len;
    vma->prot = prot;
    vma->flags = flags;
    vma->offset = offset;
    vma->file = file;
    filedup(file);
    ```
    ]
+ 接着实现 `kernel/sys_munmap()` 系统调用，以取消虚拟内存的映射：
  + 先解析调用的参数，并对参数进行检查：
    #blockquote[
    ```c
    if (argaddr(0, &addr) < 0 || argint(1, &len) < 0)
      return -1;
    if (addr % PGSIZE || len < 0)
      return -1;
    ```
    ]
  + 然后根据 `addr` 和 `len` 查找对应的 VMA：
    #blockquote[
    ```c
    struct proc *p = myproc();
    struct vma *vma = 0;
    for (int i = 0; i < NVMA; i++) {
      if (p->vma[i].addr && addr >= p->vma[i].addr && addr + len <= p->vma[i].addr + p->vma[i].len) {
        vma = &p->vma[i];
        break;
      }
    }
    if (!vma)
      return -1;
    if (len == 0)
      return 0;
    ```]
  + 根据 VMA 的标志位决定是否写回文件：
    #blockquote[
    ```c
    if (vma->flags & MAP_SHARED) {
      // 如果是共享映射，需要把文件内容写回
      maxsz = ((MAXOPBLOCKS - 1 - 1 - 2) / 2) * BSIZE;
      for (va = addr; va < addr + len; va += PGSIZE) {
        if (uvmgetdirty(p->pagetable, va) == 0) {
          continue;
        }
        n = min(PGSIZE, addr + len - va);
        for (int i = 0; i < n; i += n1) {
          n1 = min(maxsz, n - i);
          begin_op();
          ilock(vma->file->ip);
          if (writei(vma->file->ip, 1, va + i, va - vma->addr + vma->offset + i, n1) != n1) {
            iunlock(vma->file->ip);
            end_op();
            return -1;
          }
          iunlock(vma->file->ip);
          end_op();
        }
      }
    }
    ```]
  + 最后取消映射，并清空 VMA：
    #blockquote[
    ```c
    uvmunmap(p->pagetable, addr, (len - 1) / PGSIZE + 1, 1);

    if (addr == vma->addr && len == vma->len) {
      vma->addr = 0;
      vma->len = 0;
      vma->offset = 0;
      vma->flags = 0;
      vma->prot = 0;
      fileclose(vma->file);
      vma->file = 0;
    } else if (addr == vma->addr) {
      vma->addr += len;
      vma->offset += len;
      vma->len -= len;
    } else if (addr + len == vma->addr + vma->len) {
      vma->len -= len;
    } else {
      panic("unexpected munmap");
    }
    ```
    ]
+ 然后修改 `kernel/vm.c` 中的 `uvmunmap()` 函数和 `uvmcopy()` 函数，以正确取消映射：
  #blockquote[
  ```c
  // uvmunmap
  if((*pte & PTE_V) == 0)
    continue;
    // panic("uvmunmap: not mapped");

  // uvmcopy
  if((*pte & PTE_V) == 0)
    continue;
    // panic("uvmcopy: page not present");
  ```
  ]

+ 完成上述工作后，修改 `kernel/proc.c` 中的 `fork()` 函数，确保父子进程具有相同的映射关系：
  #blockquote[
  ```c
  ...
  acquire(&np->lock);

  // 复制 VMA 信息到子进程
  for (int i = 0; i < NVMA; i++) {
    if (p->vma[i].addr) {
      np->vma[i] = p->vma[i];
      filedup(np->vma[i].file);
    }
  }
  ...
  ```
  ]
+ 最后修改 `exit()` 函数，确保进程退出时可以像 `munmap()` 一样对文件映射内存取消映射：
  #blockquote[
  ```c
  ...
  // 取消进程的文件内存映射
  for (int i = 0; i < NVMA; i++) {
    if (p->vma[i].addr == 0)
      continue;

    struct vma *vma;
    uint MAXSZ = ((MAXOPBLOCKS - 1 - 1 - 2) / 2) * BSIZE;
    uint n, n1;

    vma = &p->vma[i];
    if (vma->flags & MAP_SHARED) {
      for (uint64 va = vma->addr; va < vma->addr + vma->len; va += PGSIZE) {
        if (uvmgetdirty(p->pagetable, va) == 0)
          continue;

        n = min(PGSIZE, vma->addr + vma->len - va);
        for (int j = 0; j < n; j += n1) {
          n1 = min(MAXSZ, n - i);
          begin_op();
          ilock(vma->file->ip);
          if (writei(vma->file->ip, 1, va + i, va - vma->addr + vma->offset + i, n1) != n1) {
            iunlock(vma->file->ip);
            end_op();
            panic("exit: writei failed");
          }
          iunlock(vma->file->ip);
          end_op();
        }
      }
    }
    uvmunmap(p->pagetable, vma->addr, (vma->len - 1) / PGSIZE + 1, 1);
    vma->addr = 0;
    vma->len = 0;
    vma->offset = 0;
    vma->flags = 0;
    vma->offset = 0;
    fileclose(vma->file);
    vma->file = 0;
  }
  ...
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

== 评测结果

运行 `mmaptest` 可以得到如下结果：

#figure(
  image("..\assets\mmaptest.png", width: 45%),
  caption: [`mmaptest` 运行结果],
) <fig-mmaptest>

运行 `make grade` 进行评测，得到如下结果：

#figure(
  image("..\assets\mmap-grade.png", width: 50%),
  caption: [`make grade` 评测结果],
) <fig-mmap-grade>

== 实验小结

通过本次实验，我深入了解 `mmap` 与 `munmap` 系统调用的实现原理，成功在 xv6 操作系统中实现了内存映射功能，为 xv6 添加了这两个系统调用。本次实验涉及多方面知识，为了提供 `mmap` 与 `munmap` 的系统调用，需要修改操作系统的系统调用接口，这就涉及到了用户态与内核态的切换和参数的传递与返回值的获取（@syscall）。将文件映射到进程的地址空间时，需要实现虚拟内存与物理内存间的映射，还需要使用惰性分配机制，用到了类似于 `COW` 实验（@cow）中的思路，大大提高了资源利用率。为了处理懒加载带来的缺页错误，还需要在 `usertrap` 中增加中断处理（@alarm），当出现缺页错误时才分配物理页。
这些加深了我对 xv6 操作系统的理解，让我对操作系统各部分如何紧密配合才带来了更好的用户体验有了更直观清晰的认识。

