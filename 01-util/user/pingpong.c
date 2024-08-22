#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

int main(int argc, char *argv[])
{
  if (argc > 1) {
    fprintf(2, "Too many arguments.\nUsage: pingpong\n");
    exit(-1);
  }

  int parent_fd[2], child_fd[2];
  char buf[10];

  if (pipe(parent_fd) < 0 || pipe(child_fd) < 0) {
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
    close(child_fd[0]);
    close(parent_fd[1]);

    // 从管道读取字节
    if (read(parent_fd[0], buf, 4) == -1) {
      fprintf(2, "primes: child process read failed\n");
      exit(-1);
    }
    close(parent_fd[0]);

    printf("%d: received %s\n", getpid(), buf);

    // 向管道发送字节
    if (write(child_fd[1], "pong", 4) == -1) {
      fprintf(2, "primes: child process write failed\n");
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
