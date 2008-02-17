/* 2007-02-01 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <ctype.h>

/* FIFO stream */
typedef struct vp_iobuf_t vp_iobuf_t;
struct vp_iobuf_t {
  char *data;
  char *head;
  char *tail;
  size_t size;
  const char *err;
};

/*
 * End Of Value.  This is used to separate each item.  Use one of
 * control code between 0x01 and 0x1F to prevent encoding problem.
 */
static const char VP_EOV = '\x01';

static vp_iobuf_t *vp_iobuf_new(void);
static void vp_iobuf_delete(vp_iobuf_t *self);
static void vp_iobuf_clear(vp_iobuf_t *self);
static void vp_iobuf_reset(vp_iobuf_t *self, const char *data);
static void vp_iobuf_reserve(vp_iobuf_t *self, size_t size);
static void vp_iobuf_get_str(vp_iobuf_t *self, char **pstr);
static void vp_iobuf_get_bin(vp_iobuf_t *self, char **pbuf, size_t *psize);
static void vp_iobuf_get_fmt(vp_iobuf_t *self, const char *fmt, void *ptr);
#define vp_iobuf_get_num(self, pnum) vp_iobuf_get_fmt(self, "%d", pnum)
#define vp_iobuf_get_ptr(self, pptr) vp_iobuf_get_fmt(self, "%p", pptr)
static void vp_iobuf_put_str(vp_iobuf_t *self, const char *str);
static void vp_iobuf_put_bin(vp_iobuf_t *self, const char *buf, size_t size);
static void vp_iobuf_put_fmt(vp_iobuf_t *self, const char *fmt, ...);
#define vp_iobuf_put_num(self, num) vp_iobuf_put_fmt(self, "%d", num)
#define vp_iobuf_put_ptr(self, ptr) vp_iobuf_put_fmt(self, "%p", ptr)
static void vp_iobuf_get_vars_v(vp_iobuf_t *self, const char *fmt, va_list ap);
static void vp_iobuf_get_vars(vp_iobuf_t *self, const char *fmt, ...);
static void vp_iobuf_put_vars(vp_iobuf_t *self, const char *fmt, ...);
static int vp_iobuf_get_args(vp_iobuf_t *self, const char *args, const char *fmt, ...);
static const char *vp_iobuf_return(vp_iobuf_t *self);

static vp_iobuf_t *
vp_iobuf_new(void)
{
  vp_iobuf_t *self = malloc(sizeof(vp_iobuf_t));
  if (!self)
    return 0;
  self->data = 0;
  vp_iobuf_clear(self);
  return self;
}

static void
vp_iobuf_delete(vp_iobuf_t *self)
{
  if (self) {
    vp_iobuf_clear(self);
    free(self);
  }
}

static void
vp_iobuf_clear(vp_iobuf_t *self)
{
  if (self->data)
    free(self->data);
  self->data = 0;
  self->head = 0;
  self->tail = 0;
  self->size = 0;
  self->err = 0;
}

static void
vp_iobuf_reset(vp_iobuf_t *self, const char *data)
{
  self->err = 0;
  if (!data)
    data = "";
  vp_iobuf_reserve(self, strlen(data));
  if (self->err)
    return;
  strcpy(self->data, data);
  self->head = self->data;
  self->tail = self->data + strlen(data);
}

static void
vp_iobuf_reserve(vp_iobuf_t *self, size_t needsize)
{
  char *newbuf;

  if (self->err)
    return;
  if (!self->data)
    self->size = 512;
  while (self->size < needsize + sizeof(""))
    self->size *= 2;
  newbuf = (char *)realloc(self->data, self->size);
  if (!newbuf) {
    vp_iobuf_clear(self);
    self->err = "vp_iobuf_reserve: realloc error";
    return;
  }
  self->head = newbuf + (self->head - self->data);
  self->tail = newbuf + (self->tail - self->data);
  self->data = newbuf;
}

static void
vp_iobuf_get_str(vp_iobuf_t *self, char **pstr)
{
  char *endp;

  if (self->err)
    return;
  if (self->head == self->tail) {
    self->err = "vp_iobuf_get_str: no data";
    return;
  }
  endp = strchr(self->head, VP_EOV);
  if (!endp) {
    self->err = "vp_iobuf_get_str: EOV error";
    return;
  }
  *endp = 0;
  *pstr = self->head;
  self->head = endp + 1;
}

static void
vp_iobuf_get_bin(vp_iobuf_t *self, char **pbuf, size_t *psize)
{
  char tmp[3] = {0,};
  char *p;
  size_t size = 0;

  if (self->err)
    return;
  vp_iobuf_get_str(self, pbuf);
  if (self->err)
    return;
  for (p = *pbuf; *p; p += 2) {
    if (!isxdigit(p[0]) || !isxdigit(p[1])) {
      self->err = "vp_iobuf_get_bin: format error";
      return;
    }
    tmp[0] = p[0];
    tmp[1] = p[1];
    (*pbuf)[size++] = strtol(tmp, 0, 16);
  }
  (*pbuf)[size] = 0;
  if (psize)
    *psize = size;
}

static void
vp_iobuf_get_fmt(vp_iobuf_t *self, const char *fmt, void *ptr)
{
  char tmp[8];
  int end;
  char *str;

  if (self->err)
    return;
  vp_iobuf_get_str(self, &str);
  if (self->err)
    return;
  strcpy(tmp, fmt);
  strcat(tmp, "%n");
  if (sscanf(str, tmp, ptr, &end) != 1 || str[end] != 0)
    self->err = "vp_iobuf_get_fmt: sscanf error";
}

static void
vp_iobuf_put_str(vp_iobuf_t *self, const char *str)
{
  size_t len;

  if (self->err)
    return;
  len = strlen(str);
  vp_iobuf_reserve(self, (self->tail - self->data) + len + sizeof(VP_EOV));
  if (self->err)
    return;
  strcat(self->tail, str);
  self->tail += len;
  *self->tail++ = VP_EOV;
  *self->tail = 0;
}

static void
vp_iobuf_put_bin(vp_iobuf_t *self, const char *buf, size_t size)
{
  const char hex[] = "0123456789ABCDEF";
  size_t i;

  if (self->err)
    return;
  vp_iobuf_reserve(self, (self->tail - self->data) + (size * 2) + sizeof(VP_EOV));
  if (self->err)
    return;
  for (i = 0; i < size; ++i) {
    *self->tail++ = hex[(buf[i] >> 4) & 0xF];
    *self->tail++ = hex[buf[i] & 0xF];
  }
  *self->tail++ = VP_EOV;
  *self->tail = 0;
}

static void
vp_iobuf_put_fmt(vp_iobuf_t *self, const char *fmt, ...)
{
  char tmp[64];
  va_list ap;

  if (self->err)
    return;
  va_start(ap, fmt);
  if (vsprintf(tmp, fmt, ap) < 0)
    self->err = "vp_iobuf_put_fmt: vsprintf error";
  else
    vp_iobuf_put_str(self, tmp);
  va_end(ap);
}

static void
vp_iobuf_get_vars_v(vp_iobuf_t *self, const char *fmt, va_list ap)
{
  char **pstr;
  char **pbuf;
  size_t *psize;
  int *pnum;
  void **pptr;
  void *ptr, *ptr2;
  const char *p;

  for (p = fmt; *p && !self->err; ++p) {
    switch (*p) {
    case 's':
      pstr = va_arg(ap, char **);
      vp_iobuf_get_str(self, pstr);
      break;
    case 'b':
      pbuf = va_arg(ap, char **);
      psize = va_arg(ap, size_t *);
      vp_iobuf_get_bin(self, pbuf, psize);
      break;
    case 'd':
      pnum = va_arg(ap, int *);
      vp_iobuf_get_num(self, pnum);
      break;
    case 'p':
      pptr = va_arg(ap, void **);
      vp_iobuf_get_ptr(self, pptr);
      break;
    default:
      self->err = "vp_iobuf_get_vars: unknown format";
      break;
    }
  }
}

static void
vp_iobuf_get_vars(vp_iobuf_t *self, const char *fmt, ...)
{
  va_list ap;

  va_start(ap, fmt);
  vp_iobuf_get_vars_v(self, fmt, ap);
  va_end(ap);
}

static void
vp_iobuf_put_vars(vp_iobuf_t *self, const char *fmt, ...)
{
  const char *str;
  const char *buf;
  size_t size;
  int num;
  void *ptr;
  const char *p;
  va_list ap;

  va_start(ap, fmt);
  for (p = fmt; *p && !self->err; ++p) {
    switch (*p) {
    case 's':
      str = va_arg(ap, const char *);
      vp_iobuf_put_str(self, str);
      break;
    case 'b':
      buf = va_arg(ap, const char *);
      size = va_arg(ap, size_t);
      vp_iobuf_put_bin(self, buf, size);
      break;
    case 'd':
      num = va_arg(ap, int);
      vp_iobuf_put_num(self, num);
      break;
    case 'p':
      ptr = va_arg(ap, void *);
      vp_iobuf_put_ptr(self, ptr);
      break;
    default:
      self->err = "vp_iobuf_put_vars: unknown format";
      break;
    }
  }
  va_end(ap);
}

static int
vp_iobuf_get_args(vp_iobuf_t *self, const char *args, const char *fmt, ...)
{
  va_list ap;

  vp_iobuf_reset(self, args);
  va_start(ap, fmt);
  vp_iobuf_get_vars_v(self, fmt, ap);
  va_end(ap);
  if (!self->err && (self->head != self->tail))
    self->err = "vp_iobuf_get_args: too many arguments";
  return !self->err;
}

static const char *
vp_iobuf_return(vp_iobuf_t *self)
{
  if (self->err)
    return self->err;
  return self->head;
}

