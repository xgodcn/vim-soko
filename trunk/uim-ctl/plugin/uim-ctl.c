#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <dlfcn.h>
#include <poll.h>
#include <pthread.h>
#include <unistd.h>

#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <uim/uim.h>
#include <uim/uim-helper.h>

#define RETRY_EINTR(ret, funcall)     \
  do {                                \
    ret = funcall;                    \
  } while (ret == -1 && errno == EINTR)

static void *self;
static int uim_fd;
static char *prop;
static pthread_t twatch;
static pthread_mutex_t mutex;

static void *uimwatch(void *);
static ssize_t xwrite(int fd, const char *buf, size_t size);

const char*
load(const char* dsopath)
{
  struct sockaddr_un server;
  char *path;
  int fd;

  self = dlopen(dsopath, RTLD_LAZY);
  if (self == NULL)
    return strerror(errno);

  /*
   * connect to uim-helper-server.
   * see uim/uim-helper-client.c.
   */

  path = uim_helper_get_pathname();

  bzero(&server, sizeof(server));
  server.sun_family = PF_UNIX;
  strlcpy(server.sun_path, path, sizeof(server.sun_path));

  free(path);

  fd = socket(PF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    dlclose(self);
    return "error socket()";
  }

  if (connect(fd, (struct sockaddr *)&server, sizeof(server)) != 0) {
    close(fd);
    dlclose(self);
    return "cannot connect to uim-helper-server";
  }

  if (uim_helper_check_connection_fd(fd) != 0) {
    close(fd);
    dlclose(self);
    return "error uim_helper_check_connection_fd()";
  }

  if (pthread_mutex_init(&mutex, NULL) != 0) {
    close(fd);
    dlclose(self);
    return "error pthread_mutex_init()";
  }

  if (pthread_create(&twatch, NULL, uimwatch, (void *)NULL) != 0) {
    close(fd);
    dlclose(self);
    return "error pthread_create()";
  }

  uim_fd = fd;

  return 0;
}

const char*
unload()
{
  if (uim_fd == 0)
    return NULL;
  close(uim_fd);
  pthread_join(twatch, NULL);
  pthread_mutex_destroy(&mutex);
  dlclose(self);
  return NULL;
}

const char*
get_prop()
{
  static char buf[2048];
  if (uim_fd == 0)
    return NULL;
  pthread_mutex_lock(&mutex);
  strlcpy(buf, prop ? prop : "", sizeof(buf));
  pthread_mutex_unlock(&mutex);
  return buf;
}

const char*
send_message(const char* msg)
{
  if (uim_fd == 0)
    return NULL;
  xwrite(uim_fd, msg, strlen(msg));
  xwrite(uim_fd, "\n", 1);
  return NULL;
}

static void *
uimwatch(void *nouse)
{
  char tmp[BUFSIZ];
  char *buf = strdup("");
  char *p;
  struct pollfd pfd;
  ssize_t n;

  pfd.fd = uim_fd;
  pfd.events = (POLLIN | POLLPRI);

  for (;;) {
    RETRY_EINTR(n, poll(&pfd, 1, INFTIM));
    if (n == -1)
      break;
    if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL))
      break;
    RETRY_EINTR(n, read(uim_fd, tmp, sizeof(tmp)));
    if (n == 0 || n == -1)
      break;
    if (tmp[0] == 0)
      continue;
    buf = uim_helper_buffer_append(buf, tmp, n);
    while ((p = uim_helper_buffer_get_message(buf)) != NULL) {
      if (strncmp(p, "prop_list_update", sizeof("prop_list_update") - 1) == 0) {
        pthread_mutex_lock(&mutex);
        if (prop)
          free(prop);
        prop = p;
        pthread_mutex_unlock(&mutex);
      } else {
        free(p);
      }
    }
  }

  return NULL;
}

static ssize_t
xwrite(int fd, const char *buf, size_t size)
{
  ssize_t n;
  size_t s = size;
  while (s > 0) {
    RETRY_EINTR(n, write(uim_fd, buf, size));
    if (n == -1)
      return -1;
    s -= n;
  }
  return size;
}


