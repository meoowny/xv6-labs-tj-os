#import "@preview/ilm:1.2.1": *

= Lab: Multithreading <thread>

== 实验概述

在本 lab 中，将会实现以下三个部分：
- 用户级线程的创建和切换
- 使用多线程加速程序
- barrier

开始编码之前，阅读 #link("https://pdos.csail.mit.edu/6.828/2021/xv6/book-riscv-rev2.pdf")[xv6 book] 的第 7 章。

开始实验前需要使用 ```bash git checkout thread``` 先切换到 `thread` 分支，将代码复制到 thread 目录下。

== Uthread: 在线程间切换

=== 实验目的

+ 设计并实现一个用户级线程系统的上下文切换机制。
+ 补全创建用户级线程与切换上下文的代码。

=== 实验步骤

+ 首先设计线程的数据结构。参考进程上下文的定义，各线程都应该有自己的上下文，包括唯一的线程 ID、栈、栈指针、程序计数器、通用目的寄存器和条件码。所有运行在一个进程里的线程共享该线程的整个虚拟地址空间。
+ 在 `user/uthread.c` 中创建线程上下文 `uthread_context` 的定义，并修改 `thread` 结构体的定义，添加线程上下文的字段：
  #blockquote[
  ```c
  struct uthread_context {
    uint64 ra;
    uint64 sp;
  
    uint64 s0;
    uint64 s1;
    uint64 s2;
    uint64 s3;
    uint64 s4;
    uint64 s5;
    uint64 s6;
    uint64 s7;
    uint64 s8;
    uint64 s9;
    uint64 s10;
    uint64 s11;
  };
  
  struct thread {
    char       stack[STACK_SIZE]; /* the thread's stack */
    int        state;             /* FREE, RUNNING, RUNNABLE */
    struct uthread_context context;
  };
  ```
  ]

+ 修改 `user/uthread.c` 中的 `thread_create()` 函数，用于创建线程。该函数会找到一个空闲线程并为其分配，将状态设置为运行，然后保存现场：设置 `ra` 寄存器为 `func` 指针以调用传入的函数，并设置 `sp` 寄存器为线程栈底部以确保栈指针正确指向线程的栈。
  #blockquote[
  ```c
  t->context.ra = (uint64)func;
  t->context.sp = (uint64)(t->stack + STACK_SIZE);
  ```
  ]
+ 在 `user/uthread_switch.S` 中用汇编实现用于切换线程的 `thread_switch` 函数，函数需要保存调用者保存的寄存器，切换到下一个线程，然后恢复下一个线程的寄存器状态。参考 `kernel/switch.S` 实现如下：
  #blockquote[
  ```asm
  	.globl thread_switch
  thread_switch:
  	/* YOUR CODE HERE */
          sd ra, 0(a0)
          sd sp, 8(a0)
          sd s0, 16(a0)
          sd s1, 24(a0)
          sd s2, 32(a0)
          sd s3, 40(a0)
          sd s4, 48(a0)
          sd s5, 56(a0)
          sd s6, 64(a0)
          sd s7, 72(a0)
          sd s8, 80(a0)
          sd s9, 88(a0)
          sd s10, 96(a0)
          sd s11, 104(a0)
  
          ld ra, 0(a1)
          ld sp, 8(a1)
          ld s0, 16(a1)
          ld s1, 24(a1)
          ld s2, 32(a1)
          ld s3, 40(a1)
          ld s4, 48(a1)
          ld s5, 56(a1)
          ld s6, 64(a1)
          ld s7, 72(a1)
          ld s8, 80(a1)
          ld s9, 88(a1)
          ld s10, 96(a1)
          ld s11, 104(a1)
  
  	ret    /* return to ra */
  ```
  ]
+ 补全 `user/uthread.c` 中的 `thread_schedule()` 函数，调用 `thread_switch` 实现线程的切换。需要传递当前线程的上下文指针和下一个线程的上下文指针给 `thread_switch`，以便它知道要切换到哪个线程：
  #blockquote[
  ```c
  thread_switch((uint64)&t->context, (uint64)&next_thread->context);
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行 `uthread` 可以得到如下结果：

#figure(
  image("..\assets\uthread-test.png", width: 30%),
  caption: [`uthread` 运行结果],
) <fig-uthread-test>

运行 `./grade-lab-thread uthread` 进行评测，得到如下结果：

#figure(
  image("..\assets\uthread-grade.png", width: 80%),
  caption: [`uthread` 评测结果],
) <fig-uthread-grade>

=== 实验小结

通过本次实验，我学习并理解了用户级线程的设计原理与实现机制，在理解寄存器功能的基础上实现了一个用户级线程的上下文切换机制。要实现线程的切换，我遇到了两个难题，分别是如何为每个线程分配所需的堆栈空间，以及如何实现调度器。

创建线程时，首先需要为每个线程分配独立的堆栈空间。通过查阅相关文档与代码，我对各寄存器的功能特性有了更清晰的理解。例如 RISC-V 中 `ra` 寄存器用于存储函数调用后的返回地址，`sp` 寄存器用于存储当前栈的栈顶地址，创建线程时就需要对其进行相应的分配。

实现调度器时，则需要确保可以正确切换到下一个可运行的线程。这需要在 `thread_schedule` 中选择一个可运行的线程并使用 `thread_switch` 切换到该线程。

通过实现用户级线程的创建与切换，我对用户级线程的概念和线程切换的底层实现机制有了更深入的理解，为今后的学习提供了极大帮助。

== 使用线程

=== 实验目的

+ 本实验旨在通过使用线程和锁实现并行编程。
+ 学习使用线程库创建和管理线程。
+ 在多线程下通过加锁实现一个线程安全的哈希表。

=== 实验步骤

+ 查阅 `pthread` 库的相关文档，了解基本概念、函数与用法。文档参考 #link("https://pubs.opengroup.org/onlinepubs/007908799/xsh/pthread_mutex_lock.html")[此处]、#link("https://pubs.opengroup.org/onlinepubs/007908799/xsh/pthread_mutex_init.html")[此处] 和 #link("https://pubs.opengroup.org/onlinepubs/007908799/xsh/pthread_create.html")[此处]。
  主要使用以下四个函数：
  #blockquote[
  ```c
  pthread_mutex_t lock;            // declare a lock
  pthread_mutex_init(&lock, NULL); // initialize the lock
  pthread_mutex_lock(&lock);       // acquire lock
  pthread_mutex_unlock(&lock);     // release lock
  ```
  ]
+ 使用 `make ph` 构建实验程序，然后使用 `./ph 1` 进行单线程下的性能测试，结果如下：
  #figure(
    image("..\assets\ph1.png", width: 80%),
    caption: [`./ph 1` 测评结果],
  ) <fig-ph1>
  使用 `./ph 2` 进行多线程下的性能测试，结果如下：
  #figure(
    image("..\assets\ph2.png", width: 80%),
    caption: [`./ph 2` 测评结果],
  ) <fig-ph2>
+ 可以看到，多线程情况下，出现大量键值对丢失的问题，部分键值对并没有被正确添加到哈希表中，而单线程情况下，没有出现该问题。

+ 分析代码可以知道，这是由于访问哈希表时发生了冲突，可以使用锁来解决。
  + 首先在代码中为各哈希表定义一个锁，使用 `pthread_mutex_init`、`pthread_mutex_lock` 和 `pthread_mutex_unlock` 函数来初始化、获取和释放锁：
    #blockquote[
    ```c
    pthread_mutex_t lock[NBUCKET]; // 为每个散列表设置一个锁
    ```
    ]
  + 调用 `main()` 函数前，先使用 `pthread_mutex_init` 初始化锁：
    #blockquote[
    ```c
    for (int i = 0; i < NBUCKET; ++i)
      pthread_mutex_init(&lock[i], NULL);
    ```
    ]
  + 修改 `put()` 函数，确保多线程调用 `insert()` 函数时不发生冲突：
    #blockquote[
    ```c
    if(e){
      // update the existing key.
      e->value = value;
    } else {
      // the new is new.
      pthread_mutex_lock(&lock[i]);
      insert(key, value, &table[i], table[i]);
      pthread_mutex_unlock(&lock[i]);
    }
    ```
    ]
  + 最后在使用完 `put` 后销毁锁，避免占用资源：
    #blockquote[
    ```c
    for (int i = 0; i < NBUCKET; ++i)
      pthread_mutex_destroy(&lock[i]);
    ```
    ]
+ 重新运行 `make ph` 并使用 `./ph 2` 进行多线程情况下的测试。
+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

改进后运行 `./ph 2` 可以看到，没有键值对丢失的问题发生：

#figure(
  image("..\assets\ph2-after.png", width: 80%),
  caption: [改进后 `./ph 2` 测试结果],
) <fig-ph2-after>

运行 `./grade-lab-thread ph_safe` 进行评测，得到如下结果：

#figure(
  image("..\assets\ph_safe_test.png", width: 80%),
  caption: [`ph_safe` 测评结果],
) <fig-ph_safe_test>

运行 `./grade-lab-thread ph_fast` 进行评测，得到如下结果：

#figure(
  image("..\assets\ph_fast_test.png", width: 80%),
  caption: [`ph_fast` 测评结果],
) <fig-ph_fast_test>

=== 实验小结

在多线程测试时，`./ph 2` 出现了大量的键值丢失的问题，这是由于多线程环境下没有加锁保护，多个线程可能同时访问哈希表，产生竞争。此时就会导致部分 `put()` 操作被覆盖，从而导致部分键值对没有成功插入。

在本次实验中，我通过实践掌握了使用 `pthread` 线程库来创建和管理线程的方法，以及如何运用锁来解决多线程环境下的竞争问题。实验过程中，我深入理解了并行编程中的常见问题，如竞争条件问题，并学会如何通过正确地获取和释放锁来避免这些问题。通过比较单线程与多线程程序的性能差异，我认识到多线程编程在提升程序效率方面的巨大潜力。同时，我也意识到了随之而来的控制问题，如过度锁使用所带来的性能下降。

实验过程中，我使用线程和锁实现了一个并行哈希表。我学会了如何通过减小锁的粒度来减少锁竞争，从而提高程序的整体性能。为每个哈希表添加独立的锁成为了一个有效的策略，这不仅保证了线程的安全性，也显著提高了多线程执行的效率。通过这些实践，我深刻体会到了多线程编程的挑战与重要性，获得了多线程开发的宝贵经验。

== 屏障（Barrier）

=== 实验目的

+ 实现一个线程屏障，使得每个线程都要在屏障处等待，直到所有线程到达屏障后才能继续运行。
+ 加深对多线程编程中同步互斥机制的理解。

=== 实验步骤

+ 查看并理解 `notxv6/barrier.c` 的实现与测试方法，它使用 `barrier_init()` 函数初始化线程屏障的状态，然后创建多个线程，各线程执行循环并在循环中调用 `barrier()` 函数，然后进入阻塞状态，当所有线程都调用了 `barrier()` 函数时才会继续执行。实验将会用到如下两个 `pthread` 函数调用：
  #blockquote[
  ```c
  pthread_cond_wait(&cond, &mutex);  // 根据条件休眠，释放互斥锁，唤醒后获取互斥锁
  pthread_cond_broadcast(&cond);     // 唤醒 cond 上所有处于睡眠状态的线程
  ```
  ]
+ 实现 `barrier()` 函数，使其在所有线程调用 `barrier()` 之前保持阻塞状态：\ 
  需要使用 `pthread_cond_wait()` 来让线程进入阻塞状态等待条件满足，使用 `pthread_cond_broadcast()` 来唤醒等待中的线程。
    #blockquote[
    ```c
    pthread_mutex_lock(&bstate.barrier_mutex);

    bstate.nthread++;  // 当前到达屏障的线程数量加一
    if (bstate.nthread < nthread) {
      // 当前线程进入阻塞状态等待
      pthread_cond_wait(&bstate.barrier_cond, &bstate.barrier_mutex);
    }
    else {
      bstate.nthread = 0; // 重置到达屏障的线程数
      bstate.round++;     // 轮次加一
      pthread_cond_broadcast(&bstate.barrier_cond); // 唤醒所有在条件变量 barrier_cond 上等待的线程
    }

    pthread_mutex_unlock(&bstate.barrier_mutex);
    ```
    ]

+ 使用 `make barrier` 构建实验程序，然后使用 `./barrier 1` 进行测试。
+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行 `./barrier 1` 进行单线程测试可以得到如下结果：

#figure(
  image("..\assets\barrier1.png", width: 80%),
  caption: [`./barrier 1` 测试结果],
) <fig-barrier1>

运行 `./barrier 2` 和 `./barrier 4` 进行多线程测试可以得到如下结果：

#figure(
  image("..\assets\barrier-2-3.png", width: 80%),
  caption: [`./barrier 2` 与 `./barrier 4` 测试结果],
) <fig-barrier-2-3>

运行 `./grade-lab-thread barrier` 进行评测，得到如下结果：

#figure(
  image("..\assets\barrier-grade.png", width: 80%),
  caption: [`barrier` 评测结果],
) <fig-barrier-grade>

=== 实验小结

通过本次实验，我深入探索了多线程编程中的同步机制，特别是条件变量和互斥锁的应用。我学会了如何设计和实现屏障同步机制，以确保多个线程能在特定处同步等待和唤醒，从而实现了程序的并发控制。实验中，我使用条件变量和互斥锁解决了多线程并发访问屏障的问题，确保了所有线程都能正确地等待在屏障处，直到所有线程都到达屏障后再一起继续执行。通过这些实践，我不仅提高了对多线程编程的理解，还熟悉了实际使用条件变量和互斥锁解决并发问题的过程，对多线程编程有了更深入的认知。

