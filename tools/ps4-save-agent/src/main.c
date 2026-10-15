/*
  PS4 Save Agent - HTTP payload for save tests.

  Endpoints:
    GET  /api/ping
    GET  /api/version
    GET  /api/log
    GET  /api/shutdown
    POST /api/sync_decrypted?source_user=...&dest_user=...&title=...&save=...
*/

#include <arpa/inet.h>
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <ps4/kernel.h>
#include <stdarg.h>
#include <stdint.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include "sqlite3.h"

#ifndef SAVE_AGENT_PORT
#define SAVE_AGENT_PORT 8084
#endif

#define SAVE_AGENT_VERSION "PS4SAVEAGENT 0.6"
#define SAVE_AGENT_LOG "/data/ps4-save-agent.log"
#define WORK_ROOT "/data/ps4-save-agent"
#define BUF_SIZE (512 * 1024)
#define MAX_PATH_LEN 1024
#define ENC_SEALEDKEY_LEN 0x60
#define DEC_SEALEDKEY_LEN 0x20

extern int sceNetInit(void);
extern int sceKernelGetOpenPsIdForSystem(void *psid);
extern int sceRegMgrGetBin(int key, void *buf, size_t size);
extern int sceRegMgrGetStr(int key, char *buf, size_t size);
extern int sceFsInitCreatePfsSaveDataOpt(void *opt);
extern int sceFsCreatePfsSaveDataImage(void *opt, const char *path, int x,
  uint64_t size, uint8_t *key);
extern int sceFsUfsAllocateSaveData(int fd, uint64_t size, uint64_t flags,
  int ext);
extern int sceFsInitMountSaveDataOpt(void *opt);
extern int sceFsMountSaveData(void *opt, const char *path, const char *mount,
  uint8_t *key);
extern int sceFsInitUmountSaveDataOpt(void *opt);
extern int sceFsUmountSaveData(void *opt, const char *mount, int handle,
  int ignore);

typedef struct {
  int blockSize;
  uint8_t flags[2];
} CreateOpt;

typedef struct {
  uint8_t readOnly;
  uint8_t pad[7];
  char *budgetid;
} MountOpt;

typedef struct {
  uint8_t dummy;
} UmountOpt;

static volatile int g_stop = 0;
static int g_vsh_mount_ready = 0;
static FILE *g_log_fp = NULL;

/*
 * The system may terminate userland processes while powering off.  Keep the
 * agent shutdown-safe even when it receives a normal termination signal, and
 * do not perform any work from the signal handler itself.
 */
static void request_stop(int signal_number)
{
  (void)signal_number;
  g_stop = 1;
}

static void logf(const char *fmt, ...)
{
  va_list ap;

  if (g_log_fp == NULL)
    return;

  va_start(ap, fmt);
  vfprintf(g_log_fp, fmt, ap);
  va_end(ap);
  fprintf(g_log_fp, "\n");
  fflush(g_log_fp);
}

static void send_all(int fd, const void *data, size_t size)
{
  const char *p = (const char *)data;

  while (size > 0)
  {
    ssize_t sent = write(fd, p, size);
    if (sent <= 0)
      return;
    p += sent;
    size -= (size_t)sent;
  }
}

static void send_response(int fd, int status, const char *reason,
  const char *content_type, const char *body)
{
  char header[256];
  int header_len;
  size_t body_len;

  if (body == NULL)
    body = "";

  body_len = strlen(body);
  header_len = snprintf(header, sizeof(header),
    "HTTP/1.1 %d %s\r\n"
    "Content-Type: %s\r\n"
    "Content-Length: %u\r\n"
    "Connection: close\r\n"
    "\r\n",
    status, reason, content_type, (unsigned int)body_len);

  if (header_len > 0)
    send_all(fd, header, (size_t)header_len);
  send_all(fd, body, body_len);
}

static void send_file_response(int fd, const char *path, const char *content_type)
{
  char header[256];
  char *buf;
  int file_fd;
  int header_len;
  struct stat st;
  ssize_t n;

  file_fd = open(path, O_RDONLY);
  if (file_fd < 0 || stat(path, &st) != 0)
  {
    if (file_fd >= 0)
      close(file_fd);
    send_response(fd, 404, "Not Found", "text/plain", "file not found\n");
    return;
  }

  header_len = snprintf(header, sizeof(header),
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: %s\r\n"
    "Content-Length: %llu\r\n"
    "Connection: close\r\n"
    "\r\n",
    content_type, (unsigned long long)st.st_size);
  if (header_len > 0)
    send_all(fd, header, (size_t)header_len);

  buf = malloc(BUF_SIZE);
  if (!buf)
  {
    close(file_fd);
    return;
  }

  while ((n = read(file_fd, buf, BUF_SIZE)) > 0)
    send_all(fd, buf, (size_t)n);

  free(buf);
  close(file_fd);
}

static int file_exists(const char *path)
{
  struct stat st;
  return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int path_size(const char *path, uint64_t *size)
{
  struct stat st;
  if (stat(path, &st) != 0)
    return -1;
  *size = (uint64_t)st.st_size;
  return 0;
}

static int mkdirs(const char *path)
{
  char tmp[MAX_PATH_LEN];
  char *p;

  snprintf(tmp, sizeof(tmp), "%s", path);
  for (p = tmp + 1; *p; p++)
  {
    if (*p == '/')
    {
      *p = 0;
      mkdir(tmp, 0777);
      *p = '/';
    }
  }
  return mkdir(tmp, 0777);
}

static void delete_recursive(const char *path)
{
  DIR *d;
  struct dirent *ent;

  d = opendir(path);
  if (!d)
    return;

  while ((ent = readdir(d)) != NULL)
  {
    char fp[MAX_PATH_LEN];
    struct stat st;

    if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0)
      continue;

    snprintf(fp, sizeof(fp), "%s/%s", path, ent->d_name);
    if (stat(fp, &st) != 0)
      continue;

    if (S_ISDIR(st.st_mode))
    {
      delete_recursive(fp);
      rmdir(fp);
    }
    else
      unlink(fp);
  }

  closedir(d);
}

static int copy_file(const char *src, const char *dst)
{
  int sfd;
  int dfd;
  char *buf;
  ssize_t n;

  sfd = open(src, O_RDONLY);
  if (sfd < 0)
    return -1;

  dfd = open(dst, O_CREAT | O_WRONLY | O_TRUNC, 0644);
  if (dfd < 0)
  {
    close(sfd);
    return -2;
  }

  buf = malloc(BUF_SIZE);
  if (!buf)
  {
    close(sfd);
    close(dfd);
    return -3;
  }

  while ((n = read(sfd, buf, BUF_SIZE)) > 0)
  {
    ssize_t off = 0;
    while (off < n)
    {
      ssize_t w = write(dfd, buf + off, (size_t)(n - off));
      if (w <= 0)
      {
        free(buf);
        close(sfd);
        close(dfd);
        return -4;
      }
      off += w;
    }
  }

  fsync(dfd);
  free(buf);
  close(sfd);
  close(dfd);
  return n < 0 ? -5 : 0;
}

static int copy_dir_recursive(const char *src, const char *dst)
{
  DIR *d;
  struct dirent *ent;

  mkdirs(dst);
  d = opendir(src);
  if (!d)
    return -1;

  while ((ent = readdir(d)) != NULL)
  {
    char sp[MAX_PATH_LEN];
    char dp[MAX_PATH_LEN];
    struct stat st;

    if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0)
      continue;

    snprintf(sp, sizeof(sp), "%s/%s", src, ent->d_name);
    snprintf(dp, sizeof(dp), "%s/%s", dst, ent->d_name);
    if (stat(sp, &st) != 0)
      continue;

    if (S_ISDIR(st.st_mode))
    {
      if (copy_dir_recursive(sp, dp) != 0)
      {
        closedir(d);
        return -2;
      }
    }
    else if (copy_file(sp, dp) != 0)
    {
      closedir(d);
      return -3;
    }
  }

  closedir(d);
  return 0;
}

static int copy_dir_recursive_skip_sce_sys(const char *src, const char *dst)
{
  DIR *d;
  struct dirent *ent;

  mkdirs(dst);
  d = opendir(src);
  if (!d)
    return -1;

  while ((ent = readdir(d)) != NULL)
  {
    char sp[MAX_PATH_LEN];
    char dp[MAX_PATH_LEN];
    struct stat st;

    if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0)
      continue;
    if (strcmp(ent->d_name, "sce_sys") == 0)
      continue;

    snprintf(sp, sizeof(sp), "%s/%s", src, ent->d_name);
    snprintf(dp, sizeof(dp), "%s/%s", dst, ent->d_name);
    if (stat(sp, &st) != 0)
      continue;

    if (S_ISDIR(st.st_mode))
    {
      delete_recursive(dp);
      rmdir(dp);
      if (copy_dir_recursive_skip_sce_sys(sp, dp) != 0)
      {
        closedir(d);
        return -2;
      }
    }
    else
    {
      unlink(dp);
      if (copy_file(sp, dp) != 0)
      {
        closedir(d);
        return -3;
      }
    }
  }

  closedir(d);
  return 0;
}

static int write_archive_file(FILE *out, const char *full_path, const char *rel_path)
{
  int fd;
  char *buf;
  struct stat st;
  ssize_t n;

  if (stat(full_path, &st) != 0 || !S_ISREG(st.st_mode))
    return 0;

  fprintf(out, "F\t%llu\t%s\n", (unsigned long long)st.st_size, rel_path);
  fd = open(full_path, O_RDONLY);
  if (fd < 0)
    return -1;

  buf = malloc(BUF_SIZE);
  if (!buf)
  {
    close(fd);
    return -2;
  }

  while ((n = read(fd, buf, BUF_SIZE)) > 0)
    if (fwrite(buf, 1, (size_t)n, out) != (size_t)n)
    {
      free(buf);
      close(fd);
      return -3;
    }

  free(buf);
  close(fd);
  fputc('\n', out);
  return n < 0 ? -4 : 0;
}

static int pack_dir_recursive(FILE *out, const char *root, const char *rel)
{
  DIR *d;
  struct dirent *ent;
  char dir_path[MAX_PATH_LEN];

  if (rel[0])
    snprintf(dir_path, sizeof(dir_path), "%s/%s", root, rel);
  else
    snprintf(dir_path, sizeof(dir_path), "%s", root);

  d = opendir(dir_path);
  if (!d)
    return -1;

  while ((ent = readdir(d)) != NULL)
  {
    char child_rel[MAX_PATH_LEN];
    char child_full[MAX_PATH_LEN];
    struct stat st;

    if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0)
      continue;

    if (rel[0])
      snprintf(child_rel, sizeof(child_rel), "%s/%s", rel, ent->d_name);
    else
      snprintf(child_rel, sizeof(child_rel), "%s", ent->d_name);
    snprintf(child_full, sizeof(child_full), "%s/%s", root, child_rel);

    if (stat(child_full, &st) != 0)
      continue;

    if (S_ISDIR(st.st_mode))
    {
      fprintf(out, "D\t%s\n", child_rel);
      if (pack_dir_recursive(out, root, child_rel) != 0)
      {
        closedir(d);
        return -2;
      }
    }
    else if (S_ISREG(st.st_mode))
    {
      if (write_archive_file(out, child_full, child_rel) != 0)
      {
        closedir(d);
        return -3;
      }
    }
  }

  closedir(d);
  return 0;
}

static int is_safe_relative_path(const char *path)
{
  if (!path || !path[0] || path[0] == '/' || strstr(path, "..") != NULL)
    return 0;
  return 1;
}

static int ensure_parent_dir(const char *path)
{
  char tmp[MAX_PATH_LEN];
  char *p;

  snprintf(tmp, sizeof(tmp), "%s", path);
  p = strrchr(tmp, '/');
  if (p == NULL)
    return 0;
  *p = 0;
  return mkdirs(tmp);
}

static int unpack_archive(const char *archive_path, const char *dst, int skip_sce_sys)
{
  FILE *in;
  char line[MAX_PATH_LEN + 64];
  char rel[MAX_PATH_LEN];

  in = fopen(archive_path, "rb");
  if (!in)
    return -1;

  if (fgets(line, sizeof(line), in) == NULL ||
      strcmp(line, "PS4SAVEPACK1\n") != 0)
  {
    fclose(in);
    return -2;
  }

  while (fgets(line, sizeof(line), in) != NULL)
  {
    unsigned long long size;
    char out_path[MAX_PATH_LEN];

    if (strcmp(line, "END\n") == 0)
      break;

    memset(rel, 0, sizeof(rel));
    if (line[0] == 'D' && line[1] == '\t')
    {
      snprintf(rel, sizeof(rel), "%s", line + 2);
      rel[strcspn(rel, "\r\n")] = 0;
      if (!is_safe_relative_path(rel))
      {
        fclose(in);
        return -3;
      }
      if (skip_sce_sys && strncmp(rel, "sce_sys", 7) == 0)
        continue;
      snprintf(out_path, sizeof(out_path), "%s/%s", dst, rel);
      mkdirs(out_path);
      continue;
    }

    if (sscanf(line, "F\t%llu\t%1023[^\n]", &size, rel) == 2)
    {
      FILE *out;
      char *buf;
      unsigned long long left;

      rel[strcspn(rel, "\r\n")] = 0;
      if (!is_safe_relative_path(rel))
      {
        fclose(in);
        return -4;
      }

      if (skip_sce_sys && strncmp(rel, "sce_sys/", 8) == 0)
      {
        char skip_buf[8192];
        left = size;
        while (left > 0)
        {
          size_t want = left > sizeof(skip_buf) ? sizeof(skip_buf) : (size_t)left;
          if (fread(skip_buf, 1, want, in) != want)
          {
            fclose(in);
            return -5;
          }
          left -= want;
        }
        fgetc(in);
        continue;
      }

      snprintf(out_path, sizeof(out_path), "%s/%s", dst, rel);
      ensure_parent_dir(out_path);
      out = fopen(out_path, "wb");
      if (!out)
      {
        fclose(in);
        return -6;
      }

      buf = malloc(BUF_SIZE);
      if (!buf)
      {
        fclose(out);
        fclose(in);
        return -7;
      }

      left = size;
      while (left > 0)
      {
        size_t want = left > BUF_SIZE ? BUF_SIZE : (size_t)left;
        if (fread(buf, 1, want, in) != want ||
            fwrite(buf, 1, want, out) != want)
        {
          free(buf);
          fclose(out);
          fclose(in);
          return -8;
        }
        left -= want;
      }

      free(buf);
      fflush(out);
      fclose(out);
      fgetc(in);
      continue;
    }

    fclose(in);
    return -9;
  }

  fclose(in);
  return 0;
}

static void elevate(void)
{
  uint8_t caps[16];
  intptr_t ucred;
  uint64_t sony_cred;
  intptr_t prison0;
  intptr_t rootvnode;

  kernel_set_ucred_uid(getpid(), 0);
  kernel_set_ucred_authid(getpid(), 0x4800000000000010ULL);
  if (kernel_get_ucred_caps(getpid(), caps) == 0)
  {
    caps[7] |= 0x40;
    kernel_set_ucred_caps(getpid(), caps);
  }

  ucred = kernel_get_proc_ucred(getpid());
  if (ucred != 0)
  {
    sony_cred = kernel_getlong(ucred + 96);
    sony_cred |= 0x4000000000000000ULL;
    kernel_setlong(ucred + 88, 0x3801000000000013ULL);
    kernel_setlong(ucred + 96, sony_cred);
    kernel_setlong(ucred + 104, 0xffffffffffffffffULL);
  }

  prison0 = kernel_get_ucred_prison(1);
  rootvnode = kernel_get_proc_rootdir(1);
  if (prison0 != 0)
    kernel_set_ucred_prison(getpid(), prison0);
  if (rootvnode != 0)
  {
    kernel_set_proc_rootdir(getpid(), rootvnode);
    kernel_set_proc_jaildir(getpid(), rootvnode);
    kernel_set_proc_currdir(getpid(), rootvnode);
  }

  setuid(0);
}

static int create_device_alias(const char *path)
{
  struct stat st;

  memset(&st, 0, sizeof(st));
  if (stat(path, &st) != 0)
  {
    logf("device stat failed %s errno=%d", path, errno);
    return -1;
  }

  if (syscall(SYS_mknod, path, S_IFCHR | 0777, st.st_dev) < 0)
  {
    logf("device mknod failed %s errno=%d", path, errno);
    return -2;
  }

  return 0;
}

static int init_vsh_mount(void)
{
  if (g_vsh_mount_ready)
    return 0;

  elevate();
  create_device_alias("/dev/pfsctldev");
  create_device_alias("/dev/lvdctl");
  create_device_alias("/dev/sbl_srv");
  g_vsh_mount_ready = 1;
  logf("vsh mount environment initialized");
  return 0;
}

static int decrypt_sealed_key(const char *key_path, uint8_t dec_key[DEC_SEALEDKEY_LEN])
{
  uint8_t *data;
  int fd;
  int ret;

  data = malloc(0x100);
  if (!data)
    return -10;
  memset(data, 0, 0x100);

  fd = open(key_path, O_RDONLY);
  if (fd < 0)
  {
    free(data);
    return -1;
  }

  ret = (int)read(fd, data, ENC_SEALEDKEY_LEN);
  close(fd);
  if (ret != ENC_SEALEDKEY_LEN)
  {
    free(data);
    return -2;
  }

  fd = open("/dev/sbl_srv", O_RDWR);
  if (fd >= 0)
  {
    ret = ioctl(fd, 0xc0845302, data);
    close(fd);
    if (ret >= 0)
    {
      memcpy(dec_key, data + ENC_SEALEDKEY_LEN, DEC_SEALEDKEY_LEN);
      free(data);
      return 0;
    }
  }

  fd = open("/dev/pfsmgr", O_RDWR);
  if (fd >= 0)
  {
    ret = ioctl(fd, 0xc0845302, data);
    close(fd);
    if (ret >= 0)
    {
      memcpy(dec_key, data + ENC_SEALEDKEY_LEN, DEC_SEALEDKEY_LEN);
      free(data);
      return 0;
    }
  }

  free(data);
  return -3;
}

static int generate_sealed_key(const char *key_path, uint8_t dec_key[DEC_SEALEDKEY_LEN])
{
  uint8_t sealed[ENC_SEALEDKEY_LEN];
  uint8_t *data;
  int fd;
  int ret;

  memset(sealed, 0, sizeof(sealed));
  fd = open("/dev/sbl_srv", O_RDWR);
  if (fd < 0)
    return -1;

  ret = ioctl(fd, 0x40845303, sealed);
  close(fd);
  if (ret < 0)
    return -2;

  fd = open(key_path, O_CREAT | O_WRONLY | O_TRUNC, 0644);
  if (fd < 0)
    return -3;
  write(fd, sealed, sizeof(sealed));
  fsync(fd);
  close(fd);

  data = malloc(0x100);
  if (!data)
    return -4;
  memset(data, 0, 0x100);
  memcpy(data, sealed, sizeof(sealed));

  fd = open("/dev/pfsmgr", O_RDWR);
  if (fd < 0)
    fd = open("/dev/sbl_srv", O_RDWR);
  if (fd < 0)
  {
    free(data);
    return -5;
  }

  ret = ioctl(fd, 0xc0845302, data);
  close(fd);
  if (ret < 0)
  {
    free(data);
    return -6;
  }

  memcpy(dec_key, data + ENC_SEALEDKEY_LEN, DEC_SEALEDKEY_LEN);
  free(data);
  return 0;
}

static int create_pfs_image(const char *img_path, const char *key_path,
  uint64_t wanted_size)
{
  CreateOpt copt;
  uint8_t dec_key[DEC_SEALEDKEY_LEN];
  uint64_t img_size;
  int fd;
  int ret;

  img_size = wanted_size + (4 * 1024 * 1024);
  if (img_size < (32 * 1024 * 1024))
    img_size = 32 * 1024 * 1024;
  img_size = ((img_size + 32767) / 32768) * 32768;

  ret = generate_sealed_key(key_path, dec_key);
  if (ret < 0)
    return -100 + ret;

  fd = open(img_path, O_CREAT | O_TRUNC | O_RDWR, 0644);
  if (fd < 0)
    return -1;

  ret = sceFsUfsAllocateSaveData(fd, img_size, 0, 0);
  if (ret < 0)
  {
    if (ftruncate(fd, (off_t)img_size) != 0)
    {
      close(fd);
      return -2;
    }
  }
  close(fd);

  memset(&copt, 0, sizeof(copt));
  ret = sceFsInitCreatePfsSaveDataOpt(&copt);
  if (ret < 0)
    return -3;

  ret = sceFsCreatePfsSaveDataImage(&copt, img_path, 0, img_size, dec_key);
  if (ret < 0)
    return ret;

  return 0;
}

static int mount_save(const char *img_path, const char *key_path,
  const char *mount_path, int read_only)
{
  uint8_t dec_key[DEC_SEALEDKEY_LEN];
  MountOpt mopt;
  int ret;

  ret = decrypt_sealed_key(key_path, dec_key);
  if (ret < 0)
    return -100 + ret;

  mkdirs(mount_path);
  memset(&mopt, 0, sizeof(mopt));
  sceFsInitMountSaveDataOpt(&mopt);
  mopt.readOnly = (uint8_t)(read_only ? 1 : 0);
  mopt.budgetid = "system";

  ret = sceFsMountSaveData(&mopt, img_path, mount_path, dec_key);
  return ret;
}

static int unmount_save(const char *mount_path)
{
  UmountOpt uopt;
  memset(&uopt, 0, sizeof(uopt));
  sceFsInitUmountSaveDataOpt(&uopt);
  return sceFsUmountSaveData(&uopt, mount_path, 0, 0);
}

typedef struct {
  uint32_t state[8];
  uint64_t bitlen;
  uint8_t data[64];
  uint32_t datalen;
} Sha256Ctx;

static uint32_t rotr32(uint32_t x, uint32_t n)
{
  return (x >> n) | (x << (32 - n));
}

static void sha256_transform(Sha256Ctx *ctx, const uint8_t data[64])
{
  static const uint32_t k[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
  };
  uint32_t a,b,c,d,e,f,g,h,i,j,t1,t2,m[64];

  for (i = 0, j = 0; i < 16; i++, j += 4)
    m[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j+1] << 16) |
      ((uint32_t)data[j+2] << 8) | data[j+3];
  for (; i < 64; i++)
  {
    uint32_t s0 = rotr32(m[i-15], 7) ^ rotr32(m[i-15], 18) ^ (m[i-15] >> 3);
    uint32_t s1 = rotr32(m[i-2], 17) ^ rotr32(m[i-2], 19) ^ (m[i-2] >> 10);
    m[i] = m[i-16] + s0 + m[i-7] + s1;
  }

  a = ctx->state[0]; b = ctx->state[1]; c = ctx->state[2]; d = ctx->state[3];
  e = ctx->state[4]; f = ctx->state[5]; g = ctx->state[6]; h = ctx->state[7];
  for (i = 0; i < 64; i++)
  {
    uint32_t s1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
    uint32_t ch = (e & f) ^ (~e & g);
    uint32_t s0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
    uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
    t1 = h + s1 + ch + k[i] + m[i];
    t2 = s0 + maj;
    h = g; g = f; f = e; e = d + t1;
    d = c; c = b; b = a; a = t1 + t2;
  }
  ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
  ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

static void sha256_init(Sha256Ctx *ctx)
{
  ctx->datalen = 0;
  ctx->bitlen = 0;
  ctx->state[0] = 0x6a09e667; ctx->state[1] = 0xbb67ae85;
  ctx->state[2] = 0x3c6ef372; ctx->state[3] = 0xa54ff53a;
  ctx->state[4] = 0x510e527f; ctx->state[5] = 0x9b05688c;
  ctx->state[6] = 0x1f83d9ab; ctx->state[7] = 0x5be0cd19;
}

static void sha256_update(Sha256Ctx *ctx, const uint8_t *data, size_t len)
{
  for (size_t i = 0; i < len; i++)
  {
    ctx->data[ctx->datalen++] = data[i];
    if (ctx->datalen == 64)
    {
      sha256_transform(ctx, ctx->data);
      ctx->bitlen += 512;
      ctx->datalen = 0;
    }
  }
}

static void sha256_final(Sha256Ctx *ctx, uint8_t hash[32])
{
  uint32_t i = ctx->datalen;

  ctx->data[i++] = 0x80;
  if (i > 56)
  {
    while (i < 64) ctx->data[i++] = 0;
    sha256_transform(ctx, ctx->data);
    i = 0;
  }
  while (i < 56) ctx->data[i++] = 0;

  ctx->bitlen += ctx->datalen * 8;
  for (i = 0; i < 8; i++)
    ctx->data[63 - i] = (uint8_t)(ctx->bitlen >> (8 * i));
  sha256_transform(ctx, ctx->data);

  for (i = 0; i < 4; i++)
    for (uint32_t j = 0; j < 8; j++)
      hash[i + j * 4] = (uint8_t)(ctx->state[j] >> (24 - i * 8));
}

static void hmac_sha256(const uint8_t *key, size_t key_len,
  const uint8_t *data, size_t data_len, uint8_t out[32])
{
  uint8_t ipad[64], opad[64], tk[32];
  Sha256Ctx ctx;

  if (key_len > 64)
  {
    sha256_init(&ctx);
    sha256_update(&ctx, key, key_len);
    sha256_final(&ctx, tk);
    key = tk;
    key_len = 32;
  }

  memset(ipad, 0x36, sizeof(ipad));
  memset(opad, 0x5c, sizeof(opad));
  for (size_t i = 0; i < key_len; i++)
  {
    ipad[i] ^= key[i];
    opad[i] ^= key[i];
  }

  sha256_init(&ctx);
  sha256_update(&ctx, ipad, sizeof(ipad));
  sha256_update(&ctx, data, data_len);
  sha256_final(&ctx, tk);

  sha256_init(&ctx);
  sha256_update(&ctx, opad, sizeof(opad));
  sha256_update(&ctx, tk, sizeof(tk));
  sha256_final(&ctx, out);
}

static int get_account_id_for_user(const char *uid_hex, uint64_t *aid)
{
  char username_path[MAX_PATH_LEN];
  char username[32];
  int fd;

  *aid = 0;
  memset(username, 0, sizeof(username));
  snprintf(username_path, sizeof(username_path), "/user/home/%s/username.dat", uid_hex);
  fd = open(username_path, O_RDONLY);
  if (fd < 0)
    return -1;
  read(fd, username, sizeof(username) - 1);
  close(fd);
  if (!username[0])
    return -2;

  for (int i = 1; i <= 16; i++)
  {
    int key_name = (i - 1) * 65536 + 125829632;
    int key_aid = (i - 1) * 65536 + 125830400;
    char reg_name[32];
    uint64_t reg_aid = 0;

    memset(reg_name, 0, sizeof(reg_name));
    if (sceRegMgrGetStr(key_name, reg_name, sizeof(reg_name)) < 0)
      continue;
    logf("registry user slot %d name '%s' comparing with '%s'", i, reg_name, username);
    if (strcmp(username, reg_name) != 0)
      continue;
    if (sceRegMgrGetBin(key_aid, &reg_aid, sizeof(reg_aid)) < 0)
      return -3;
    if (reg_aid == 0)
      return -5;
    *aid = reg_aid;
    return 0;
  }

  return -4;
}

static uint16_t rd16(const uint8_t *p)
{
  return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t rd32(const uint8_t *p)
{
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
    ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void wr32(uint8_t *p, uint32_t v)
{
  p[0] = (uint8_t)v;
  p[1] = (uint8_t)(v >> 8);
  p[2] = (uint8_t)(v >> 16);
  p[3] = (uint8_t)(v >> 24);
}

static void wr64(uint8_t *p, uint64_t v)
{
  for (int i = 0; i < 8; i++)
    p[i] = (uint8_t)(v >> (8 * i));
}

static int find_sfo_value(uint8_t *buf, size_t len, const char *key,
  size_t *off, uint32_t *used)
{
  uint32_t key_off, data_off, entries;

  if (len < 20 || rd32(buf) != 0x46535000)
    return -1;

  key_off = rd32(buf + 8);
  data_off = rd32(buf + 12);
  entries = rd32(buf + 16);
  if (key_off >= len || data_off >= len || 20 + entries * 16 > len)
    return -2;

  for (uint32_t i = 0; i < entries; i++)
  {
    uint8_t *e = buf + 20 + i * 16;
    uint32_t name = key_off + rd16(e);
    uint32_t size = rd32(e + 4);
    uint32_t max_size = rd32(e + 8);
    uint32_t value = data_off + rd32(e + 12);
    if (name >= len || value >= len || value + size > len)
      continue;
    if (max_size < size)
      continue;
    if (strcmp((char *)(buf + name), key) == 0)
    {
      *off = value;
      *used = size;
      return 0;
    }
  }

  return -3;
}

static int patch_ps4_param_sfo(const char *mount_path, const char *dest_user)
{
  char sfo_path[MAX_PATH_LEN];
  uint64_t aid;
  uint32_t user_id;
  int fd;
  struct stat st;
  uint8_t *buf;
  size_t account_off = 0;
  size_t params_off = 0;
  uint32_t account_used = 0;
  uint32_t params_used = 0;
  uint8_t psid[16];
  static const uint8_t psid_hmac_key[16] = {
    0x13, 0xD1, 0xDF, 0x06, 0x75, 0xC9, 0xFD, 0x95,
    0x0A, 0x17, 0xE5, 0x64, 0xC2, 0x77, 0x7F, 0x2C
  };

  if (get_account_id_for_user(dest_user, &aid) != 0)
  {
    logf("could not get account id for %s", dest_user);
    return -1;
  }

  snprintf(sfo_path, sizeof(sfo_path), "%s/sce_sys/param.sfo", mount_path);
  fd = open(sfo_path, O_RDWR);
  if (fd < 0)
  {
    logf("param.sfo not found at %s", sfo_path);
    return -2;
  }
  if (fstat(fd, &st) != 0 || st.st_size <= 0 || st.st_size > (1024 * 1024))
  {
    close(fd);
    logf("param.sfo invalid size at %s", sfo_path);
    return -3;
  }

  buf = malloc((size_t)st.st_size);
  if (buf == NULL)
  {
    close(fd);
    return -4;
  }
  if (pread(fd, buf, (size_t)st.st_size, 0) != st.st_size)
  {
    free(buf);
    close(fd);
    return -5;
  }

  user_id = (uint32_t)strtoul(dest_user, NULL, 16);
  if (find_sfo_value(buf, (size_t)st.st_size, "ACCOUNT_ID",
      &account_off, &account_used) == 0 && account_used == 8)
    wr64(buf + account_off, aid);
  else
    logf("param.sfo ACCOUNT_ID not found/invalid");

  if (find_sfo_value(buf, (size_t)st.st_size, "PARAMS",
      &params_off, &params_used) == 0 && params_used >= 0x50)
  {
    wr32(buf + params_off + 0x04, user_id);
    if (sceKernelGetOpenPsIdForSystem(psid) == 0)
      hmac_sha256(psid_hmac_key, sizeof(psid_hmac_key), psid, sizeof(psid),
        buf + params_off + 0x08);
    else
      logf("sceKernelGetOpenPsIdForSystem failed");
    memcpy(buf + params_off + 0x3C, buf + params_off + 0x2C, 0x10);
  }
  else
    logf("param.sfo PARAMS not found/invalid");

  pwrite(fd, buf, (size_t)st.st_size, 0);
  fsync(fd);
  close(fd);
  free(buf);
  logf("param.sfo patched aid=%llx user_id=%x for %s",
    (unsigned long long)aid, user_id, dest_user);
  return 0;
}

static int update_savedata_db(const char *source_user, const char *dest_user,
  const char *title, const char *save)
{
  char src_db_path[MAX_PATH_LEN];
  char dst_db_path[MAX_PATH_LEN];
  char dst_db_dir[MAX_PATH_LEN];
  sqlite3 *src_db = NULL;
  sqlite3 *dst_db = NULL;
  sqlite3_stmt *stmt = NULL;
  char *sql = NULL;
  char *err = NULL;
  const char *main_title = "";
  const char *sub_title = "";
  const char *detail = "";
  const char *game_title_id = title;
  int user_param = 0;
  int blocks = 96;
  int free_blocks = 96;
  int size_kib = 96 * 32;
  uint64_t account_id = 0;
  uint32_t user_id;
  int exists = 0;
  int ret;

  snprintf(src_db_path, sizeof(src_db_path),
    "/system_data/savedata/%s/db/user/savedata.db", source_user);
  snprintf(dst_db_path, sizeof(dst_db_path),
    "/system_data/savedata/%s/db/user/savedata.db", dest_user);
  snprintf(dst_db_dir, sizeof(dst_db_dir),
    "/system_data/savedata/%s/db/user", dest_user);
  mkdirs(dst_db_dir);

  if (sqlite3_open_v2(src_db_path, &src_db, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK)
  {
    sql = sqlite3_mprintf(
      "SELECT main_title, sub_title, detail, user_param, blocks, free_blocks, "
      "size_kib, game_title_id FROM savedata "
      "WHERE title_id=%Q AND dir_name=%Q LIMIT 1",
      title, save);
    if (sql != NULL &&
        sqlite3_prepare_v2(src_db, sql, -1, &stmt, NULL) == SQLITE_OK &&
        sqlite3_step(stmt) == SQLITE_ROW)
    {
      main_title = (const char *)sqlite3_column_text(stmt, 0);
      sub_title = (const char *)sqlite3_column_text(stmt, 1);
      detail = (const char *)sqlite3_column_text(stmt, 2);
      user_param = sqlite3_column_int(stmt, 3);
      blocks = sqlite3_column_int(stmt, 4);
      free_blocks = sqlite3_column_int(stmt, 5);
      size_kib = sqlite3_column_int(stmt, 6);
      game_title_id = (const char *)sqlite3_column_text(stmt, 7);
      if (main_title == NULL) main_title = "";
      if (sub_title == NULL) sub_title = "";
      if (detail == NULL) detail = "";
      if (game_title_id == NULL || game_title_id[0] == 0) game_title_id = title;
    }
    if (stmt != NULL)
    {
      sqlite3_finalize(stmt);
      stmt = NULL;
    }
    if (sql != NULL)
    {
      sqlite3_free(sql);
      sql = NULL;
    }
    sqlite3_close(src_db);
  }
  else if (src_db != NULL)
    sqlite3_close(src_db);

  get_account_id_for_user(dest_user, &account_id);
  user_id = (uint32_t)strtoul(dest_user, NULL, 16);

  ret = sqlite3_open(dst_db_path, &dst_db);
  if (ret != SQLITE_OK)
  {
    if (dst_db != NULL)
      sqlite3_close(dst_db);
    return -1;
  }

  sqlite3_exec(dst_db,
    "CREATE TABLE IF NOT EXISTS savedata ("
    "id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,"
    "title_id NOT NULL, dir_name NOT NULL, main_title NOT NULL,"
    "sub_title, detail, tmp_dir_name, is_broken, user_param,"
    "blocks, free_blocks, size_kib, mtime NOT NULL,"
    "fake_broken, account_id, user_id, faked_owner,"
    "cloud_icon_url, cloud_revision, game_title_id NOT NULL)",
    NULL, 0, &err);
  if (err != NULL)
  {
    logf("savedata.db create table warning: %s", err);
    sqlite3_free(err);
    err = NULL;
  }

  sql = sqlite3_mprintf(
    "SELECT COUNT(*) FROM savedata WHERE title_id=%Q AND dir_name=%Q",
    title, save);
  if (sql != NULL &&
      sqlite3_prepare_v2(dst_db, sql, -1, &stmt, NULL) == SQLITE_OK &&
      sqlite3_step(stmt) == SQLITE_ROW)
    exists = sqlite3_column_int(stmt, 0);
  if (stmt != NULL)
  {
    sqlite3_finalize(stmt);
    stmt = NULL;
  }
  if (sql != NULL)
  {
    sqlite3_free(sql);
    sql = NULL;
  }

  if (exists)
    sql = sqlite3_mprintf(
      "UPDATE savedata SET main_title=%Q, sub_title=%Q, detail=%Q, "
      "user_param=%d, blocks=%d, free_blocks=%d, size_kib=%d, "
      "mtime=strftime('%%Y-%%m-%%dT%%H:%%M:%%S.00Z', CURRENT_TIMESTAMP), "
      "account_id=%llu, user_id=%u, game_title_id=%Q "
      "WHERE title_id=%Q AND dir_name=%Q",
      main_title, sub_title, detail, user_param, blocks, free_blocks, size_kib,
      (unsigned long long)account_id, user_id, game_title_id, title, save);
  else
    sql = sqlite3_mprintf(
      "INSERT INTO savedata (title_id, dir_name, main_title, sub_title, detail, "
      "tmp_dir_name, is_broken, user_param, blocks, free_blocks, size_kib, "
      "mtime, fake_broken, account_id, user_id, faked_owner, cloud_icon_url, "
      "cloud_revision, game_title_id) VALUES "
      "(%Q,%Q,%Q,%Q,%Q,'',0,%d,%d,%d,%d,"
      "strftime('%%Y-%%m-%%dT%%H:%%M:%%S.00Z', CURRENT_TIMESTAMP),"
      "0,%llu,%u,0,'',0,%Q)",
      title, save, main_title, sub_title, detail, user_param, blocks,
      free_blocks, size_kib, (unsigned long long)account_id, user_id,
      game_title_id);

  if (sql == NULL)
  {
    sqlite3_close(dst_db);
    return -2;
  }

  ret = sqlite3_exec(dst_db, sql, NULL, NULL, &err);
  if (ret != SQLITE_OK)
  {
    logf("savedata.db update failed: %s", err ? err : sqlite3_errmsg(dst_db));
    if (err != NULL)
      sqlite3_free(err);
    sqlite3_free(sql);
    sqlite3_close(dst_db);
    return -3;
  }

  sqlite3_free(sql);
  sqlite3_close(dst_db);
  logf("savedata.db %s for %s/%s user %s", exists ? "updated" : "inserted",
    title, save, dest_user);
  return 0;
}

static int is_safe_token(const char *s)
{
  if (!s || !s[0])
    return 0;
  for (; *s; s++)
    if (!isalnum((unsigned char)*s) && *s != '_' && *s != '-' && *s != '.')
      return 0;
  return 1;
}

static void url_decode(char *s)
{
  char *r = s;
  char *w = s;

  while (*r)
  {
    if (*r == '%' && isxdigit((unsigned char)r[1]) &&
        isxdigit((unsigned char)r[2]))
    {
      char hex[3] = { r[1], r[2], 0 };
      *w++ = (char)strtol(hex, NULL, 16);
      r += 3;
    }
    else
    {
      *w++ = (*r == '+') ? ' ' : *r;
      r++;
    }
  }
  *w = 0;
}

static int query_value(const char *url, const char *key, char *out, size_t out_size)
{
  char needle[64];
  const char *p;
  size_t key_len;
  size_t i;

  snprintf(needle, sizeof(needle), "%s=", key);
  p = strstr(url, needle);
  if (!p)
    return 0;

  p += strlen(needle);
  key_len = strcspn(p, "& ");
  if (key_len >= out_size)
    key_len = out_size - 1;

  for (i = 0; i < key_len; i++)
    out[i] = p[i];
  out[key_len] = 0;
  url_decode(out);
  return out[0] != 0;
}

static int content_length_from_request(const char *request)
{
  const char *p;

  p = strstr(request, "Content-Length:");
  if (!p)
    p = strstr(request, "Content-length:");
  if (!p)
    p = strstr(request, "content-length:");
  if (!p)
    return 0;

  p = strchr(p, ':');
  if (!p)
    return 0;
  return atoi(p + 1);
}

static int receive_request_body_to_file(int fd, const char *request,
  ssize_t request_size, const char *path)
{
  const char *body;
  int content_length;
  int out_fd;
  int already;
  int remaining;
  char *buf;

  content_length = content_length_from_request(request);
  if (content_length <= 0)
    return -1;

  out_fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0644);
  if (out_fd < 0)
    return -2;

  body = strstr(request, "\r\n\r\n");
  if (!body)
  {
    close(out_fd);
    return -3;
  }
  body += 4;
  already = (int)(request_size - (body - request));
  if (already > content_length)
    already = content_length;
  if (already > 0 && write(out_fd, body, (size_t)already) != already)
  {
    close(out_fd);
    return -4;
  }

  remaining = content_length - already;
  buf = malloc(BUF_SIZE);
  if (!buf)
  {
    close(out_fd);
    return -5;
  }

  while (remaining > 0)
  {
    int want = remaining > BUF_SIZE ? BUF_SIZE : remaining;
    ssize_t n = read(fd, buf, (size_t)want);
    if (n <= 0)
    {
      free(buf);
      close(out_fd);
      return -6;
    }
    if (write(out_fd, buf, (size_t)n) != n)
    {
      free(buf);
      close(out_fd);
      return -7;
    }
    remaining -= (int)n;
  }

  free(buf);
  fsync(out_fd);
  close(out_fd);
  return 0;
}

static int export_decrypted_send(const char *url, int fd)
{
  char user[32];
  char title[32];
  char save[256];
  char src_dir[MAX_PATH_LEN];
  char src_img[MAX_PATH_LEN];
  char src_bin[MAX_PATH_LEN];
  char work_dir[MAX_PATH_LEN];
  char work_img[MAX_PATH_LEN];
  char work_bin[MAX_PATH_LEN];
  char mnt_src[MAX_PATH_LEN];
  char archive_path[MAX_PATH_LEN];
  FILE *archive;
  int ret;

  memset(user, 0, sizeof(user));
  memset(title, 0, sizeof(title));
  memset(save, 0, sizeof(save));

  if (!query_value(url, "user", user, sizeof(user)) ||
      !query_value(url, "title", title, sizeof(title)) ||
      !query_value(url, "save", save, sizeof(save)) ||
      !is_safe_token(user) || !is_safe_token(title) || !is_safe_token(save))
  {
    send_response(fd, 400, "Bad Request", "text/plain", "invalid query\n");
    return 400;
  }

  elevate();
  init_vsh_mount();
  mkdirs(WORK_ROOT);
  snprintf(work_dir, sizeof(work_dir), "%s/export_%ld_%ld",
    WORK_ROOT, (long)getpid(), (long)time(NULL));
  mkdirs(work_dir);
  snprintf(mnt_src, sizeof(mnt_src), "%s/mnt_src", work_dir);
  snprintf(src_dir, sizeof(src_dir), "/user/home/%s/savedata/%s", user, title);
  snprintf(src_img, sizeof(src_img), "%s/sdimg_%s", src_dir, save);
  snprintf(src_bin, sizeof(src_bin), "%s/%s.bin", src_dir, save);
  snprintf(work_img, sizeof(work_img), "%s/sdimg_%s", work_dir, save);
  snprintf(work_bin, sizeof(work_bin), "%s/%s.bin", work_dir, save);
  snprintf(archive_path, sizeof(archive_path), "%s/save.ps4sav", work_dir);

  logf("export begin %s/%s user %s", title, save, user);
  if (!file_exists(src_img) || !file_exists(src_bin))
  {
    send_response(fd, 404, "Not Found", "text/plain", "source save files not found\n");
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 404;
  }

  if (copy_file(src_img, work_img) != 0 || copy_file(src_bin, work_bin) != 0)
  {
    send_response(fd, 500, "Internal Server Error", "text/plain", "copy source failed\n");
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  ret = mount_save(work_img, work_bin, mnt_src, 1);
  if (ret < 0)
    ret = mount_save(src_img, src_bin, mnt_src, 1);
  if (ret < 0)
  {
    char msg[128];
    snprintf(msg, sizeof(msg), "mount source failed: 0x%x\n", ret);
    send_response(fd, 500, "Internal Server Error", "text/plain", msg);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  archive = fopen(archive_path, "wb");
  if (!archive)
  {
    unmount_save(mnt_src);
    send_response(fd, 500, "Internal Server Error", "text/plain", "create archive failed\n");
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }
  fprintf(archive, "PS4SAVEPACK1\n");
  ret = pack_dir_recursive(archive, mnt_src, "");
  fprintf(archive, "END\n");
  fclose(archive);
  sync();
  unmount_save(mnt_src);

  if (ret != 0)
  {
    send_response(fd, 500, "Internal Server Error", "text/plain", "pack archive failed\n");
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  send_file_response(fd, archive_path, "application/octet-stream");
  logf("export complete %s/%s user %s", title, save, user);
  delete_recursive(work_dir);
  rmdir(work_dir);
  return 200;
}

static int import_decrypted_from_archive(const char *url, const char *archive_path,
  char *result, size_t result_size)
{
  char dest_user[32];
  char source_user[32];
  char title[32];
  char save[256];
  char dst_dir[MAX_PATH_LEN];
  char dst_img[MAX_PATH_LEN];
  char dst_bin[MAX_PATH_LEN];
  char work_dir[MAX_PATH_LEN];
  char work_dst_img[MAX_PATH_LEN];
  char work_dst_bin[MAX_PATH_LEN];
  char mnt_dst[MAX_PATH_LEN];
  uint64_t archive_size;
  int use_existing_dest;
  int ret;

  memset(dest_user, 0, sizeof(dest_user));
  memset(source_user, 0, sizeof(source_user));
  memset(title, 0, sizeof(title));
  memset(save, 0, sizeof(save));

  if (!query_value(url, "user", dest_user, sizeof(dest_user)) ||
      !query_value(url, "title", title, sizeof(title)) ||
      !query_value(url, "save", save, sizeof(save)))
  {
    snprintf(result, result_size, "missing query parameter\n");
    return 400;
  }
  if (!query_value(url, "source_user", source_user, sizeof(source_user)))
    query_value(url, "Left_user", source_user, sizeof(source_user));
  if (source_user[0] == 0)
    snprintf(source_user, sizeof(source_user), "%s", dest_user);

  if (!is_safe_token(dest_user) || !is_safe_token(source_user) ||
      !is_safe_token(title) || !is_safe_token(save))
  {
    snprintf(result, result_size, "invalid token in query\n");
    return 400;
  }

  elevate();
  init_vsh_mount();
  mkdirs(WORK_ROOT);
  snprintf(work_dir, sizeof(work_dir), "%s/import_%ld_%ld",
    WORK_ROOT, (long)getpid(), (long)time(NULL));
  mkdirs(work_dir);
  snprintf(mnt_dst, sizeof(mnt_dst), "%s/mnt_dst", work_dir);
  snprintf(dst_dir, sizeof(dst_dir), "/user/home/%s/savedata/%s", dest_user, title);
  snprintf(dst_img, sizeof(dst_img), "%s/sdimg_%s", dst_dir, save);
  snprintf(dst_bin, sizeof(dst_bin), "%s/%s.bin", dst_dir, save);
  snprintf(work_dst_img, sizeof(work_dst_img), "%s/dst_sdimg_%s", work_dir, save);
  snprintf(work_dst_bin, sizeof(work_dst_bin), "%s/dst_%s.bin", work_dir, save);

  if (path_size(archive_path, &archive_size) != 0)
    archive_size = 32 * 1024 * 1024;
  use_existing_dest = file_exists(dst_img) && file_exists(dst_bin);
  logf("import begin %s/%s user %s existing=%d",
    title, save, dest_user, use_existing_dest);

  if (use_existing_dest)
  {
    if (copy_file(dst_img, work_dst_img) != 0 ||
        copy_file(dst_bin, work_dst_bin) != 0)
    {
      snprintf(result, result_size, "copy existing destination failed\n");
      delete_recursive(work_dir);
      rmdir(work_dir);
      return 500;
    }
  }
  else
  {
    ret = create_pfs_image(work_dst_img, work_dst_bin, archive_size + (8 * 1024 * 1024));
    if (ret < 0)
    {
      snprintf(result, result_size, "create destination pfs failed: 0x%x\n", ret);
      delete_recursive(work_dir);
      rmdir(work_dir);
      return 500;
    }
  }

  ret = mount_save(work_dst_img, work_dst_bin, mnt_dst, 0);
  if (ret < 0)
  {
    snprintf(result, result_size, "mount destination failed: 0x%x\n", ret);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  ret = unpack_archive(archive_path, mnt_dst, use_existing_dest);
  if (ret != 0)
  {
    unmount_save(mnt_dst);
    snprintf(result, result_size, "unpack archive failed: %d\n", ret);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  ret = patch_ps4_param_sfo(mnt_dst, dest_user);
  if (ret != 0)
  {
    unmount_save(mnt_dst);
    snprintf(result, result_size, "patch param.sfo failed: %d\n", ret);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }
  sync();
  unmount_save(mnt_dst);

  mkdirs(dst_dir);
  if (copy_file(work_dst_img, dst_img) != 0 ||
      copy_file(work_dst_bin, dst_bin) != 0)
  {
    snprintf(result, result_size, "copy destination files failed\n");
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  chmod(dst_img, 0644);
  chmod(dst_bin, 0644);
  ret = update_savedata_db(source_user, dest_user, title, save);
  sync();

  logf("import complete %s/%s user %s db=%d", title, save, dest_user, ret);
  snprintf(result, result_size, "ok\ndestination=%s\ndb_update=%d\n", dst_img, ret);
  logf("work files kept for stability: %s", work_dir);
  return 200;
}

static int import_decrypted_child(const char *url, const char *request,
  ssize_t request_size, int fd, char *result, size_t result_size)
{
  int ret;
  char archive_path[MAX_PATH_LEN];

  mkdirs(WORK_ROOT);
  snprintf(archive_path, sizeof(archive_path), "%s/import_body_%ld_%ld.ps4sav",
    WORK_ROOT, (long)getpid(), (long)time(NULL));

  ret = receive_request_body_to_file(fd, request, request_size, archive_path);
  if (ret != 0)
  {
    snprintf(result, result_size, "receive import body failed: %d\n", ret);
    unlink(archive_path);
    return 500;
  }

  /*
   * Execute the import in this process.  The previous fork/result-file
   * protocol could report wait_status=0 even when the child never produced
   * its result file, hiding the actual import error from the client.
   */
  ret = import_decrypted_from_archive(url, archive_path, result, result_size);
  unlink(archive_path);
  return ret;
}

static int sync_decrypted(const char *url, char *result, size_t result_size)
{
  char source_user[32];
  char dest_user[32];
  char title[32];
  char save[256];
  char src_dir[MAX_PATH_LEN];
  char src_img[MAX_PATH_LEN];
  char src_bin[MAX_PATH_LEN];
  char dst_dir[MAX_PATH_LEN];
  char dst_img[MAX_PATH_LEN];
  char dst_bin[MAX_PATH_LEN];
  char work_dir[MAX_PATH_LEN];
  char work_src_img[MAX_PATH_LEN];
  char work_src_bin[MAX_PATH_LEN];
  char work_dst_img[MAX_PATH_LEN];
  char work_dst_bin[MAX_PATH_LEN];
  char mnt_src[MAX_PATH_LEN];
  char mnt_dst[MAX_PATH_LEN];
  uint64_t src_size;
  int use_existing_dest;
  int ret;

  memset(source_user, 0, sizeof(source_user));
  memset(dest_user, 0, sizeof(dest_user));
  memset(title, 0, sizeof(title));
  memset(save, 0, sizeof(save));

  if (!query_value(url, "source_user", source_user, sizeof(source_user)) &&
      !query_value(url, "Left_user", source_user, sizeof(source_user)))
  {
    snprintf(result, result_size, "missing query parameter\n");
    return 400;
  }
  if (!query_value(url, "dest_user", dest_user, sizeof(dest_user)) ||
      !query_value(url, "title", title, sizeof(title)) ||
      !query_value(url, "save", save, sizeof(save)))
  {
    snprintf(result, result_size, "missing query parameter\n");
    return 400;
  }

  if (!is_safe_token(source_user) || !is_safe_token(dest_user) ||
      !is_safe_token(title) || !is_safe_token(save))
  {
    snprintf(result, result_size, "invalid token in query\n");
    return 400;
  }

  elevate();
  init_vsh_mount();
  mkdirs(WORK_ROOT);
  snprintf(work_dir, sizeof(work_dir), "%s/%ld", WORK_ROOT, (long)time(NULL));
  mkdirs(work_dir);
  snprintf(mnt_src, sizeof(mnt_src), "%s/mnt_src", work_dir);
  snprintf(mnt_dst, sizeof(mnt_dst), "%s/mnt_dst", work_dir);

  snprintf(src_dir, sizeof(src_dir), "/user/home/%s/savedata/%s", source_user, title);
  snprintf(src_img, sizeof(src_img), "%s/sdimg_%s", src_dir, save);
  snprintf(src_bin, sizeof(src_bin), "%s/%s.bin", src_dir, save);
  snprintf(dst_dir, sizeof(dst_dir), "/user/home/%s/savedata/%s", dest_user, title);
  snprintf(dst_img, sizeof(dst_img), "%s/sdimg_%s", dst_dir, save);
  snprintf(dst_bin, sizeof(dst_bin), "%s/%s.bin", dst_dir, save);
  snprintf(work_src_img, sizeof(work_src_img), "%s/sdimg_%s", work_dir, save);
  snprintf(work_src_bin, sizeof(work_src_bin), "%s/%s.bin", work_dir, save);
  snprintf(work_dst_img, sizeof(work_dst_img), "%s/dst_sdimg_%s", work_dir, save);
  snprintf(work_dst_bin, sizeof(work_dst_bin), "%s/dst_%s.bin", work_dir, save);

  logf("sync begin %s/%s %s -> %s", title, save, source_user, dest_user);

  if (!file_exists(src_img) || !file_exists(src_bin))
  {
    snprintf(result, result_size, "source save files not found: %s / %s\n",
      src_img, src_bin);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 404;
  }

  if (path_size(src_img, &src_size) != 0)
    src_size = 32 * 1024 * 1024;
  use_existing_dest = file_exists(dst_img) && file_exists(dst_bin);

  ret = copy_file(src_img, work_src_img);
  if (ret != 0)
  {
    snprintf(result, result_size, "copy source image failed: %d errno=%d\n", ret, errno);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  ret = copy_file(src_bin, work_src_bin);
  if (ret != 0)
  {
    snprintf(result, result_size, "copy source key failed: %d errno=%d\n", ret, errno);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  if (use_existing_dest)
  {
    logf("using existing destination pfs as base to preserve sce_sys");
    ret = copy_file(dst_img, work_dst_img);
    if (ret != 0)
    {
      snprintf(result, result_size, "copy existing destination image failed: %d errno=%d\n", ret, errno);
      delete_recursive(work_dir);
      rmdir(work_dir);
      return 500;
    }
    ret = copy_file(dst_bin, work_dst_bin);
    if (ret != 0)
    {
      snprintf(result, result_size, "copy existing destination key failed: %d errno=%d\n", ret, errno);
      delete_recursive(work_dir);
      rmdir(work_dir);
      return 500;
    }
  }
  else
  {
    logf("creating destination pfs, source size=%llu", (unsigned long long)src_size);
    ret = create_pfs_image(work_dst_img, work_dst_bin, src_size);
    if (ret < 0)
    {
      snprintf(result, result_size, "create destination pfs failed: 0x%x\n", ret);
      delete_recursive(work_dir);
      rmdir(work_dir);
      return 500;
    }
  }

  logf("mount source %s", work_src_img);
  ret = mount_save(work_src_img, work_src_bin, mnt_src, 0);
  if (ret < 0)
  {
    logf("mount copied source failed 0x%x; trying original %s", ret, src_img);
    ret = mount_save(src_img, src_bin, mnt_src, 0);
    if (ret < 0)
    {
      snprintf(result, result_size, "mount source failed: 0x%x\n", ret);
      delete_recursive(work_dir);
      rmdir(work_dir);
      return 500;
    }
  }

  logf("mount destination %s", work_dst_img);
  ret = mount_save(work_dst_img, work_dst_bin, mnt_dst, 0);
  if (ret < 0)
  {
    unmount_save(mnt_src);
    snprintf(result, result_size, "mount destination failed: 0x%x\n", ret);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  if (use_existing_dest)
    ret = copy_dir_recursive_skip_sce_sys(mnt_src, mnt_dst);
  else
    ret = copy_dir_recursive(mnt_src, mnt_dst);
  if (ret != 0)
  {
    unmount_save(mnt_dst);
    unmount_save(mnt_src);
    snprintf(result, result_size, "copy decrypted content failed: %d errno=%d\n", ret, errno);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  ret = patch_ps4_param_sfo(mnt_dst, dest_user);
  if (ret != 0)
  {
    unmount_save(mnt_dst);
    unmount_save(mnt_src);
    snprintf(result, result_size, "patch param.sfo failed: %d\n", ret);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }
  sync();
  unmount_save(mnt_dst);
  unmount_save(mnt_src);

  mkdirs(dst_dir);
  ret = copy_file(work_dst_img, dst_img);
  if (ret != 0)
  {
    snprintf(result, result_size, "copy destination image failed: %d errno=%d\n", ret, errno);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  ret = copy_file(work_dst_bin, dst_bin);
  if (ret != 0)
  {
    snprintf(result, result_size, "copy destination key failed: %d errno=%d\n", ret, errno);
    delete_recursive(work_dir);
    rmdir(work_dir);
    return 500;
  }

  chmod(dst_img, 0644);
  chmod(dst_bin, 0644);
  ret = update_savedata_db(source_user, dest_user, title, save);
  if (ret != 0)
    logf("savedata.db update returned %d", ret);
  sync();

  logf("sync complete %s/%s -> %s", title, save, dest_user);
  snprintf(result, result_size,
    "ok\nsource=%s\ndestination=%s\ndb_update=%d\n", src_img, dst_img, ret);

  logf("work files kept for stability: %s", work_dir);
  return 200;
}

static int delete_save_entry(const char *url, char *result, size_t result_size)
{
  char user[32];
  char title[32];
  char save[256];
  char save_dir[MAX_PATH_LEN];
  char img_path[MAX_PATH_LEN];
  char bin_path[MAX_PATH_LEN];
  char db_path[MAX_PATH_LEN];
  sqlite3 *db = NULL;
  char *sql = NULL;
  char *err = NULL;
  int ret;

  memset(user, 0, sizeof(user));
  memset(title, 0, sizeof(title));
  memset(save, 0, sizeof(save));

  if (!query_value(url, "user", user, sizeof(user)) ||
      !query_value(url, "title", title, sizeof(title)) ||
      !query_value(url, "save", save, sizeof(save)))
  {
    snprintf(result, result_size, "missing query parameter\n");
    return 400;
  }

  if (!is_safe_token(user) || !is_safe_token(title) || !is_safe_token(save))
  {
    snprintf(result, result_size, "invalid token in query\n");
    return 400;
  }

  elevate();
  snprintf(save_dir, sizeof(save_dir), "/user/home/%s/savedata/%s", user, title);
  snprintf(img_path, sizeof(img_path), "%s/sdimg_%s", save_dir, save);
  snprintf(bin_path, sizeof(bin_path), "%s/%s.bin", save_dir, save);
  snprintf(db_path, sizeof(db_path),
    "/system_data/savedata/%s/db/user/savedata.db", user);

  logf("delete begin %s/%s user %s", title, save, user);
  unlink(img_path);
  unlink(bin_path);

  ret = sqlite3_open(db_path, &db);
  if (ret == SQLITE_OK)
  {
    sql = sqlite3_mprintf(
      "DELETE FROM savedata WHERE title_id=%Q AND dir_name=%Q",
      title, save);
    if (sql != NULL)
    {
      ret = sqlite3_exec(db, sql, NULL, NULL, &err);
      if (ret != SQLITE_OK)
        logf("savedata.db delete failed: %s", err ? err : sqlite3_errmsg(db));
      sqlite3_free(sql);
    }
    if (err != NULL)
      sqlite3_free(err);
    sqlite3_close(db);
  }
  else if (db != NULL)
    sqlite3_close(db);

  rmdir(save_dir);
  sync();
  logf("delete complete %s/%s user %s", title, save, user);
  snprintf(result, result_size, "ok\n");
  return 200;
}

static int cleanup_stale_save_entries(const char *url, char *result, size_t result_size)
{
  char user[32];
  char db_path[MAX_PATH_LEN];
  char img_path[MAX_PATH_LEN];
  char bin_path[MAX_PATH_LEN];
  char titles[512][32];
  char saves[512][256];
  sqlite3 *db = NULL;
  sqlite3_stmt *stmt = NULL;
  char *sql = NULL;
  char *err = NULL;
  int ret;
  int count = 0;
  int i;

  memset(user, 0, sizeof(user));
  if (!query_value(url, "user", user, sizeof(user)) || !is_safe_token(user))
  {
    snprintf(result, result_size, "invalid user\n");
    return 400;
  }

  elevate();
  snprintf(db_path, sizeof(db_path),
    "/system_data/savedata/%s/db/user/savedata.db", user);

  ret = sqlite3_open(db_path, &db);
  if (ret != SQLITE_OK)
  {
    snprintf(result, result_size, "open savedata.db failed: %s\n",
      db ? sqlite3_errmsg(db) : "sqlite unavailable");
    if (db != NULL)
      sqlite3_close(db);
    return 500;
  }

  ret = sqlite3_prepare_v2(db,
    "SELECT title_id, dir_name FROM savedata", -1, &stmt, NULL);
  if (ret != SQLITE_OK)
  {
    snprintf(result, result_size, "read savedata.db failed: %s\n", sqlite3_errmsg(db));
    sqlite3_close(db);
    return 500;
  }

  while (sqlite3_step(stmt) == SQLITE_ROW && count < 512)
  {
    const char *title = (const char *)sqlite3_column_text(stmt, 0);
    const char *save = (const char *)sqlite3_column_text(stmt, 1);
    if (title == NULL || save == NULL)
      continue;

    snprintf(img_path, sizeof(img_path),
      "/user/home/%s/savedata/%s/sdimg_%s", user, title, save);
    snprintf(bin_path, sizeof(bin_path),
      "/user/home/%s/savedata/%s/%s.bin", user, title, save);

    if (access(img_path, F_OK) != 0 || access(bin_path, F_OK) != 0)
    {
      snprintf(titles[count], sizeof(titles[count]), "%s", title);
      snprintf(saves[count], sizeof(saves[count]), "%s", save);
      count++;
    }
  }
  sqlite3_finalize(stmt);

  for (i = 0; i < count; i++)
  {
    sql = sqlite3_mprintf(
      "DELETE FROM savedata WHERE title_id=%Q AND dir_name=%Q",
      titles[i], saves[i]);
    if (sql != NULL)
    {
      ret = sqlite3_exec(db, sql, NULL, NULL, &err);
      if (ret != SQLITE_OK)
        logf("stale savedata.db delete failed: %s", err ? err : sqlite3_errmsg(db));
      else
        logf("stale savedata.db entry removed: %s/%s user %s",
          titles[i], saves[i], user);
      sqlite3_free(sql);
    }
    if (err != NULL)
    {
      sqlite3_free(err);
      err = NULL;
    }
  }

  sqlite3_close(db);
  sync();
  snprintf(result, result_size, "ok\nremoved=%d\n", count);
  return 200;
}

static void send_log(int fd)
{
  FILE *fp;
  char *buf;
  long size;

  fp = fopen(SAVE_AGENT_LOG, "r");
  if (!fp)
  {
    send_response(fd, 200, "OK", "text/plain", "");
    return;
  }

  fseek(fp, 0, SEEK_END);
  size = ftell(fp);
  if (size < 0)
    size = 0;
  if (size > 32768)
  {
    fseek(fp, size - 32768, SEEK_SET);
    size = 32768;
  }
  else
    fseek(fp, 0, SEEK_SET);

  buf = malloc((size_t)size + 1);
  if (!buf)
  {
    fclose(fp);
    send_response(fd, 500, "Internal Server Error", "text/plain", "malloc failed\n");
    return;
  }

  fread(buf, 1, (size_t)size, fp);
  buf[size] = 0;
  fclose(fp);
  send_response(fd, 200, "OK", "text/plain", buf);
  free(buf);
}

static int sync_decrypted_child(const char *url, char *result, size_t result_size)
{
  pid_t pid;
  int status;
  int child_status;
  char result_path[MAX_PATH_LEN];
  char dest_user[32];
  FILE *fp;
  size_t n;

  memset(dest_user, 0, sizeof(dest_user));
  if (!query_value(url, "dest_user", dest_user, sizeof(dest_user)) ||
      !is_safe_token(dest_user))
  {
    snprintf(result, result_size, "invalid dest_user\n");
    return 400;
  }

  mkdirs(WORK_ROOT);
  snprintf(result_path, sizeof(result_path), "%s/result_%ld_%ld.txt",
    WORK_ROOT, (long)getpid(), (long)time(NULL));
  pid = fork();
  if (pid < 0)
  {
    snprintf(result, result_size, "fork failed errno=%d\n", errno);
    return 500;
  }

  if (pid == 0)
  {
    char child_result[2048];
    int ret;

    memset(child_result, 0, sizeof(child_result));
    ret = sync_decrypted(url, child_result, sizeof(child_result));
    fp = fopen(result_path, "w");
    if (fp != NULL)
    {
      fprintf(fp, "%d\n%s", ret, child_result);
      fclose(fp);
    }
    _exit(ret == 200 ? 0 : 1);
  }

  child_status = 500;
  waitpid(pid, &status, 0);

  fp = fopen(result_path, "r");
  if (fp == NULL)
  {
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0)
    {
      snprintf(result, result_size, "ok\n");
      return 200;
    }
    snprintf(result, result_size,
      "falha no payload ao preparar o save para o usuario destino %s. Verifique se o account_id do usuario destino nao esta zerado; com account_id 0 o save fica corrompido. wait_status=0x%x\n",
      dest_user, status);
    return 500;
  }

  if (fscanf(fp, "%d\n", &child_status) != 1)
    child_status = 500;
  n = fread(result, 1, result_size - 1, fp);
  result[n] = 0;
  fclose(fp);
  unlink(result_path);

  if (result[0] == 0)
    snprintf(result, result_size, "sync child returned status %d\n", child_status);

  return child_status;
}

static void handle_client(int fd)
{
  char request[2048];
  char method[8];
  char url[1024];
  char result[2048];
  ssize_t bytes_read;
  struct timeval client_timeout;
  int keepalive;

  memset(request, 0, sizeof(request));
  client_timeout.tv_sec = 120;
  client_timeout.tv_usec = 0;
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &client_timeout,
    sizeof(client_timeout));
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &client_timeout,
    sizeof(client_timeout));
  keepalive = 1;
  setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &keepalive, sizeof(keepalive));

  bytes_read = 0;
  while (bytes_read < (ssize_t)(sizeof(request) - 1))
  {
    ssize_t n = read(fd, request + bytes_read,
      sizeof(request) - 1 - (size_t)bytes_read);
    if (n <= 0)
      break;
    bytes_read += n;
    request[bytes_read] = 0;
    if (strstr(request, "\r\n\r\n") != NULL)
      break;
  }
  if (bytes_read <= 0)
    return;

  memset(method, 0, sizeof(method));
  memset(url, 0, sizeof(url));
  sscanf(request, "%7s %1023s", method, url);

  if (strcmp(method, "GET") == 0 && strncmp(url, "/api/ping", 9) == 0)
  {
    send_response(fd, 200, "OK", "text/plain", SAVE_AGENT_VERSION "\n");
    return;
  }

  if (strcmp(method, "GET") == 0 && strncmp(url, "/api/version", 12) == 0)
  {
    send_response(fd, 200, "OK", "text/plain",
      SAVE_AGENT_VERSION "\n"
      "sync_decrypted=experimental\n"
      "export_decrypted=experimental\n"
      "import_decrypted=experimental\n");
    return;
  }

  if (strcmp(method, "GET") == 0 && strncmp(url, "/api/log", 8) == 0)
  {
    send_log(fd);
    return;
  }

  if (strcmp(method, "GET") == 0 && strncmp(url, "/api/account_id", 15) == 0)
  {
    char user[32];
    uint64_t aid;

    memset(user, 0, sizeof(user));
    if (!query_value(url, "user", user, sizeof(user)) || !is_safe_token(user))
    {
      send_response(fd, 400, "Bad Request", "text/plain", "invalid user\n");
      return;
    }

    elevate();
    if (get_account_id_for_user(user, &aid) != 0 || aid == 0)
    {
      snprintf(result, sizeof(result), "account_id=0000000000000000\nuser=%s\n", user);
      send_response(fd, 409, "Conflict", "text/plain", result);
      return;
    }

    snprintf(result, sizeof(result), "account_id=%016llx\nuser=%s\n",
      (unsigned long long)aid, user);
    send_response(fd, 200, "OK", "text/plain", result);
    return;
  }

  if (strcmp(method, "GET") == 0 && strncmp(url, "/api/shutdown", 13) == 0)
  {
    send_response(fd, 200, "OK", "text/plain", "bye\n");
    g_stop = 1;
    return;
  }

  if (strcmp(method, "GET") == 0 && strncmp(url, "/api/export_decrypted", 21) == 0)
  {
    int status = export_decrypted_send(url, fd);
    logf("export request response sent status=%d", status);
    return;
  }

  if (strcmp(method, "POST") == 0 && strncmp(url, "/api/import_decrypted", 21) == 0)
  {
    int status = import_decrypted_child(url, request, bytes_read, fd, result, sizeof(result));
    if (status == 200)
      send_response(fd, 200, "OK", "text/plain", result);
    else if (status == 400)
      send_response(fd, 400, "Bad Request", "text/plain", result);
    else
      send_response(fd, 500, "Internal Server Error", "text/plain", result);
    logf("import request response sent status=%d", status);
    return;
  }

  if (strcmp(method, "POST") == 0 && strncmp(url, "/api/sync_decrypted", 19) == 0)
  {
    int status = sync_decrypted_child(url, result, sizeof(result));
    if (status == 200)
      send_response(fd, 200, "OK", "text/plain", result);
    else if (status == 400)
      send_response(fd, 400, "Bad Request", "text/plain", result);
    else if (status == 404)
      send_response(fd, 404, "Not Found", "text/plain", result);
    else
      send_response(fd, 500, "Internal Server Error", "text/plain", result);
    logf("sync request response sent status=%d", status);
    return;
  }

  if (strcmp(method, "POST") == 0 && strncmp(url, "/api/delete_save", 16) == 0)
  {
    int status = delete_save_entry(url, result, sizeof(result));
    if (status == 200)
      send_response(fd, 200, "OK", "text/plain", result);
    else if (status == 400)
      send_response(fd, 400, "Bad Request", "text/plain", result);
    else
      send_response(fd, 500, "Internal Server Error", "text/plain", result);
    logf("delete request response sent status=%d", status);
    return;
  }

  if (strcmp(method, "POST") == 0 && strncmp(url, "/api/cleanup_saves", 18) == 0)
  {
    int status = cleanup_stale_save_entries(url, result, sizeof(result));
    if (status == 200)
      send_response(fd, 200, "OK", "text/plain", result);
    else if (status == 400)
      send_response(fd, 400, "Bad Request", "text/plain", result);
    else
      send_response(fd, 500, "Internal Server Error", "text/plain", result);
    logf("cleanup request response sent status=%d", status);
    return;
  }

  if (strcmp(method, "GET") == 0 && strcmp(url, "/") == 0)
  {
    send_response(fd, 200, "OK", "text/plain",
      SAVE_AGENT_VERSION "\nUse /api/ping\n");
    return;
  }

  send_response(fd, 404, "Not Found", "text/plain", "not found\n");
}

int main(int argc, char **argv)
{
  int server_fd;
  int one;
  struct sockaddr_in server_addr;

  (void)argc;
  (void)argv;

  signal(SIGTERM, request_stop);
  signal(SIGINT, request_stop);

  setvbuf(stdout, NULL, _IONBF, 0);
  elevate();
  mkdirs(WORK_ROOT);
  g_log_fp = fopen(SAVE_AGENT_LOG, "a");
  logf("%s starting on port %d", SAVE_AGENT_VERSION, SAVE_AGENT_PORT);

  sceNetInit();

  server_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (server_fd < 0)
  {
    logf("socket failed: %s", strerror(errno));
    return 1;
  }

  one = 1;
  setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

  /*
   * Do not leave the main thread blocked forever in accept().  Apart from
   * making /api/shutdown deterministic, this gives the process a bounded
   * opportunity to observe termination during the PS4 power-off sequence.
   */
  {
    struct timeval accept_timeout;
    accept_timeout.tv_sec = 1;
    accept_timeout.tv_usec = 0;
    setsockopt(server_fd, SOL_SOCKET, SO_RCVTIMEO,
      &accept_timeout, sizeof(accept_timeout));
  }

  memset(&server_addr, 0, sizeof(server_addr));
  server_addr.sin_family = AF_INET;
  server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
  server_addr.sin_port = htons(SAVE_AGENT_PORT);

  if (bind(server_fd, (struct sockaddr *)&server_addr, sizeof(server_addr)) != 0)
  {
    logf("bind 0.0.0.0:%d failed: %s", SAVE_AGENT_PORT, strerror(errno));
    return 2;
  }

  if (listen(server_fd, 8) != 0)
  {
    logf("listen failed: %s", strerror(errno));
    return 3;
  }

  logf("%s listening on 0.0.0.0:%d", SAVE_AGENT_VERSION, SAVE_AGENT_PORT);

  while (!g_stop)
  {
    int client_fd;
    struct sockaddr_in client_addr;
    socklen_t client_len;

    client_len = sizeof(client_addr);
    client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &client_len);
    if (client_fd < 0)
    {
      if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)
        continue;
      continue;
    }

    handle_client(client_fd);
    close(client_fd);
  }

  close(server_fd);
  logf("%s stopped", SAVE_AGENT_VERSION);
  if (g_log_fp != NULL)
  {
    fclose(g_log_fp);
    g_log_fp = NULL;
  }
  return 0;
}
