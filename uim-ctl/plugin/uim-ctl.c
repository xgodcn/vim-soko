/* 2007-01-29 */

#include <uim/uim.h>
#include <uim/uim-helper.h>
#include <dlfcn.h>

static int uim_fd;

const char*
load(const char* path)
{
  dlopen(path, RTLD_LAZY);
  uim_fd = uim_helper_init_client_fd(NULL);
  if (uim_fd < 0)
    return "error: uim_helper_init_client_fd()";
  return 0;
}

const char*
unload()
{
  uim_helper_close_client_fd(uim_fd);
  return 0;
}

const char*
pump_event()
{
  static char *ret = 0;
  char *tmp;

  while (uim_helper_fd_readable(uim_fd)) {
    uim_helper_read_proc(uim_fd);
    while (tmp = uim_helper_get_message()) {
      if (strncmp(tmp, "prop_list_update", strlen("prop_list_update")) == 0) {
        if (ret)
          free(ret);
        ret = tmp;
      } else {
        free(tmp);
      }
    }
  }
  return ret;
}

const char*
send_message(const char* msg)
{
  int uim_fd;

  uim_fd = uim_helper_init_client_fd(NULL);
  if (uim_fd < 0)
    return "error: uim_helper_init_client_fd";
  uim_helper_send_message(uim_fd, msg);
  uim_helper_close_client_fd(uim_fd);
  return 0;
}
