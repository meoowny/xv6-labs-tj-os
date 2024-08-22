#import "@preview/ilm:1.2.1": *

= Lab: Networking <net>

== 实验概述

本实验中，我将为网络接口卡（network interface card, NIC）编写 xv6 设备驱动程序。在这里，我将使用一个名为 E1000 的网络设备来处理网络通信，并使用 QEMU 的“用户模式网络堆栈”进行仿真。通过学习初始化并操作一个虚拟的网络设备，以及处理网络通信，来深入理解操作系统中设备驱动程序的工作原理。

开始编码之前，阅读 #link("https://pdos.csail.mit.edu/6.828/2021/xv6/book-riscv-rev2.pdf")[xv6 book] 的第 5 章“中断与设备驱动程序”的内容。

开始实验前需要使用 ```bash git checkout net``` 先切换到 `net` 分支，将代码复制到 net 目录下。

== 实现一个驱动程序

=== 实验目的

+ 完成 `kernel/e1000.c` 中的 `e1000_transmit()` 和 `e1000_recv()` 两个函数，使驱动程序可以传输和接收数据包。

=== 实验步骤

+ 本次使用 E1000 的网络设备来处理网络通信，在 QEMU 中通过模拟出的 E1000 硬件连接到真实的局域网（LAN）。在这个模拟的局域网上，`Guest` 的 IP 地址为 `10.0.2.15`，`Host` 的 IP 地址为 `10.0.2.2`。

+ 本次实验主要涉及如下文件：
  + `kernel/e1000.c` 文件包含了 E1000 的初始化代码，与用于发送接收数据包的空函数有待完成。
  + `kernel/e1000_dev.h` 文件包含了 E1000 寄存器和标志位的定义，可以查看 E1000 #link("https://pdos.csail.mit.edu/6.828/2021/readings/8254x_GBe_SDM.pdf")[软件开发人员手册] 来了解如何操作 E1000 寄存器和描述符。
  + `kernel/net.c` 与 `kernel/net.h` 文件包含了一个实现 IP、UDP 和 ARP 协议的简单网络栈。同时用于保存数据包的 `mbuf` 也位于其中。
  + `kernel/pci.c` 文件包含了 xv6 引导时在 PCI 总线上搜索 E1000 的代码。

+ 首先实现 `kernel/e1000.c` 文件中用于发送数据包的 `e1000_transmit()` 函数：
  + 先获取锁并读取 `E1000_TDT` 控制寄存器，从 E1000 获取发送环的下一个可用位置，以确定将要使用的描述符在发送环中的位置。
  + 然后读取该位置的描述符，检查环是否溢出。如果描述符未设置 `E1000_TXD_STAT_DD`，则说明上一个传输还在进行中，释放锁并返回 -1 表示传输失败。
  + 如果未溢出且该位置缓冲区 `tx_mbufs[index]` 不为空，则使用 `mbuffree()` 释放旧的缓冲区。
  + 然后将待发送的 `mbuf` 数据包指针存储在 `tx_mbufs` 数组中，将其地址 `m->head` 存储中对应描述符的 `addr` 字段中。描述符 `length` 字段设置为 `mbuf` 的长度 `m->len`，设置的 `cmd` 标志为 `E1000_TXD_CMD_RS | E1000_TXD_CMD_EOP`。
  + 更新 E1000_TDT 控制寄存器，指向下一个描述符。
  + 最后使用 `__sync_synchronize()` 函数确保所有前面的操作对其他线程可见，然后释放锁。
  #blockquote[
  ```c
  acquire(&e1000_lock);

  // 读取 E1000_TDT 控制寄存器以获取下一个数据包的 TX 环索引
  uint64 index = regs[E1000_TDT];

  if (!(tx_ring[index].status & E1000_TXD_STAT_DD)) {
    release(&e1000_lock);
    return -1;
  }

  // 释放上一个数据包
  if (tx_mbufs[index])
    mbuffree(tx_mbufs[index]);

  tx_mbufs[index] = m;
  tx_ring[index].length = m->len;
  tx_ring[index].addr = (uint64)m->head;
  // 设置标志位，表示发送完该数据包产生一个中断
  // E1000_TXD_CMD_EOP 为结束位，表示这是该数据包最后一个描述符
  tx_ring[index].cmd = E1000_TXD_CMD_RS | E1000_TXD_CMD_EOP;

  tx_ring[index].status = 0;

  // 更新 E1000_TDT 控制寄存器
  regs[E1000_TDT] = (index + 1) % TX_RING_SIZE;
  __sync_synchronize();

  release(&e1000_lock);
  ```
  ]

+ 接下来实现 `kernel/e1000.c` 文件中用于接收数据包的 `e1000_recv()` 函数：
  + 先获取锁并读取 `E1000_TDT` 控制寄存器，从 E1000 获取发送环的下一个可用位置，以确定将要使用的描述符在发送环中的位置。
  + 然后循环读取该位置的描述符，检查是否有新数据包到达。如果描述符未设置 `E1000_TXD_STAT_DD`，则直接结束循环并返回。

  + 如果有新数据包，则将 `mbuf` 的 `len` 字段更新为包的长度 `rx_ring[index]->length`，并使用 `net_rx()` 将 `mbuf` 传送到上层网络栈。
  + 分配一个新的 `mbuf` 并写入描述符，替换刚刚传送给 `net_rx()` 的 `mbuf`，将描述符状态位复位并将其数据指针 `head` 赋到描述符中。
  + 最后更新 `E1000_RDT` 寄存器为最后处理的环描述符的索引，并使用 `__sync_synchronize()` 函数确保所有前面的操作对其他线程可见。
  #blockquote[
  ```c
  // 获取接收包的位置
  uint64 index = (regs[E1000_RDT] + 1) % RX_RING_SIZE;

  while (rx_ring[index].status & E1000_RXD_STAT_DD) {
    // 更新 mbuf 长度并将结果传送到上层网络协议栈
    rx_mbufs[index]->len = rx_ring[index].length;
    net_rx(rx_mbufs[index]);

    // 分配新的 mbuf 并写入到描述符中，并将描述状态码设置为 0
    rx_mbufs[index] = mbufalloc(0);
    rx_ring[index].status = 0;
    rx_ring[index].addr = (uint64)rx_mbufs[index]->head;

    regs[E1000_RDT] = index;
    __sync_synchronize();

    // 更新 index，继续处理下一个接收到的数据包
    index = (regs[E1000_RDT] + 1) % RX_RING_SIZE;
  }
  ```
  ]

+ 测试驱动程序时，可以在一个窗口中运行 `make server` 然后在另一个窗口中运行 `make qemu` 并在 xv6 中运行 `nettests`。这些测试将模拟发送和接收数据包的情况，可以根据输出情况判断驱动程序的行为是否符合预期。

+ 在 xv6 shell 中运行程序进行测试。

#pagebreak()

=== 评测结果

运行 `make server` 后在 xv6 中运行 `nettests` 可以得到如下结果：

#figure(
  image("../assets/net-test.png", width: 45%),
  caption: [NIC 驱动程序测试结果],
) <fig-net-test>

`server` 端的输出信息如下：

#figure(
  image("../assets/net-server-output.png", width: 70%),
  caption: [驱动程序测试服务器输出信息],
) <fig-net-server-output>

使用 `tcpdump -XXnr packets.pcap` 命令进行测试，得到的结果如下图所示：

#figure(
  image("../assets/tcp-info.png", width: 70%),
  caption: [`tcpdump` 运行结果],
) <fig-tcp-info>

运行 `./grade-lab-net` 进行评测，得到如下结果：

#figure(
  image("../assets/net-grade.png", width: 80%),
  caption: [驱动程序评测结果],
) <fig-net-grade>

=== 实验小结

有些时候之前的数据包总数会超出环缓冲区 16 的大小，发生越界错误。这就需要我们将线性存储的数组的逻辑结构设计为一个环，通过将 `E1000_TDT` 加 1 对 `TX_RING_SIZE` 取模得到合适的索引值。

通过本次实验，我了解了设备驱动程序的基本概念与工作原理。在实际编写和调试过程中，我学会了如何初始化并操作虚拟网络设备，并能够正确处理数据包的发送与接收。同时我还学会了如何使用锁，能够使用互斥锁与同步机制保证多个进程或多个内核线程对设备的正确访问。这些让我对操作系统内核与设备驱动程序有了更深入的了解。

