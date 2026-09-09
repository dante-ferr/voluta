#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/socket.h>

static ssize_t (*real_write)(int fd, const void *buf, size_t count) = NULL;
static ssize_t (*real_send)(int sockfd, const void *buf, size_t len, int flags) = NULL;
static ssize_t (*real_sendto)(int sockfd, const void *buf, size_t len, int flags,
                              const struct sockaddr *dest_addr, socklen_t addrlen) = NULL;

static void init_symbols(void) {
    if (!real_write) {
        real_write = (ssize_t (*)(int, const void *, size_t))dlsym(RTLD_NEXT, "write");
    }
    if (!real_send) {
        real_send = (ssize_t (*)(int, const void *, size_t, int))dlsym(RTLD_NEXT, "send");
    }
    if (!real_sendto) {
        real_sendto = (ssize_t (*)(int, const void *, size_t, int, const struct sockaddr *, socklen_t))dlsym(RTLD_NEXT, "sendto");
    }
}

static int transform_hypr_cmd(const void *buf, size_t count, char *out_buf, size_t out_size) {
    if (!buf || count < 9 || memcmp(buf, "dispatch ", 9) != 0) {
        return 0;
    }

    const char *cmd = (const char *)buf;

    // If it's already using the Lua hl.dsp API, do not modify
    if (strstr(cmd, "hl.dsp.") != NULL) {
        return 0;
    }

    int handled = 0;

    if (strncmp(cmd, "dispatch workspace ", 19) == 0) {
        const char *arg = cmd + 19;
        char target[128] = {0};
        size_t len = count - 19;
        if (len >= sizeof(target)) len = sizeof(target) - 1;
        memcpy(target, arg, len);
        target[len] = '\0';
        while (len > 0 && (target[len-1] == '\n' || target[len-1] == '\r' || target[len-1] == ' ')) {
            target[--len] = '\0';
        }
        if (strncmp(target, "name:", 5) == 0) {
            snprintf(out_buf, out_size, "dispatch hl.dsp.focus({ workspace = \"%s\" })", target + 5);
        } else {
            snprintf(out_buf, out_size, "dispatch hl.dsp.focus({ workspace = \"%s\" })", target);
        }
        handled = 1;
    } else if (strncmp(cmd, "dispatch focusworkspaceoncurrentmonitor ", 40) == 0) {
        const char *arg = cmd + 40;
        char target[128] = {0};
        size_t len = count - 40;
        if (len >= sizeof(target)) len = sizeof(target) - 1;
        memcpy(target, arg, len);
        target[len] = '\0';
        while (len > 0 && (target[len-1] == '\n' || target[len-1] == '\r' || target[len-1] == ' ')) {
            target[--len] = '\0';
        }
        if (strncmp(target, "name:", 5) == 0) {
            snprintf(out_buf, out_size, "dispatch hl.dsp.focus({ workspace = \"%s\", on_current_monitor = true })", target + 5);
        } else {
            snprintf(out_buf, out_size, "dispatch hl.dsp.focus({ workspace = \"%s\", on_current_monitor = true })", target);
        }
        handled = 1;
    } else if (strncmp(cmd, "dispatch togglespecialworkspace", 31) == 0) {
        const char *arg = cmd + 31;
        while (*arg == ' ') arg++;
        char target[128] = {0};
        size_t len = strlen(arg);
        if (len >= sizeof(target)) len = sizeof(target) - 1;
        memcpy(target, arg, len);
        target[len] = '\0';
        while (len > 0 && (target[len-1] == '\n' || target[len-1] == '\r' || target[len-1] == ' ')) {
            target[--len] = '\0';
        }
        if (len > 0) {
            snprintf(out_buf, out_size, "dispatch hl.dsp.workspace.toggle_special(\"%s\")", target);
        } else {
            snprintf(out_buf, out_size, "dispatch hl.dsp.workspace.toggle_special()");
        }
        handled = 1;
    }

    if (handled) {
        if (getenv("WAYBAR_SHIM_DEBUG")) {
            fprintf(stderr, "[hypr-shim] %s -> %s\n", cmd, out_buf);
        }
        return 1;
    }

    return 0;
}

ssize_t write(int fd, const void *buf, size_t count) {
    init_symbols();
    char new_cmd[512];
    if (transform_hypr_cmd(buf, count, new_cmd, sizeof(new_cmd))) {
        return real_write(fd, new_cmd, strlen(new_cmd));
    }
    return real_write(fd, buf, count);
}

ssize_t send(int sockfd, const void *buf, size_t len, int flags) {
    init_symbols();
    char new_cmd[512];
    if (transform_hypr_cmd(buf, len, new_cmd, sizeof(new_cmd))) {
        return real_send(sockfd, new_cmd, strlen(new_cmd), flags);
    }
    return real_send(sockfd, buf, len, flags);
}

ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
               const struct sockaddr *dest_addr, socklen_t addrlen) {
    init_symbols();
    char new_cmd[512];
    if (transform_hypr_cmd(buf, len, new_cmd, sizeof(new_cmd))) {
        return real_sendto(sockfd, new_cmd, strlen(new_cmd), flags, dest_addr, addrlen);
    }
    return real_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
}
