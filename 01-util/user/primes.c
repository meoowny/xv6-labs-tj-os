#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

void new_proc(int p[])
{
  int prime;
  int n;

  // 关闭 p 管道的写端
  close(p[1]);
  if (read(p[0], &prime, 4) != 4) {
    fprintf(2, "primes: read failed\n");
    exit(-1);
  }
  printf("prime %d\n", prime);

  // read 返回不为 0 且还需要下一个进程时
  if (read(p[0], &n, 4) == 4) {
    int new_p[2];
    if (pipe(new_p) < 0) {
      fprintf(2, "primes: pipe create failed\n");
      exit(-1);
    }

    int pid = fork();
    if (pid < 0) {
      fprintf(2, "primes: fork failed\n");
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

int main(int argc, char *argv[])
{
  int p[2];

  if (pipe(p) < 0) {
    fprintf(2, "primes: pipe create failed\n");
    exit(-1);
  }

  int pid = fork();

  if (pid < 0) {
    fprintf(2, "primes: fork failed\n");
    exit(-1);
  }

  if (pid == 0) {
    // 子进程
    new_proc(p);
    exit(0);
  }
  else {
    // 父进程
    close(p[0]);
    for (int i = 2; i <= 35; i++) {
      if (write(p[1], &i, 4) != 4) {
        fprintf(2, "primes: ailed to write %d into the pipe\n", i);
        exit(-1);
      }
    }
    close(p[1]);

    wait(0);
    exit(0);
  }
}
