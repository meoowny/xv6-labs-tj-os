#include "types.h"
#include "riscv.h"
#include "param.h"
#include "defs.h"
#include "date.h"
#include "memlayout.h"
#include "spinlock.h"
#include "proc.h"

uint64
sys_exit(void)
{
  int n;
  if(argint(0, &n) < 0)
    return -1;
  exit(n);
  return 0;  // not reached
}

uint64
sys_getpid(void)
{
  return myproc()->pid;
}

uint64
sys_fork(void)
{
  return fork();
}

uint64
sys_wait(void)
{
  uint64 p;
  if(argaddr(0, &p) < 0)
    return -1;
  return wait(p);
}

uint64
sys_sbrk(void)
{
  int addr;
  int n;

  if(argint(0, &n) < 0)
    return -1;
  
  addr = myproc()->sz;
  if(growproc(n) < 0)
    return -1;
  return addr;
}

uint64
sys_sleep(void)
{
  int n;
  uint ticks0;


  if(argint(0, &n) < 0)
    return -1;
  acquire(&tickslock);
  ticks0 = ticks;
  while(ticks - ticks0 < n){
    if(myproc()->killed){
      release(&tickslock);
      return -1;
    }
    sleep(&ticks, &tickslock);
  }
  release(&tickslock);
  return 0;
}


#ifdef LAB_PGTBL
int
sys_pgaccess(void)
{
  // lab pgtbl: your code here.

  uint64 va;            // 需要检查的用户页面的起始虚拟地址
  int pgnum;            // 要检查的页面数
  uint64 bitmask_addr;  // 缓冲区的用户地址，用于将结果存储到位掩码中

  argaddr(0, &va);
  argint(1, &pgnum);
  argaddr(2, &bitmask_addr);

  if (pgnum > 32 || pgnum < 0)
    return -1;

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
      // 清除 PTE_A 位
      *pte &= (~PTE_A);
    }
    va += PGSIZE;
  }

  // 将位掩码复制到用户空间
  if (copyout(p->pagetable, bitmask_addr, (char*)&bitmask, sizeof(bitmask)) < 0)
    return -1;
  return 0;
}
#endif

uint64
sys_kill(void)
{
  int pid;

  if(argint(0, &pid) < 0)
    return -1;
  return kill(pid);
}

// return how many clock tick interrupts have occurred
// since start.
uint64
sys_uptime(void)
{
  uint xticks;

  acquire(&tickslock);
  xticks = ticks;
  release(&tickslock);
  return xticks;
}
