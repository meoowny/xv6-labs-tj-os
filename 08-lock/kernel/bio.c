// Buffer cache.
//
// The buffer cache is a linked list of buf structures holding
// cached copies of disk block contents.  Caching disk blocks
// in memory reduces the number of disk reads and also provides
// a synchronization point for disk blocks used by multiple processes.
//
// Interface:
// * To get a buffer for a particular disk block, call bread.
// * After changing buffer data, call bwrite to write it to disk.
// * When done with the buffer, call brelse.
// * Do not use the buffer after calling brelse.
// * Only one process at a time can use a buffer,
//     so do not keep them longer than necessary.


#include "types.h"
#include "param.h"
#include "spinlock.h"
#include "sleeplock.h"
#include "riscv.h"
#include "defs.h"
#include "fs.h"
#include "buf.h"

#define NBUCKET 13

struct bucket {
  struct spinlock lock;  // 自旋锁，用于保护对该桶的并发访问
  struct buf head;       // 缓冲区指针，用于构建 LRU 缓冲区的链表
} hashtable[NBUCKET];

struct {
  struct spinlock lock;
  struct buf buf[NBUF];

  // Linked list of all buffers, through prev/next.
  // Sorted by how recently the buffer was used.
  // head.next is most recent, head.prev is least.
  // struct buf head;
} bcache;

int
hash(uint blockno)
{
  return blockno % NBUCKET;
}

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

// Look through buffer cache for block on device dev.
// If not found, allocate a buffer.
// In either case, return locked buffer.
static struct buf*
bget(uint dev, uint blockno)
{
  struct buf *b;

  int index = hash(blockno);
  struct bucket* bucket = &hashtable[index];
  acquire(&bucket->lock);

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

  // Not cached.
  // Recycle the least recently used (LRU) unused buffer.
  struct buf *min_b = 0;
  uint min_time = 0x7fffffff;
  uint cur_bucket = -1;

  for (int i = 0; i < NBUCKET; i++) {
    acquire(&hashtable[i].lock);

    int found = 0;
    for (b = &hashtable[i].head; b->next != 0; b = b->next) {
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
}

// Return a locked buf with the contents of the indicated block.
struct buf*
bread(uint dev, uint blockno)
{
  struct buf *b;

  b = bget(dev, blockno);
  if(!b->valid) {
    virtio_disk_rw(b, 0);
    b->valid = 1;
  }
  return b;
}

// Write b's contents to disk.  Must be locked.
void
bwrite(struct buf *b)
{
  if(!holdingsleep(&b->lock))
    panic("bwrite");
  virtio_disk_rw(b, 1);
}

// Release a locked buffer.
// Move to the head of the most-recently-used list.
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


