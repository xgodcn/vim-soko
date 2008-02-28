#include <uim/uim.h>
#include <uim/uim-helper.h>
#include <dlfcn.h>
#include <sys/types.h>
#include <sys/wait.h>

#include <stdlib.h>
#include <string.h>

#define UIM_CTL_HELPER_CMD "/uim-ctl-helper"

int pid = 0;
FILE *fin;
FILE *fout;
char *cmd;
char *retptr;

const char*
load(const char* path)
{
  char *p;
  size_t s;

  s = strlen(path) + strlen(UIM_CTL_HELPER_CMD) + 1;
  cmd = malloc(s);
  if (cmd == NULL)
    return "malloc error";

  strlcpy(cmd, path, s);
  p = strrchr(cmd, '/');
  if (p == NULL)
    return "path separator error";
  *p = '\0';
  strlcat(cmd, UIM_CTL_HELPER_CMD, s);

  pid = uim_ipc_open_command(0, &fin, &fout, cmd);
  if (pid == 0)
    return "error: uim_ipc_open_command()";

  dlopen(path, RTLD_LAZY);

  return 0;
}

const char*
unload()
{
  if (fin != NULL)
    fclose(fin);
  if (fout != NULL)
    fclose(fout);
  if (pid != 0)
    waitpid(pid, NULL, 0);
  return 0;
}

const char*
get_prop()
{
  if (retptr)
    free(retptr);
  retptr = uim_ipc_send_command(&pid, &fin, &fout, cmd, "<prop_list_get>\n\n");
  return retptr;
}

const char*
send_message(const char* msg)
{
  fprintf(fout, "%s\n", msg);
  fflush(fout);
  return NULL;
}

