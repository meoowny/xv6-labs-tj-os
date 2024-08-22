#import "@preview/ilm:1.2.1": *

= Lab: Locks

== 实验概述

锁机制常用于在并发编程中解决同步互斥问题，但是过多的锁冲突往往会使得多核机器的并行性变差。在本实验中，我们将重新设计代码，通过修改锁相关的数据结构减少对锁的竞争，以提升系统并行度。

开始编码之前，阅读 #link("https://pdos.csail.mit.edu/6.828/2021/xv6/book-riscv-rev2.pdf")[xv6 book] 的相关内容：

/ 第 6 章: “锁”与相应的代码。
/ 第 3.5 章: “代码：物理内存分配器”。
/ 第 8.1 至 8.3 章: “概述”、“缓冲区缓存层”与“代码：缓冲区缓冲”。

开始实验前需要使用 ```bash git checkout lock``` 先切换到 `lock` 分支，将代码复制到 lock 目录下。

== Memory allocator

=== 实验目的

+ 实现每个 CPU 的空闲列表，每个列表都有自己的锁。
+ 通过这样的方式使不同 CPU 上的内存分配与释放操作可以并行进行。
+ 当一个 CPU 的自己列表为空时，能够从其他 CPU 的空闲列表中获取部分内存。
+ 通过这种对内存分配器的优化，减少锁竞争，提升多核系统下的内核性能。

=== 实验步骤

+ 代码未修改前，所有内存块都由一个锁管理，因此如果有多个进程同时获取内存，就会出现锁竞争，极大降低系统并行性，造成较大的性能浪费。为优化内存分配器性能，就可以通过为各 CPU 单独维护一个空闲列表存储内核内存空间，减少锁竞争。

+ 参考 `kernel/param.h` 中 `NCPU` 的宏定义，将 `kernel/kalloc.c` 中的 `kmem` 改为大小为 `NCPU` 的数组，每个元素含有一个锁和一个指向空闲列表的指针：
  #blockquote[
  ```c
  struct {
    struct spinlock lock;
    struct run *freelist;
  } kmem[NCPU];
  ```
  ]
+ 修改 `kinit()` 函数以初始化所有 CPU 上的空闲列表：
  #blockquote[
  ```c
  char kmem_name[32];
  for (int i = 0; i < NCPU; i++) {
    snprintf(kmem_name, 32, "kmem_%d", i);
    initlock(&kmem[i].lock,kmem_name);
  }
  freerange(end, (void*)PHYSTOP);
  ```
  ]
+ 接下来修改 `kfree()` 函数以正确释放页表，当 CPU 持有锁时，应当禁用该 CPU 上的中断，未持有锁时则可以重新启用中断：
  #blockquote[
  ```c
  ...
  r = (struct run*)pa;

  // 禁用 CPU 上的中断
  push_off();
  int id = cpuid();

  acquire(&kmem[id].lock);
  r->next = kmem[id].freelist;
  kmem[id].freelist = r;
  release(&kmem[id].lock);

  // 重新启用 CPU 上的中断
  pop_off();
  ```
  ]
+ 对于 `kalloc()` 函数，关中断、获取锁后，先在当前 CPU 上查找空闲页，如果在当前核心上申请失败，就尝试使用快慢指针从其他核心上偷一半的页面：
  #blockquote[
  ```c
  void *
  kalloc(void)
  {
    struct run *r;
  
    push_off();
    int id = cpuid();
    acquire(&kmem[id].lock);
  
    r = kmem[id].freelist;
    if(r)
      kmem[id].freelist = r->next;
    else {
      int success = 0;
      for (int i = 0; i < NCPU; i++) {
        if (i == id)
          continue;
  
        acquire(&kmem[i].lock);
        struct run *p = kmem[i].freelist;
        if (p) {
          struct run *fast = p;
          struct run *pre = p;
          // 找到中间一页
          while (fast && fast->next) {
            fast = fast->next->next;
            pre = p;
            p = p->next;
          }
  
          kmem[id].freelist = kmem[i].freelist;
          if (p == kmem[i].freelist)
            // 仅偷走一页
            kmem[i].freelist = 0;
          else {
            kmem[i].freelist = p;
            pre->next = 0;
          }
          success = 1;
        }
        release(&kmem[i].lock);
        if (success) {
          r = kmem[id].freelist;
          kmem[id].freelist = r->next;
          break;
        }
      }
    }
  
    release(&kmem[id].lock);
    pop_off();
  
    if(r)
      memset((char*)r, 5, PGSIZE); // fill with junk
    return (void*)r;
  }
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

使用原代码运行 `kalloctest` 进行测试得到如下结果：

#figure(
  image("..\assets\pre-kalloctest.png", width: 80%),
  caption: [优化前 `kalloctest` 测试结果],
) <fig-pre-kalloctest>

完成优化后，运行 `kalloctest` 进行测试可以得到如下结果，可以看到 `acquire` 循环次数明显减少，说明锁冲突问题大幅减少，性能得到了显著优化：

#figure(
  image("..\assets\alloc-kalloctest.png", width: 80%),
  caption: [`kalloctest` 测试结果],
) <fig-alloc-kalloctest>

运行 `usertests sbrkmuch` 进行测试可以得到如下结果：

#figure(
  image("..\assets\alloc-sbrkmuch.png", width: 30%),
  caption: [`usertests sbrkmuch` 测试结果],
) <fig-alloc-sbrkmuch>

运行 `usertests` 进行测试可以得到如下结果：

#figure(
  image("..\assets\alloc-usertests.png", width: 60%),
  caption: [`usertests` 测试结果],
) <fig-alloc-usertests>

运行 `make grade` 进行评测，得到如下结果：

#figure(
  image("..\assets\alloc-grade.png", width: 40%),
  caption: [`make grade` 部分运行结果],
) <fig-alloc-grade>

=== 实验小结

通过本次实验，我完成一个内存分配器的优化任务，并且理解了操作系统内核是如何处理多核心处理器的锁竞争问题的。通过为每个 CPU 维护一个独立的空闲列表，使得不同 CPU 上的内存分配与释放可以并行进行，减小了锁竞争的次数，从而提高了性能。在尝试从其他 CPU 空闲列表“偷”页面时，为避免过多的锁竞争的同时保证能够获取到足够的内存，我选择了使用快慢指针从其他核心上偷取一半页面。通过这些优化工作，我认识到了优化对于操作系统内核性能的重要性，也学会了如何在并发控制中合理地设计使用锁。

== Buffer cache

=== 实验目的

+ 原本的 xv6 系统使用 `bcache.lock` 锁来保护对于缓存的读写，但这种实现并行性较差。
+ 通过将缓冲区划分为多个桶，并为每个桶设置独立的锁，使得不同进程可以并行访问缓冲区，减少锁竞争和性能瓶颈。
+ 通过这种对缓冲区缓存的优化，减少多个进程之间对缓冲区缓存锁的竞争。

=== 实验步骤

+ 首先查看 `bio.c` 中的代码，了解 xv6 缓冲区缓存的工作原理：
  #blockquote[
  ```c
  struct {
    struct spinlock lock;
    struct buf buf[NBUF];
  
    // Linked list of all buffers, through prev/next.
    // Sorted by how recently the buffer was used.
    // head.next is most recent, head.prev is least.
    struct buf head;
  } bcache;
  ```
  ]
  可以看到，xv6 使用 LRU 链表维护磁盘缓冲区，这就使得每次获取、释放缓冲区时都要对整个链表加锁，降低了并行性。为提高并行性能，可以使用哈希表来代替链表。每次操作缓冲区时只需要对其中一个桶加锁，而桶之间的操作可以并行进行。

+ 修改 `kernel/buf.h` 的 `buf` 结构体，加入字段 `timestamp` 记录该块的最近使用时间：
  #blockquote[
  ```c
  struct buf {
    ...
  
    uint timestamp; // 最近使用时间
    int bucketno;   // 所属的 bucket
  };
  ```
  ]

+ 接下来在 `kernel/bio.c` 中添加用于实现缓冲区哈希表机制的数据结构
  + 定义结构体 `bucket` 与全局哈希表 `hashtable`：
    #blockquote[
    ```c
    struct bucket {
      struct spinlock lock;  // 自旋锁，用于保护对该桶的并发访问
      struct buf head;       // 缓冲区指针，用于构建 LRU 缓冲区的链表
    } hashtable[NBUF];
    ```
    ]
  + 添加需要的宏定义与哈希函数，用于完成从块号到哈希索引的转换：
    #blockquote[
    ```c
    #define NBUCKET 13

    int
    hash(uint dev, uint blockno)
    {
      return blockno % NBUCKET;
    }
    ```
    ]

+ 修改 `kernel/bio.c` 的 `binit()` 函数，完成对哈希表的初始化：
  #blockquote[
  ```c
  void
  binit(void)
  {
    struct buf *b;
    struct bucket *bucket;

    initlock(&bcache.lock, "bcache");

    char name[32];
    for (bucket = hashtable; bucket < hashtable+NBUCKET; bucket++) {
      snprintf(name, 32, "bcache_bucket_%d", bucket - hashtable);
      initlock(&bucket->lock, name);
    }

    for(b = bcache.buf; b < bcache.buf+NBUF; b++) {
      initsleeplock(&b->lock, "buffer");

      b->timestamp = 0;
      b->refcnt = 0;
      b->bucketno = 0;

      b->next = hashtable[0].head.next;
      hashtable[0].head.next = b;
    }
  }
  ```
  ]
+ 修改 `bget()` 函数：
  + 先通过索引获取锁：
    #blockquote[
    ```c
    int index = hash(blockno);
    struct bucket* bucket = &hashtable[index];
    acquire(&bucket->lock);
    ```]
  + 在对应桶中查找是否有空闲块，如果当前桶中没有则在其他桶中查找，如果找到则直接返回：
    #blockquote[
    ```c
    // Is the block already cached?
    for(b = bucket->head.next; b != 0; b = b->next){
      if(b->dev == dev && b->blockno == blockno){
        // 当前块已缓存则直接返回
        b->refcnt++;
        release(&bucket->lock);
        acquiresleep(&b->lock);
        return b;
      }
    }
    release(&bucket->lock);

    // 在其他桶中查看当前当前块是否已缓存
    acquire(&bcache.lock);
    for (b = bucket->head.next; b != 0; b = b->next) {
      if (b->dev == dev && b->blockno == blockno) {
        // 已缓存则直接返回
        acquire(&bucket->lock);
        b->refcnt++;
        release(&bucket->lock);
        release(&bcache.lock);

        acquiresleep(&b->lock);
        return b;
      }
    }
    ```]
  + 没有找到就需要在全局数组中查找最久未使用过的一个空闲块：
    #blockquote[
    ```c
    // Not cached.
    // Recycle the least recently used (LRU) unused buffer.
    struct buf *min_b = 0;
    uint min_time = ~0;
    uint cur_bucket = -1;

    for (int i = 0; i < NBUCKET; i++) {
      acquire(&hashtable[i].lock);

      int found = 0;
      for (b = hashtable[i].head; b->next != 0; b = b->next) {
        if (b->next->refcnt == 0 && (min_b == 0 || b->next->timestamp < min_time)) {
          // 首次找到空闲缓冲区或找到更早使用过的缓冲区
          min_b = b;
          min_time = b->next->timestamp;
          found = 1;
        }
      }

      if (found) {
        if (cur_bucket != -1)
          release(&hashtable[cur_bucket].lock);
        cur_bucket = i;
      }
      else {
        release(&hashtable[i].lock);
      }
    }
    ```]
  + 最后如果找到空闲块则释放桶与哈希表的自旋锁，获取该缓冲区的休眠锁，并返回该缓冲区，没找到则发出 `panic`：
    #blockquote[
    ```c
    if (min_b) {
      struct buf* p = min_b->next;

      if (cur_bucket != index) {
        // 删除 min_b 节点
        min_b->next = p->next;
        release(&hashtable[cur_bucket].lock);

        // 将 min_b 节点加入到当前桶中
        acquire(&hashtable[index].lock);
        p->next = hashtable[index].head.next;
        hashtable[index].head.next = p;
      }

      p->dev = dev;
      p->blockno = blockno;
      p->refcnt = 1;
      p->valid = 0;
      p->bucketno = index;

      release(&hashtable[index].lock);
      release(&bcache.lock);

      acquiresleep(&p->lock);
      return p;
    }

    panic("bget: no buffers");
    ```
    ]
+ 修改 `kernel/bio.c` 的 `brelse` 函数，释放之前在 `bget()` 中调用的睡眠锁，减少 `refcnt` 即可。如果一个块引用数为 0，则需要将 `timestamp` 改为最近使用时间：
  #blockquote[
  ```c
  void
  brelse(struct buf *b)
  {
    if(!holdingsleep(&b->lock))
      panic("brelse");

    releasesleep(&b->lock);

    uint index = hash(b->blockno);
    acquire(&hashtable[index].lock);
    b->refcnt--;
    if (b->refcnt == 0) {
      // no one is waiting for it.
      b->timestamp = ticks;
    }

    release(&hashtable[index].lock);
  }
  ```
  ]

+ 最后修改 `bpin()` 与 `bunpin()` 函数，使之可以正确增减引用数：
  #blockquote[
  ```c
  void
  bpin(struct buf *b) {
    uint index = hash(b->blockno);
    acquire(&hashtable[index].lock);
    b->refcnt++;
    release(&hashtable[index].lock);
  }

  void
  bunpin(struct buf *b) {
    uint index = hash(b->blockno);
    acquire(&hashtable[index].lock);
    b->refcnt--;
    release(&hashtable[index].lock);
  }
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行 `bcachetest` 进行测试可以得到如下结果：

#figure(
  image("..\assets\bcachetest.png", width: 60%),
  caption: [`bcachetest` 测试运行结果],
) <fig-bcachetest>

最初运行 `usertests` 进行测试会得到如下结果：

#figure(
  image("..\assets\buffer-failure.png", width: 80%),
  caption: [未通过 `usertests` 测试],
) <fig-buffer-failure>

并没有通过测试。查阅资料后，得知这与 `kernel/param.h` 文件中的文件系统的大小相关，当初始数值设置太小时，就没有足够的内存支持所需的操作，因此需要做出如下修改，以提供更大的文件系统容量来执行写入等操作。

#blockquote[
```c
#ifdef LAB_LOCK
#define FSSIZE       10000  // size of file system in blocks
#else
#define FSSIZE       1000   // size of file system in blocks
#endif
```]

做出修改后重新运行测试，可以得到如下结果：

#figure(
  image("..\assets\buffer-usertests.png", width: 40%),
  caption: [`usertests` 测试结果],
) <fig-buffer-usertests>

运行 `make grade` 进行测试可以得到如下结果：

#figure(
  image("..\assets\buffer-grade.png", width: 60%),
  caption: [`make grade` 评测结果],
) <fig-buffer-grade>

=== 实验小结

通过本次实验，我通过使用哈希表来存储缓存的块信息并为每个哈希表分配一个独立的锁，成功地降低了缓冲区缓存中的锁竞争。在这种思路下，结合 LRU 算法，可以让不同块的查找和释放操作能够并行执行，并尽可能地减少锁的获取次数，从而减少锁竞争问题。

实验过程中，我遇到了一些死锁方面的挑战。在某些情况下，确实需要同时持有两个锁，比如在替换块时，需要持有全局的 `bcache.lock` 以及特定哈希桶的锁。为了避免死锁的发生，我仔细设计了锁的获取顺序，并确保在任何情况下都不会发生死锁。

这次实验加深了我对操作系统内存管理的理解，让我对哈希表的设计与使用有更加深入的认识，也让我了解了更多如何有效地管理和减少锁竞争的知识。
