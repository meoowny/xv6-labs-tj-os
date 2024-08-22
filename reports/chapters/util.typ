#import "@preview/ilm:1.2.1": *

= Lab: Xv6 and Unix utilities <util>

== 实验概述

本实验我们将熟悉 xv6 操作系统及其系统调用。

== 启动 xv6

=== 实验目的

+ 配置实验环境并编译运行 xv6 内核。
+ 学习使用 QEMU 模拟内核运行。

=== 实验步骤

+ 使用以下指令获取实验室的 xv6 源代码并检出 util 分支：

  #blockquote[
  ```bash
  $ git clone git://g.csail.mit.edu/xv6-labs-2021
  Cloning into 'xv6-labs-2021'...
  ...
  $ cd xv6-labs-2021
  $ git checkout util
  ```
  ]

xv6-labs-2021 仓库与本书的仓库略有不同 XV6-RISCV；它主要添加一些文件。可以在 git 日志中查看这个修改：```bash git log ```。为方便查看完成后的代码，这里将各分支代码单独复制到各 lab 的目录下。

Git 允许跟踪我们对代码所做的修改。例如，如果完成了其中一个练习，想检查一下进度，我们可以通过运行以下程序提交修改：

  #blockquote[
  ```bash
  $ git commit -am 'my solution for util lab exercise 1'
  Created commit 60d2135: my solution for util lab exercise 1
  1 files changed, 1 insertions(+), 0 deletions(-)
  ```
  ]

可以使用 ```bash git diff``` 命令来跟踪改动。运行 ```bash git diff``` 将显示自上次提交后代码的修改，而 ```bash git diff origin/util``` 将显示相对于初始 xv6-labs-2021 代码的修改。这里，`origin/xv6-labs-2021` 是该类初始代码的 git 分支名称。

+ 构建并运行 xv6：

  #blockquote[
  ```bash
  mony@LAPTOP-1G006S5P:~/xv6-labs-2021$ make qemu
  ...
  xv6 kernel is booting

  hart 2 starting
  hart 1 starting
  init: starting sh
  $
  ```
  ]

此时在 prompt 下输入 `ls` 就可以看到如下内容：

  #blockquote[
  ```bash
  $ ls
  .              1 1 1024
  ..             1 1 1024
  README         2 2 2226
  xargstest.sh   2 3 93
  cat            2 4 24184
  echo           2 5 23008
  forktest       2 6 13232
  grep           2 7 27488
  init           2 8 23744
  kill           2 9 22952
  ln             2 10 22792
  ls             2 11 26376
  mkdir          2 12 23088
  rm             2 13 23072
  sh             2 14 41904
  stressfs       2 15 23952
  usertests      2 16 157000
  grind          2 17 38120
  wc             2 18 25272
  zombie         2 19 22336
  console        3 20 0
  $ 
  ```
  ]

这些是 `mkfs` 包含在初始文件系统中的文件，大多数是我们可以运行的程序，键入 `ls` 便是运行了其中一个。

xv6 没有 `ps` 命令，但是如果输入 `Ctrl-p` ，内核会打印每个进程的信息。现在紧接着尝试输入，我们可以看到两行：一行是 `init`，一行是 `sh`。

+ 如果需要退出 `qemu`，键入 `Ctrl-a x` 即可。

=== 实验小结

通过本次实验，我成功启动了 xv6 内核并且可以在命令行中完成一些基本操作。这让我熟悉了 xv6 内核的构建运行方法，为后续实验打下了基础。

== sleep

=== 实验目的

+ 本实验将为 xv6 实现一个 UNIX 程序 `sleep`；
+ 实现的 sleep 应当按用户指定的 ticks 数暂停，其中 tick 是 xv6 内核定义的时间概念，即定时器芯片两次中断之间的时间。

=== 实验步骤

+ 在开始编码之前，阅读 #link("https://pdos.csail.mit.edu/6.828/2021/xv6/book-riscv-rev2.pdf")[xv6 book] 的第一章，并使用 VSCode 连接 WSL 或使用 Vim 查看 `user/` 中的其他程序（如 `user/echo.c`、`user/grep.c` 和 `user/rm.c`），了解如何获取传递命令行参数给程序。
+ 查看实现 `sleep` 所需的代码：
  - 通过 `kernel/sysproc.c` 中的 `sys_sleep` 获取实现 `sleep` 系统调用的 xv6 内核代码；
  - 通过 `user/user.h` 获取可从用户程序调用 `sleep` 的 C 语言定义；
  - 通过 `user/usys.S` 获取从用户代码跳转到内核以实现 `sleep` 的汇编代码。
+ 编写 `sleep` 程序的代码，创建 `user/sleep.c` 并在其中完成实现，代码如下：

  #blockquote[
  ```c
  #include "kernel/types.h"
  #include "kernel/stat.h"
  #include "user/user.h"

  int main(int argc, char *argv[])
  {
    if (argc < 2) {
      fprintf(2, "Arguments missed.\nUsage: sleep <ticks>\n");
      exit(-1);
    }
    int time = atoi(argv[1]);
    sleep(time);
    exit(0);
  }
  ```
  ]

+ 将 `sleep` 程序添加到 `Makefile` 的 `UPROGS` 列表中，这样运行 `make qemu` 时就会编译新增的 `sleep` 程序，修改后如下：

  #blockquote[
  ```makefile
  UPROGS=\
          $U/_cat\
          $U/_echo\
          $U/_forktest\
          $U/_grep\
          $U/_init\
          $U/_kill\
          $U/_ln\
          $U/_ls\
          $U/_mkdir\
          $U/_rm\
          $U/_sh\
          $U/_stressfs\
          $U/_usertests\
          $U/_grind\
          $U/_wc\
          $U/_zombie\
          $U/_sleep\
  ```
  ]

+ 在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行测试结果如下：

#figure(
  image("..\assets\sleep-test.png", width: 80%),
  caption: [`sleep` 程序测试结果],
) <fig-sleep-test>

运行 `./grade-lab-util sleep` 进行评测，得到如下结果：

#figure(
  image("..\assets\sleep-grade.png", width: 80%),
  caption: [`sleep` 程序评测结果],
) <fig-sleep-grade>

=== 实验小结

程序编写过程中，LSP 提示出现了未定义类型，使用 `make qemu` 编译运行时也出现该提示。查看内核代码和文档后得知 `user/user.h` 使用了 `kernel/types.h` 中的定义，需要在 `user/user.h` 前先引入头文件 `kernel/types.h` 头文件。

本次实验中我完成了 xv6 系统中的第一个程序，学会了如何调用内核函数实现一个简单的 `sleep` 程序，并且能够正确处理命令行参数。这加深了我对于操作系统与系统编程的理解。

== pingpong

=== 实验目的

+ 本实验将为 xv6 实现一个 UNIX 程序 `pingpong`，使用 UNIX 系统调用通过一对管道在两个进程之间 “ping-pong” 一个字节，每个管道对应一个方向。父进程应该向子进程发送一个字节；子进程应该打印 “`<pid>: received ping`”，其中 `<pid>` 是它的进程ID，将管道上的字节写给父进程，然后退出；父进程应该从子进程读取字节，打印 “`<pid>: received pong`” 后退出。
+ 理解父进程与子进程的关系及其执行顺序，并学习使用管理进行进程间通信，实现父子进程之间的数据交换。
+ 掌握进程同步的概念，确保父子进程在适当的时机进行通信。

=== 实验步骤

+ 在 `user/user.h` 中查看 xv6 上的用户程序的一组库函数；并在 `user/ulib.c`、`user/printf.c` 和 `user/umalloc.c` 中查看其他源代码（系统调用除外）。

+ 编写 `pingpong` 程序的代码，需要用到如下函数：
  + 使用 `pipe` 创建管道，
  + 使用 `fork` 创建子进程，
  + 使用 `read` 从管道中读取字节，
  + 使用 `write` 将字节写入管道，
  + 使用 `getpid` 获取调用进程的进程 ID，实现父子进程之间的字节交换和输出。
  代码如下：

  #blockquote[
  ```c
  #include "kernel/types.h"
  #include "kernel/stat.h"
  #include "user/user.h"

  int main(int argc, char *argv[])
  {
    if (argc > 1) {
      fprintf(2, "Too many arguments.\n");
      exit(-1);
    }

    int parent_fd[2], child_fd[2];
    char buf[10];

    if (pipe(parent_fd) < 0 || pipe(child_fd) < 0) {
      fprintf(2, "Pipe create failed\n");
      exit(-1);
    }

    int pid;
    pid = fork();

    if (pid < 0) {
      fprintf(2, "Fork failed\n");
      exit(-1);
    }

    if (pid == 0) {
      // 子进程
      close(child_fd[0]);
      close(parent_fd[1]);

      // 从管道读取字节
      if (read(parent_fd[0], buf, 4) == -1) {
        fprintf(2, "Child process read failed\n");
        exit(-1);
      }
      close(parent_fd[0]);

      printf("%d: received %s\n", getpid(), buf);

      // 向管道发送字节
      if (write(child_fd[1], "pong", 4) == -1) {
        fprintf(2, "Child process write failed\n");
        exit(-1);
      }

      close(parent_fd[1]);
      exit(0);
    }
    else {
      // 父进程
      close(child_fd[1]);
      close(parent_fd[0]);

      // 向管道发送字节
      if (write(parent_fd[1], "ping", 4) == -1) {
        printf("Parent process write failed\n");
        exit(-1);
      }

      // 等待子进程结束
      wait(0);

      close(parent_fd[1]);
      // 从管道读取字节
      if (read(child_fd[0], buf, 4) == -1) {
        printf("Parent process read failed\n");
        exit(-1);
      }

      close(child_fd[0]);
      printf("%d: received %s\n", getpid(), buf);

      exit(0);
    }
  }
  ```
  ]

+ 和 `sleep` 一样，将 `pingpong` 程序添加到 `Makefile` 的 `UPROGS` 列表中，然后在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行测试结果如下：

#figure(
  image("..\assets\pingpong-test.png", width: 80%),
  caption: [`pingpong` 程序测试结果],
) <fig-pingpong-test>

运行 `./grade-lab-util pingpong` 进行评测，得到如下结果：

#figure(
  image("..\assets\pingpong-grade.png", width: 80%),
  caption: [`pingpong` 程序评测结果],
) <fig-pingpong-grade>

=== 实验小结

在本次实验中，我在实践中学习使用了如何使用 UNIX 系统调用在父子进程之间通信，学会了如何使用 `fork` 函数创建子进程并通过 `pipe`、`read` 和 `write` 等函数创建管道并用管道在父子进程之间传递字节信息。本次实验加深了我对于操作系统进程与管道的理解，掌握了进程间同步的方法。

== primes

=== 实验目的

+ 使用管道编写一个素数筛选器的并发版本。解决方案位于 `user/primes.c` 中。
+ 学习使用 `pipe` 和 `fork` 来设置管道。第一个进程将数字 2 到 35 输入管道。对于每个素数创建一个进程，该进程通过一个管道从左边的邻居读取数据，并通过另一个管道向右边的邻居写入数据。由于 xv6 的文件描述符和进程数量有限，第一个进程可以在 35 处停止。
+ 理解并掌握进程间通信的概念和机制。
+ 学习如何使用管道在父子进程之间进行数据传递。

=== 实验步骤

+ 编写 `primes` 程序代码，创建第一个子进程，由主进程将数字 2 到 35 输入到管道中，其余子进程在需要时由当前子进程创建。
+ 对于 2 到 35 中的每个素数都创建一个进程，各进程从左边的父进程读取数据，然后通过另一个管道向右边子进程写入数据。
+ 各子进程最顶部的数即为素数，将该数打印输出，由各子进程对当前进程中的剩余数进行检查，如果不能用该进程的素数整除则写入下一进程，如果可以整除则跳过。
+ 数据传递过程中，父进程需要等待子进程结束并回收共享的资源和数据等。因此主进程需要等待所有输出打印完成，并且其他子进程都退出后才退出。
+ 按照上述思路编写代码，素数筛相关逻辑如下：

  #blockquote[
  ```c
  void new_proc(int p[])
  {
    int prime;
    int n;

    // 关闭 p 管道的写端
    close(p[1]);
    if (read(p[0], &prime, 4) != 4) {
      fprintf(2, "Read failed\n");
      exit(-1);
    }
    printf("prime %d\n", prime);

    // read 返回不为 0 且还需要下一个进程时
    if (read(p[0], &n, 4) == 4) {
      int new_p[2];
      if (pipe(new_p) < 0) {
        fprintf(2, "Pipe create failed\n");
        exit(-1);
      }

      int pid = fork();
      if (pid < 0) {
        fprintf(2, "Fork failed\n");
        exit(-1);
      }

      if (pid == 0) {
        // 子进程
        new_proc(new_p);
      }
      else {
        // 父进程
        close(new_p[0]);
        if (n % prime)
          write(new_p[1], &n, 4);
        while (read(p[0], &n, 4) == 4) {
          if (n % prime)
            write(new_p[1], &n, 4);
        }
        close(p[0]);
        close(new_p[1]);

        wait(0);
      }
    }
  }
  ```
  ]

+ 将 `primes` 程序添加到 `Makefile` 的 `UPROGS` 列表中，然后在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行测试结果如下：

#figure(
  image("..\assets\primes-test.png", width: 50%),
  caption: [`primes` 程序运行结果],
) <fig-primes-test>

运行 `./grade-lab-util primes` 进行评测，得到如下结果：

#figure(
  image("..\assets\primes-grade.png", width: 80%),
  caption: [`primes` 程序评测结果],
) <fig-primes-grade>

=== 实验小结

在本次实验中，我完成了一个并发版本的素数查找程序，使用管道实现了一个简单的并发筛选器。通过本次实验，我进一步掌握了进程与管道的创建和使用方法，加深了对于进程、管道的理解，对 xv6 内核有了更为深入的了解。

== find

=== 实验目的

+ 编写一个简单版本的 UNIX 程序 `find`，查找目录树中具有特定名称的所有文件。解决方案位于文件 `user/find.c` 中。
+ 理解文件系统中目录和文件的基本概念和组织结构。
+ 熟悉在 xv6 操作系统中使用系统调用和文件系统接口进行文件查找操作。

=== 实验步骤

+ 查看 `user/ls.c`，了解如何读取目录。它包含了两个主要函数：
  - `void ls(char *path)`：用于显示指定路径下的所有文件（包含目录）；
  - `char *fmtname(char *path)`：提取出给定路径的文件名并返回规范化字符串用于打印，如果名称的长度大于等于 `DIRSIZ` 则直接返回名称，否则就将名称拷贝到静态字符数组 `buf` 中用空格填充剩余空间，保证输出的名称长度为 `DIRSIZ`。
+ 在 `main` 函数中完成参数检查和 `find` 函数的调用。要求参数数量为 3，将第一个参数作为路径，第二个参数作为需要查找的文件名称，参数不足则打印提示信息并退出程序，否则调用 `find` 函数进行查找，最后退出程序。
+ 修改 `ls.c` 的 `fmtname` 函数为 `match` 函数，用于检查给定路径与名称是否匹配，即在提取出路径最后一个 `/` 后的文件名后将其与给定名称比较即可。如果匹配则返回 1，否则返回 0：

  #blockquote[
  ```c
  int fmtname(char *path, char *name)
  {
    static char buf[DIRSIZ+1];
    char *p;

    // 找到最后一个 / 后的第一个字符
    for(p=path+strlen(path); p >= path && *p != '/'; p--)
      ;
    p++;

    // 检查文件名与给定名称是否匹配
    if (strcmp(p, name) == 0)
      return 1;
    else
      return 0;
  }
  ```
  ]

+ 修改 `ls.c` 的 `ls` 函数为 `find` 函数，用于递归地在给定目录中查找带有特定名称的文件，即修改对于不同类型目录的处理部分的逻辑：
  - 对于 `T_FILE`，使用 `match` 函数检查文件名称，如果与给定名称匹配则打印文件路径。
  - 对于 `T_DIR`，遍历目录中的每个文件，在检查过路径长度后，将路径拷贝到 `buf` 中并在路径后添加 `/`。接着循环读取目录中每个文件信息，跳过当前目录 `.` 和上级目录 `..`。最后将文件名拷贝到 `buf` 中递归调用 `find` 函数在子目录中进一步查找。
  - 关闭目录文件描述符。

  #blockquote[
  ```c
  void find(char *path, char *name)
  {
    char buf[512], *p;
    int fd;
    struct dirent de;
    struct stat st;

    if ((fd = open(path, 0)) < 0) {
      fprintf(2, "find: cannot open %s\n", path);
      exit(-1);
    }

    if (fstat(fd, &st) == -1) {
      fprintf(2, "find: cannot fstat %s\n", path);
      close(fd);
      exit(-1);
    }

    // 根据目录类型的不同分别处理
    switch (st.type) {
      case T_FILE:
        if (match(path, name))
          printf("%s\n", path);
        break;

      case T_DIR:
        if (strlen(path) + 1 + DIRSIZ + 1 > sizeof buf) {
          fprintf(2, "find: path too long\n");
          break;
        }
        strcpy(buf, path);
        p = buf + strlen(buf);
        *p++ = '/';

        while (read(fd, &de, sizeof de) == sizeof de) {
          // 跳过空目录、当前目录与上一级目录
          if (de.inum == 0 || strcmp(de.name, ".") == 0 || strcmp(de.name, "..") == 0)
            continue;

          memmove(p, de.name, DIRSIZ);
          p[DIRSIZ] = '\0';
          if (stat(buf, &st) < 0) {
            fprintf(2, "find: cannot stat %s\n", buf);
            continue;
          }
          find(buf, name);
        }
        break;
      default:
        break;
    }
    close(fd);
  }
  ```
  ]

+ 将 `find` 程序添加到 `Makefile` 的 `UPROGS` 列表中，然后在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行测试结果如下：

#figure(
  image("..\assets\find-test.png", width: 60%),
  caption: [`find` 程序运行结果],
) <fig-find-test>

运行 `./grade-lab-util find` 进行评测，得到如下结果：

#figure(
  image("..\assets\find-grade.png", width: 80%),
  caption: [`find` 程序评测结果],
) <fig-find-grade>

=== 实验小结

由于本次实验中，程序的大体逻辑主要参考 `ls.c` 程序，而 `ls.c` 程序只能列出指定目录下的文件信息，因此最开始实现时并不能递归查找子目录中的文件。在修改过程序逻辑提供递归的逻辑后，程序才可以给出更为全面的查找结果。

通过完成 `find.c` 程序，我理解了 xv6 的文件系统中目录与文件的概念，并学会通过系统调用和文件系统接口访问并操作文件。在完成程序的过程中，我阅读参考了 `ls.c` 程序，掌握了如何在 xv6 操作系统中使用系统调用与文件接口读取目录、打开文件并读取文件信息。这提高了我阅读源码与文档的能力，也加深了我对于文件系统的理解与应用能力。

== xargs

=== 实验目的

+ 编写一个 UNIX 程序 `xargs` 的简单版本：从标准输入中读取行，并为每一行运行一个命令，将行作为参数提供给命令。解决方案位于文件`user/xargs.c`中。
+ 了解 shell 管道的原理与使用方法。
+ 学习使用 `exec` 执行外部命令，理解执行外部程序的基本原理。

=== 实验步骤

+ 首先需要读取用户输入，需要读取单行输入，每次读取一个字符直到出现换行符。

+ 读取完单行输入后，将 `xargs` 的参数和读取到的参数分别放入 `args` 数组，然后调用指令执行函数 `exec_cmd`。

+ 使用 `fork` 和 `exec` 来调用每行输入的命令。在父进程中使用 `wait` 函数等待子进程完成命令的执行。可以编写如下指令执行函数：

  #blockquote[
  ```c
  void exec_cmd(char *cmd, char *args[])
  {
    if (fork() > 0) {
      // 父进程
      wait(0);
    }
    else {
      // 子进程
      if (exec(cmd, args) < 0) {
        fprintf(2, "xargs: command %s execute failed\n", cmd);
        exit(-1);
      }
      exit(0);
    }
  }
  ```
  ]

+ 将 `xargs` 程序添加到 `Makefile` 的 `UPROGS` 列表中，然后在 xv6 shell 中运行程序进行测试。

=== 评测结果

运行测试结果如下：

#figure(
  image("..\assets\x.png", width: 80%),
  caption: [`xargs` 程序测试结果],
) <fig-x>

运行 `./grade-lab-util xargs` 进行评测，得到如下结果：

#figure(
  image("..\assets\xargs-grade.png", width: 80%),
  caption: [`xargs` 程序评测结果],
) <fig-xargs-grade>

=== 实验小结

在实验过程中，最初调用 `exec` 函数时总是失败，查询过文档和资料后得知，参数列表指针数组末尾需要有一个空指针作为数组结束标志。修改后程序可以正常运行。

通过完成 `xargs.c` 程序，我学会了如何处理标准输入中传入的参数并将其存储在适当的数据结构中，还通过调用 `exec` 函数执行外部命令，深入了解了进程创建和替换的过程，了解了如何在子进程中执行外部程序。这使我更加理解了 xv6 中程序的调用逻辑，加深对于操作系统的理解。

