#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fs.h"
#include "user/user.h"

int match(char *path, char *name)
{
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

int main(int argc, char *argv[])
{
  if (argc != 3) {
    fprintf(2, "Usage: find <path> <file>\n");
    exit(-1);
  }

  char *path = argv[1];
  char *name = argv[2];

  find(path, name);
  exit(0);
}
