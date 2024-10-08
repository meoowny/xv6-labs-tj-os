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
} kmem;

struct refcnt {
  struct spinlock lock;
  int count[PHYSTOP / PGSIZE];
} pg_ref_count;

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

int
get_pgref_count(void *pa)
{
  return pg_ref_count.count[(uint64)pa / PGSIZE];
}

void
kinit()
{
  initlock(&kmem.lock, "kmem");
  // 初始化 pg_ref_count 锁
  initlock(&pg_ref_count.lock, "pg_ref_count");
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

  int temp;

  acquire(&pg_ref_count.lock);
  pg_ref_count.count[(uint64)pa / PGSIZE]--;
  temp = pg_ref_count.count[(uint64)pa / PGSIZE];
  release(&pg_ref_count.lock);

  if (temp > 0)
    return;

  // Fill with junk to catch dangling refs.
  memset(pa, 1, PGSIZE);

  r = (struct run*)pa;

  acquire(&kmem.lock);
  r->next = kmem.freelist;
  kmem.freelist = r;
  release(&kmem.lock);
}

// Allocate one 4096-byte page of physical memory.
// Returns a pointer that the kernel can use.
// Returns 0 if the memory cannot be allocated.
void *
kalloc(void)
{
  struct run *r;

  acquire(&kmem.lock);
  r = kmem.freelist;
  if(r)
    kmem.freelist = r->next;
  release(&kmem.lock);

  if(r) {
    acquire(&pg_ref_count.lock);
    pg_ref_count.count[(uint64)r / PGSIZE] = 1;
    release(&pg_ref_count.lock);
  }

  if(r)
    memset((char*)r, 5, PGSIZE); // fill with junk
  return (void*)r;
}
