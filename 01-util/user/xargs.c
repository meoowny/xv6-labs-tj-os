#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/param.h"
#include "user/user.h"

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

void xargs(char *argv[], int argc, char *cmd)
{
  char *args[MAXARG];
  char buf[1024];
  int n = 0;
  while (read(0, buf + n, 1) == 1) {
    if (n >= 1024) {
      fprintf(2, "xargs: arguments too long.\n");
      exit(1);
    }

    if (buf[n] != '\n') {
      n++;
      continue;
    }

    buf[n] = '\0';
    memmove(args, argv, sizeof(*argv) * argc);

    int index = argc;
    if (index == 0) {
      args[index] = cmd;
      index++;
    }

    args[index] = malloc(sizeof(char) * (n + 1));
    memmove(args[index], buf, n + 1);

    args[index + 1] = 0;
    exec_cmd(cmd, args);
    free(args[index]);
    n = 0;
  }
}

int main(int argc, char *argv[])
{
  if (argc < 2) {
    fprintf(2, "Too few arguments.\nUsage: xargs <command> <args>\n");
    exit(-1);
  }

  xargs(argv + 1, argc - 1, argv[1]);

  exit(0);
}
