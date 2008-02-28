/*
 * Since libuim use static variable (uim_fd), use helper process.
 */
#include <uim/uim.h>
#include <uim/uim-helper.h>
#include <poll.h>
#include <pthread.h>
#include <unistd.h>

#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static int uim_fd;
static char *proplist = NULL;
static pthread_mutex_t mutex;

static char *readonecmd();
static void *uimwatch(void *param);

int
main(int argc, char **argv)
{
  pthread_t twatch;
  char *p;

  uim_fd = uim_helper_init_client_fd(NULL);
  if (uim_fd < 0) {
    fprintf(stderr, "error: uim_helper_init_client_fd()\n");
    return 0;
  }

  pthread_mutex_init(&mutex, NULL);

  if (pthread_create(&twatch, NULL, uimwatch, (void *)NULL) != 0) {
    fprintf(stderr, "error: pthread_create()\n");
    return 0;
  }

  while ((p = readonecmd()) != NULL) {
    if (strcmp(p, "<prop_list_get>\n") == 0) {
      pthread_mutex_lock(&mutex);
      if (proplist == NULL) {
        /* put new line for uim_ipc_send_command() */
        printf("\n");
      } else {
        printf("%s", proplist);
      }
      pthread_mutex_unlock(&mutex);
    } else {
      uim_helper_send_message(uim_fd, p);
    }
    fflush(stdout);
    free(p);
  }

  uim_helper_close_client_fd(uim_fd);
  pthread_join(twatch, NULL);
  pthread_mutex_destroy(&mutex);
  return 0;
}

static char *
readonecmd()
{
  char buf[BUFSIZ];
  char *tmp;

  if (feof(stdin))
    return NULL;

  tmp = strdup("");
  while (fgets(buf, sizeof(buf), stdin) != NULL) {
    if (strcmp(buf, "\n") == 0)
      break;
    tmp = realloc(tmp, strlen(tmp) + strlen(buf) + 1);
    strcat(tmp, buf);
  }
  return tmp;
}

static void *
uimwatch(void *param)
{
  char *tmp;
  struct pollfd pfd;
  int events;

  pfd.fd = uim_fd;
  pfd.events = (POLLIN | POLLPRI);

  for (;;) {
    events = poll(&pfd, 1, INFTIM);
    if (events == -1) {
      if (errno == EINTR)
        continue;
      break;
    } else if (!(pfd.revents & (POLLIN | POLLPRI))) {
      break;
    }
    pthread_mutex_lock(&mutex);
    while (uim_helper_fd_readable(uim_fd)) {
      uim_helper_read_proc(uim_fd);
      while (tmp = uim_helper_get_message()) {
        if (strncmp(tmp, "prop_list_update", sizeof("prop_list_update") - 1) == 0) {
          if (proplist)
            free(proplist);
          proplist = tmp;
        } else {
          free(tmp);
        }
      }
    }
    pthread_mutex_unlock(&mutex);
  }
  return NULL;
}

