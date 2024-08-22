#import "@preview/ilm:1.2.1": *

= Lab: Traps <traps>

== 实验概述

本实验将会探索系统调用是如何使用陷阱（trap）实现的。首先会使用堆栈进行热身练习，接下来会实现一个用户级陷阱处理（user-level trap handling）的示例。

开始编码之前，阅读 #link("https://pdos.csail.mit.edu/6.828/2021/xv6/book-riscv-rev2.pdf")[xv6 book] 的第 4 章以及相关源文件：

+ `kernel/trampoline.S` ：从用户空间切换到内核空间并返回的汇编代码。
+ `kernel/trap.c`：处理所有中断的代码。

开始实验前需要使用 ```bash git checkout traps``` 先切换到 `traps` 分支，将代码复制到 traps 目录下。

== RISC-V 汇编

=== 实验目的

+ 了解 RISC-V 汇编知识。
+ 学习如何在 RISC-V 汇编中进行函数参数的传递、函数调用和内存访问。

=== 实验步骤

+ 使用 `make fs.img` 编译 `user/call.c`，阅读生成的 `user/call.asm` 文件，查看函数 `g()`、`f()` 和 `main()` 的汇编代码。

+ 回答以下问题：
  / Q1: 哪些寄存器保存函数的参数？例如，在 `main` 对 `printf` 的调用中，哪个寄存器保存 13？
  / A1: 调用函数时使用 `a1`、`a2`、`a3` 等通用寄存器保存函数的参数。
        #figure(
          image("..\assets\call-main.png", width: 80%),
          caption: [`call.asm` 中的 `main()` 函数],
        ) <fig-call-main>
        通过查看 `call.asm` 文件的 `main()` 函数可知，在 `main` 调用 `printf` 时，13 被保存在寄存器 `a2` 中。\ \ 

  / Q2: `main` 的汇编代码中在哪里调用了函数 `f`？对 `g` 的调用在哪里（提示：编译器可能会将函数内联）
  / A2: 通过查看函数 `f()` 和 `g()` 可知：函数 `f()` 调用了函数 `g()`，函数 `g()` 将传入的参数加 3 后返回。考虑到编译器会进行内联优化，这就意味着一些编译时可以计算的数据会在编译时得出结果，而不进行函数调用。\ \ 
        查看代码可以发现，函数 `f()` 直接将传入的值加 3 返回；`main()` 函数在 `printf()` 中调用了 `f()` 函数，但对应的汇编代码直接将 `f(8)+1` 替换为 12。这说明编译器对这个函数调用进行了优化。\ \ 
        所以对于 `main` 函数而言，它并没有直接调用 `f()` 函数和 `g()` 函数，`f()` 函数也没有直接调用 `g()` 函数，编译器对其进行了优化。\ \ 

  / Q3: `printf`函数位于哪个地址？
  / A3: 通过搜索可以得到 `printf` 函数的地址为 `0x628`。
        #figure(
          image("..\assets\printf-addr.png", width: 80%),
          caption: [`printf` 函数地址],
        ) <fig-printf-addr>\ \ 

  / Q4: 在 `main` 中 `jalr` 到 `printf` 后寄存器 `ra` 中值是什么？
  / A4: 查看相关代码：
        #figure(
          image("..\assets\main-jalr.png", width: 80%),
          caption: [`main` 中的 `jalr` 指令],
        ) <fig-main-jalr>
        30: 使用 `auipc ra,0x0` 将当前程序计数器 `pc` 的值存入 `ra` 中；\ \ 
        34: 使用 `jalr 1536(ra)` 跳转到偏移地址 `printf` 处，也就是 `0x628` 的位置。\ \ 
        执行完这句指令后，寄存器 `ra` 的值会被设置为 `pc+4`，即 `0x38`。\ \ 
        因此 `jalr` 指令执行完毕之后，`ra` 的值为 `0x38`。\ \ 
  / Q5: 运行以下代码：
        #blockquote[
        ```c
        unsigned int i = 0x00646c72;
        printf("H%x Wo%s", 57616, &i);
        ```
        ]
        指出程序的输出是什么样的。\ \ 
        输出取决这样一个事实，即 RISC-V 使用小端存储。如果 RISC-V 是大端存储，为了得到相同的输出，你会把 `i` 设置成什么？是否需要将 `57616` 更改为其他值？\ \ 
  / A5: 运行结果：打印出了 `HE110 World`。\ \ 
        这是因为 `57616` 转换为十六进制后为 `E110`，因此格式化后打印出了它的十六进制值。而在小端处理器中，数据 `0x00646c72` 的高字节存储在内存的高位，从内存低位（即低字节）开始读取时，对应的 ASCII 字符就是 `rld`。\ \ 
        如果是在大端处理器中，数据高字节存储在内存低位中，所以如果需要和小端序输出相同内容的话，就需要将 `i` 的值改为 `0x726c64` 才能保证内存从低位读取时输出为 `rld`。\ \ 
        而 `57616` 的二进制值无关存储方式，因此不需要改变。\ \ 
        总的来说，需要将 `i` 的值改为 `0x726c64`，`57616` 不需要改变。\ \ 

  / Q6: 在下面的代码中，`y=` 后面将打印什么（注：答案不是一个特定的值）？为什么会发生这种情况？
        #blockquote[
        ```c
        printf("x=%d y=%d", 3);
        ```
        ]
  / A6: 由于函数参数是通过 `a1`, `a2` 等寄存器来传递的，因此如果 `printf` 少传一个参数，它就仍会从指定寄存器中读取想要的参数的值。但由于这里没有给出该参数，因此函数从寄存器 `a2` 中的读取到的值无法确定。

=== 实验小结

在该实验中，我深入了解了 RISC-V 汇编中是如何进行函数参数传递、函数调用和内存访问的。通过查看生成的 `user/call.asm` 文件，我更好地理解了 C 代码是如何编译为汇编的，也了解了 `jalr` 指令作用、xv6 存储方式。这为后续学习和理解操作系统与底层硬件提供极大的帮助。

== Backtrace

=== 实验目的

+ 在 `kernel/printf.c` 中实现 `backtrace()` 函数，用于在操作系统内核发生错误时，输出调用堆栈上的函数调用列表。这有助于调试和定位错误发生的位置。

=== 实验步骤

+ 在 `kernel/defs.h` 中添加 `backtrace()` 的原型，并在 `sys_sleep` 中插入对此函数的调用。
  #blockquote[
  kernel/def.h：
  ```c
  void backtrace(void);
  ```
  kernel/sysproc.c：
  ```c
  uint64
  sys_sleep(void)
  {
    int n;
    uint ticks0;
    backtrace();
    ...
  ```
  ]
+ 在 `kernel/riscv.h` 中添加以下代码，并在 `backtrace()` 中调用该函数来读取当前的帧指针。这个函数使用了内联汇编读取 `s0` 寄存器，GCC 会将当前执行的函数的帧指针存放到该寄存器中：
  #blockquote[
  kernel/riscv.h
  ```c
  static inline uint64
  r_fp()
  {
    uint64 x;
    asm volatile("mv %0, s0" : "=r" (x) );
    return x;
  }
  ```
  ]

+ 在 `kernel/printf.c` 中实现 `backtrace` 函数，这个函数通过遍历调用堆栈中的帧指针来输出保存的每个栈帧中的返回地址：
  + 首先，调用 `r_fp` 函数来读取当前帧指针的值，将这个值存储在 `fp` 变量中：
    #blockquote[
    ```c
    uint64 fp = r_fp();
    ```
    ]
  + 接着，为了确保在栈的有效地址范围内遍历，我们需要利用 `PGROUNDDOWN(fp)` 来设置循环终止条件：
    #blockquote[
    ```c
    while (fp != PGROUNDDOWN(fp)) {
      printf("%p\n", *((uint64 *)(fp - 8)));
      fp = *((uint64 *)(fp - 16));
    }
    ```
    ]
    循环中先输出了当前栈帧中保存的返回地址，它保存在调用者的栈帧中，相对于帧指针的位移量为 -8，因此使用 `*((uint64 *)(fp - 8))` 读取该值并打印出来。\ \ 
    为遍历下一个栈帧，还需要更新帧指针 `fp`，上一个帧指针的位置在位移量 -16 的位置，因此使用 `*((uint64 *)(fp - 16))` 读取该值并赋值给 `fp`。

+ 在 xv6 shell 中运行 `bttest` 程序进行测试。
+ 最后，可以将 `backtrace` 函数添加到 `panic` 函数中，这样就可以在内核发生 panic 时看到内核的回溯信息。

=== 评测结果

执行 `make qemu` 后，运行 `bttest` 测评程序调用 `sys_sleep` 可以得到如下结果：

#figure(
  image("..\assets\backtrace-test.png", width: 45%),
  caption: [`backtrace` 测评结果],
) <fig-backtrace-test>

使用 `addr2line -e kernel/kernel` 将上述地址转换为函数名和文件行号：

#figure(
  image("..\assets\addr2line.png", width: 80%),
  caption: [将地址转换为函数名和文件名],
) <fig-addr2line>

运行 `./grade-lab-traps backtrace` 进行评测，得到如下结果：

#figure(
  image("..\assets\backtrace-grade.png", width: 80%),
  caption: [`backtrace` 评测结果],
) <fig-backtrace-grade>

=== 实验小结

在本次实验中，我成功实现了 `backtrace()` 函数，可以获取函数调用链上的每个栈帧的返回地址，并输出这些返回地址的列表。在实验过程中，我深入了解了程序执行过程中函数调用和返回的机制，认识到帧指针在调用堆栈中的重要作用。

为了可以获取当前帧指针并根据帧指针访问返回地址，还需要充分利用 RISC-V 的寄存器和内联汇编，这需要查阅相关资料与 RISC-V 手册。最后使用 `addr2line` 工具，就可以获取返回地址对应的源代码位置，有助于调试内核代码，可以更加方便地定位并解决问题，为后续实验的开展提供了便利，也加深了我对于调用堆栈与帧指针的理解。

== Alarm <alarm>

=== 实验目的

+ 实现 `sigalarm()` 系统调用，以周期性地为进程设置定时提醒。
+ 这个功能类似于用户级的中断/异常处理程序，能够让进程在消耗一定的 CPU 时间后执行指定的函数，然后恢复执行。
+ 通过实现这个功能，我们可以为计算密集型进程限制 CPU 时间，或者为需要周期性执行某些操作的进程提供支持。

=== 实验步骤

+ `sigalarm(interval, handler)` 函数接收两个参数：`interval` 为时间间隔，每隔 `interval` 个 `tick` 发出警告，调用函数指针 `handler` 指向的函数。如果一个程序调用了`sigalarm(0, 0)`，系统应当停止生成周期性的报警调用。

+ 在 `Makefile` 中添加`$U/_alarmtest\`，以便将 `alarmtest.c` 作为 xv6 用户程序编译。
+ 在 `user/user.h` 中添加用户调用的接口声明：
  #blockquote[
  ```c
  int sigalarm(int ticks, void (*handler)());
  int sigreturn(void);
  ```
  ]
+ 更新 `user/usys.pl` 以生成 `user/usys.S`，在 `usys.pl` 中添加相应的用户态库函数入口：
  #blockquote[
  ```perl
  entry("sigalarm");
  entry("sigreturn");
  ```
  ]
+ 在 `syscall.h` 中声明 `sigalarm` 和 `sigreturn` 的用户态库函数：
  #blockquote[
  ```c
  #define SYS_sigalarm 22
  #define SYS_sigreturn 23
  ```
  ]
+ 在 `syscall.c` 中添加对应的系统调用处理函数：
  #blockquote[
  ```c
  extern uint64 sys_sigalarm(void);
  extern uint64 sys_sigreturn(void);

  static uint64 (*syscalls[])(void) = {
    ...
    [SYS_sigalarm] sys_sigalarm,
    [SYS_sigreturn] sys_sigreturn,
  };
  ```
  ]
+ 目前，`sys_sigreturn` 应当只返回零，因此还需要在 `sys_sigalarm` 中，将警报间隔和处理函数的指针存储在 `proc` 结构体的新字段中（位于 `kernel/proc.h`）：
  #blockquote[
  ```c
  struct proc {
    ...

    int interval;                      // 间隔
    int ticks;                         // Tick 数
    uint64 handler;                    // 处理函数
    struct trapframe trapframe_saved; // 用来保存和还原寄存器状态
    int have_return;                   // bool 值，表示警报处理程序是否返回。
  };
  ```
  ]
+ 在 `kernel/proc.c` 的 `allocproc()` 中进行初始化，以追踪自上次调用警报处理函数以来经过了多少个时钟中断：
  #blockquote[
  ```c
  static struct proc*
  allocproc(void)
  {
    ...

    p->interval = 0;
    p->ticks = 0;
    p->handler = 0;

    return p;
  }
  ```
  ]
+ 在 `kernel/sysproc.c` 中添加 `sys_sigalarm()` 系统调用，完成参数传递：
  #blockquote[
  ```c
  uint64
  sys_sigalarm(void)
  {
    int interval;
    uint64 handler;
    struct proc *p = myproc();
  
    argint(0, &interval);
    argaddr(1, &handler);
  
    p->interval = interval;
    p->handler = handler;
    p->have_return = 1; // true
    return 0;
  }
  ```
  ]
+ 每次时钟中断发生时，硬件时钟会产生一个中断，这将在 `usertrap()` 函数中进行处理（位于 `kernel/trap.c`）。因此接下来需要修改 `usertrap` 函数，使得硬件时钟每滴答一次都会强制中断一次。
  #blockquote[
  ```c
  void
  usertrap(void)
  {
    ...

    if(which_dev == 2) {
      struct proc *proc = myproc();
      if (proc->interval && proc->have_return) {
        if (++proc->ticks == 2) {
          proc->trapframe_saved = *p->trapframe;

          proc->trapframe->epc = proc->handler;
          proc->ticks = 0;
          proc->have_return = 0;
        }
      }
      yield();
    }

    usertrapret();
  }
  ```
  ]
+ 在 `kernel/sysproc.c` 中添加 `sys_sigreturn()` 系统调用，用于恢复寄存器状态并释放空间，模拟中断返回过程，以避免影响到内核的其他部分：
  #blockquote[
  ```c
  uint64
  sys_sigreturn(void)
  {
    // 获取当前进程的结构体指针
    struct proc *p = myproc();
    // 将保存在 p->trapframe_saved 中的中断帧信息恢复回 p->trapframe
    *p->trapframe = p->trapframe_saved;
    // 置 p->have_return 为 1，表示信号处理函数已返回
    p->have_return = 1;
    return p->trapframe->a0;
  }
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行 `alarmtest` 可以得到如下结果：

#figure(
  image("..\assets\alarm-test.png", width: 70%),
  caption: [`alarm` 测试结果],
) <fig-alarm-test>

运行 `usertests` 可以得到如下结果：

#figure(
  image("..\assets\alarm-test2.png", width: 40%),
  caption: [`alarm` 测试结果],
) <fig-alarm-test2>

运行 `./grade-lab-traps` 进行评测，得到如下结果：

#figure(
  image("..\assets\alarm-grade.png", width: 80%),
  caption: [`alarm` 评测结果],
) <fig-alarm-grade>

=== 实验小结

在本次实验中，我遇到了两个主要问题：一是对系统调用机制的理解不足，导致在设置系统调用时遗漏了必要的用户层面声明和入口点，这让我对用户态与内核态之间的转换有了更深刻的认识；二是处理函数调用后未能正确恢复进程状态，最初忽略了中断帧信息的保存和恢复，通过实验我学会了如何利用 `proc->saved_trapframe` 中的信息来恢复进程的执行状态。

通过实现 `sigalarm()` 和 `sys_sigreturn()` 系统调用，为 xv6 实现周期性的 CPU 时间警报功能，我不仅加深了对定时中断处理机制的理解，还巩固了用户态与内核态转换的知识，并且意识到了确保系统稳定性的重要性，特别是在修改内核操作时，必须确保不会影响系统的稳定性和正常运行，确保中断处理程序能够及时返回，避免影响其他中断和系统调度。

