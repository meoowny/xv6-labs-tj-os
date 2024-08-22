// Physical memory allocator, for user processes,
// kernel stacks, page-table pages,
// and pipe buffers. Allocates whole 4096-byte pages.

#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "spinlock.h"
#include "riscv.h"
#include "defs.h"

void freerange(void *pa_start, void *pa_end);

extern char end[]; // first address after kernel.
                   // defined by kernel.ld.

struct run {
  struct run *next;
};

struct {
  struct spinlock lock;
  struct run *freelist;
} kmem[NCPU];

void
kinit()
{
  char kmem_name[32];
  for (int i = 0; i < NCPU; i++) {
    snprintf(kmem_name, 32, "kmem_%d", i);
    initlock(&kmem[i].lock,kmem_name);
  }
  freerange(end, (void*)PHYSTOP);
}

void
freerange(void *pa_start, void *pa_end)
{
  char *p;
  p = (char*)PGROUNDUP((uint64)pa_start);
  for(; p + PGSIZE <= (char*)pa_end; p += PGSIZE)
    kfree(p);
}

// Free the page of physical memory pointed at by v,
// which normally should have been returned by a
// call to kalloc().  (The exception is when
// initializing the allocator; see kinit above.)
void
kfree(void *pa)
{
  struct run *r;

  if(((uint64)pa % PGSIZE) != 0 || (char*)pa < end || (uint64)pa >= PHYSTOP)
    panic("kfree");

  // Fill with junk to catch dangling refs.
  memset(pa, 1, PGSIZE);

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
}

// Allocate one 4096-byte page of physical memory.
// Returns a pointer that the kernel can use.
// Returns 0 if the memory cannot be allocated.
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
